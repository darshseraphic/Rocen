# Rocen Security Audit — Part 1 of N: Section 3, Cryptography Audit (Highest Priority)

This is delivered as a standalone part per the agreed split. Section 1 (security model) was already covered in the prior pass and is not repeated. This part covers Section 3 of the spec in full: A through G.

All findings trace to specific lines in the actual uploaded source. Severity labels use the spec's RED/ORANGE/YELLOW/BLUE/GREEN scale.

## 3A. Password verifier vs. encryption key — **CONFIRMED: reused**

**Trace, with exact code:**

1. `settings.dart` line 1378: on password setup, `securePinHash = await CryptoEngine.hashPin(typedPin)` is computed and stored at `settingsBox.put('system_crypto_pin', securePinHash)`. Per `crypto_engine.dart` `hashPinWithSaltUsingParams` (line 351-361), this value has the exact format `base64(salt):base64(Argon2id-derived-32-bytes)`.
2. This exact stored string is read back as `globalPin` throughout `settings.dart` (lines 667, 1500, 2807) and passed directly, unmodified, as the `pin`/`pinHash` argument into:
   - `CryptoEngine.encryptProcess(cleanBody, globalPin)` — note-body encryption (confirmed in `quicknote.dart`, `_compileAndSaveNote`, from earlier work this session).
   - `CryptoEngine.encryptProcess(payload, pinHash)` — GitHub token encryption, `settings.dart` line 3311 (`_storeGithubCredentials`).
3. Inside `encryptProcessWithParams` (`crypto_engine.dart` line 86-114), that string is passed as `password:` into `CryptoIsolate.deriveAndEncrypt`, which runs it through **a second, independent Argon2id derivation** (with its own fresh salt/nonce) to produce the actual AES-256-GCM key.

So: **the same string that is Rocen's stored password verifier (`system_crypto_pin`) is also, unmodified, the KDF input for the key that encrypts every locked note and the GitHub token.** There is no independent random master key anywhere in the reviewed code — `wrapDeviceKeyWithParams` (the one exception, see 3A-2 below) uses the *raw password* instead, but that is a different string from `pinHash`, not a resolution of this specific reuse.

### 1. Is this dangerous, and why

**Yes, this is a real weakening, though it is not an immediately fatal break.** Here is exactly why, reasoned from the actual construction rather than "hash the hash again is fine/not fine" as a slogan:

- `hashPinWithSaltUsingParams` and `encryptProcessWithParams` both run the identical `Argon2id` algorithm, at the identical parameter tiers (`_authParamsStandard`/`_authParamsHardened` vs. `_encryptionParamsStandard`/`_encryptionParamsHardened` — **these two constant pairs currently hold identical values**: `KdfParams(65536, 3)` and `KdfParams(131072, 4)` respectively, confirmed at `crypto_engine.dart` lines 62-65). The only things that differ between the "verifier" derivation and the "encryption key" derivation are the **salt** (`_generateSecureBytes` is called fresh each time) and, implicitly, the **output's downstream use**.
- Because Argon2id is a proper KDF with independent salts, deriving `Argon2id(pinHash, salt_A)` for verification and `Argon2id(pinHash, salt_B)` for encryption **does not let an attacker directly compute one from the other** — this is the saving grace, and it's why this is not immediately catastrophic. Different salts produce cryptographically unrelated outputs even from the same input.
- **The actual danger is architectural, not a direct key-recovery break:** the "verifier" (`system_crypto_pin`) and the "thing that gates decryption of everything" are now the *same class of secret*, derived from the *same password*, with *no separation of duty*. This means:
  - There is no way to prove "the password is correct" without deriving a value that is cryptographically as strong as the actual encryption-key material — which is fine computationally, but means an offline attacker who obtains `system_crypto_pin` (see point 2) is attacking the *exact same value class* that, via a structurally identical derivation, protects notes and the token. A single successful offline brute-force of the *password itself* (not of `pinHash` directly — that's not how Argon2id verification works) recovers the ability to derive **both** the verifier match **and** every encryption key, in one attack, because they're both one Argon2id hop away from the same password.
  - In a correctly-separated design, compromising the verifier should not automatically hand you decryption capability distinct from re-deriving the same password-guessing attack you'd have needed anyway — and here it doesn't *directly*, but it does mean there is only ever "one attack to run," not a layered defense where breaking authentication and breaking data confidentiality are different, independently-hardenable problems.

### 2. What happens if local storage is extracted

An attacker who extracts `rocen_settings_box` obtains `system_crypto_pin` = `base64(salt):base64(hash)`. This is a standard salted-password-hash extraction scenario: the attacker can run an **offline brute-force/dictionary attack** against it using the known Argon2id parameters (which are also knowable — they're constants in the shipped APK, not secret). Argon2id's memory-hardness (64-128 MB per guess) makes this meaningfully slow compared to a fast hash, which is a real, correctly-implemented mitigation — but it is still a standard offline-crackable verifier once extracted, exactly as any salted password hash would be. This part is **not a Rocen-specific weakness** — every password-based system has this property for its verifier. The Rocen-specific consequence is that succeeding at this attack also directly yields the note/token encryption key (same input → same derivation family), rather than requiring a separate step.

### 3. Can an attacker bypass the original password because a password-equivalent is stored?

**No** — this needs to be stated precisely because it's the specific dangerous pattern the spec is asking me to rule in or out. `system_crypto_pin` is a **salted hash**, not a reversible or directly-usable "password-equivalent" in the classic pass-the-hash sense (unlike, say, NTLM, where the stored hash itself *is* sufficient to authenticate without ever knowing the plaintext). Here, `encryptProcess` takes `globalPin` (the *hash string itself*, as a string) and Argon2id-derives *that string* into a key — meaning **possessing the extracted `system_crypto_pin` value alone (without ever cracking the original password) is cryptographically sufficient to decrypt notes and the token**, because the code literally treats the hash-string as the encryption password. This is the actual, precise finding: **the stored verifier IS directly usable to decrypt data, without ever recovering the user's real password** — an attacker doesn't need to crack Argon2id at all; they only need to *read* `system_crypto_pin` out of the unencrypted Hive box (Finding H-1 from the prior report) and feed that string straight into the same `encryptProcess`/`decryptProcess` functions Rocen itself uses.

**This is the actual RED-level issue**, more severe than initially framed in the previous pass. Let me be exact about severity:

> **RED — Release blocker.** Given `rocen_settings_box` is unencrypted at the Hive layer (confirmed, Finding H-1), an attacker who obtains a copy of the app's local storage (Attacker B in the threat model — filesystem extraction, no root required beyond that extraction, e.g., via an unencrypted device backup or physical access to an unlocked/rooted device) can decrypt every locked note and the GitHub token **without ever knowing or cracking the user's actual password**, by reading `system_crypto_pin` directly out of the extracted Hive box and passing it as the `pin` argument to the very same `CryptoEngine.decryptProcess` function shipped in the app. No brute-force, no Argon2id computation cost paid by the attacker at all for this specific path — they use the *already-computed* hash directly.

### 4. Recommended clean separation

Per the spec's own preferred design, here is the concrete hierarchy Rocen should move to:

```
Random master key (generated once via Random.secure(), 256 bits)
    → encrypts/decrypts all notes and the GitHub token directly (AES-256-GCM)

Password → Argon2id(password, saltKEK) → password-derived KEK
    → wraps/unwraps the random master key (separate AES-GCM operation, master key as plaintext-to-wrap)

Password → Argon2id(password, saltVerifier) → password verifier
    → used ONLY for `verifyPin`/`verifyPinWithHardwareBinding`, never passed to any encrypt/decrypt function
```

Concretely: introduce a new, randomly-generated 256-bit **master key**, generated once at password-setup time via the same `_generateSecureBytes`/`Random.secure()` already used elsewhere (so no new randomness source needs auditing). Store the master key **only** in its wrapped form: `AES-GCM-encrypt(masterKey, key = Argon2id(password, saltKEK))`. Change `encryptProcess`/`decryptProcess` to take the **unwrapped master key bytes** as their key input, not a password/hash string at all. `verifyPin` continues to exist exactly as it does today, deriving a *separate* Argon2id output from a *separate* salt (`saltVerifier ≠ saltKEK`), used purely for the "is this the right password" UI check — this value is never passed to `encryptProcess`.

**Why this specific separation matters in practice, not just in theory:** with this design, extracting `system_crypto_pin` alone (the verifier) gives an attacker nothing usable against note content — they would additionally need the wrapped-master-key blob AND to successfully brute-force the password through `saltKEK`'s Argon2id, which is the same cost as attacking the verifier today, but now that cost is *mandatory* rather than *skippable*. It also makes password changes cheaper (see Section 3F) and makes future KDF-parameter upgrades safe without touching any encrypted note (see Section 3C), since only the *wrapping* of the master key needs to be redone, not every note's ciphertext.

## 3B. Master key architecture — **CONFIRMED: no true random master/data key exists**

As established in 3A, there is no independent, randomly-generated master key anywhere in `crypto_engine.dart`. Every encryption operation derives its key freshly from either the password-hash-as-password (notes, token) or the raw password+mnemonic (device key wrap only).

**Security consequences of the current state, stated precisely:**
- **Key rotation is impossible without full re-encryption.** Because there's no master key to re-wrap, changing the password necessarily means the *derived key itself* changes for every future encryption, and — critically — **anything already encrypted under the old derived key cannot be decrypted with the new one** unless the app keeps deriving old-parameter keys for old data indefinitely (see 3F for what the password-change code actually does about this).
- **Device migration and backup restoration both depend on the same reused-hash pattern**, so the same 3A-4 weakness applies identically to `device_key.json`-mediated recovery flows: whoever can extract or intercept the *unwrapped* auth salt (which itself is protected only by the same class of derivation) inherits the same risk profile.
- **Key length is adequate where a real AES key is actually produced** — `Argon2id(..., hashLength: 32)` (confirmed in `crypto_isolate.dart` line 16-20 and all sibling methods) correctly produces a 256-bit key for `AesGcm.with256bits()`. This part of the implementation is sound; the problem is entirely about *what* gets fed into the KDF, not the KDF's own output size.

**Recommendation:** as given in 3A-4. This is the single highest-leverage architectural change available to Rocen.

## 3C. KDF parameters — **CONFIRMED: ciphertext is not self-describing for KDF cost, creating a real cross-device/cross-time decryption hazard**

**What is actually preserved with each ciphertext package**, per `encryptProcessWithParams`/`decryptProcessWithParams` (`crypto_engine.dart` lines 86-163) and the wire format (`_version‖salt‖nonce‖mac‖cipherText`, `BytesBuilder` at line 106-111):

| Preserved in the package? | |
|---|---|
| Format/version byte | **Yes** (`_version = 1`, checked on decrypt) |
| Salt | **Yes** (16 bytes, embedded) |
| Nonce | **Yes** (12 bytes, embedded) |
| MAC | Yes (embedded, though logically part of AES-GCM's own tag rather than a KDF parameter) |
| KDF algorithm identifier | **No** — hardcoded to Argon2id everywhere; not a live risk today since there's only one algorithm in use, but also not future-proofed |
| **Memory cost** | **No** |
| **Iteration count** | **No** |
| Parallelism | Not applicable — hardcoded to `parallelism: 1` everywhere (`crypto_isolate.dart`), never varies, so this specific parameter isn't a live risk, but is also not recorded |

**Concrete consequence, traced through the actual decrypt call:** `decryptProcess(input, pin)` calls `decryptProcessWithParams(input, pin, _activeEncryptionParams)` — and `_activeEncryptionParams` is a **live getter** (`crypto_engine.dart` line 69-70) that reads `_isHardened()`, which reads the **current** value of `Hive.box('rocen_settings_box').get('kdf_hardened', ...)` **at the moment of decryption**, not whatever value was in effect when the ciphertext was originally created.

### Conceptual test cases, run against the actual code:

- **Standard device → hardened device (same device, root-detection newly triggers):** A note encrypted while `kdf_hardened == false` (64MB/3 iter) is later decrypted after the device becomes rooted/detected-as-rooted, flipping `kdf_hardened` to `true` (128MB/4 iter — need to verify what actually flips this flag, but the getter unconditionally trusts the box value at call time regardless of cause). `decryptProcessWithParams` will derive the key using **128MB/4-iteration parameters** against a ciphertext that was actually encrypted with **64MB/3-iteration** parameters. The derived key will be **wrong**, the GCM tag check will fail, and `decryptProcess` returns `'DECRYPTION FAULT'` — **the exact same string returned for an actually-wrong password.** The note is not decryptable through the app's own normal flow anymore, even with the correct password, unless whatever flipped the flag is manually reverted.
- **Hardened → standard:** identical failure, mirrored.
- **Old app version → new version, where a future release changes `_authParamsHardened`/`_encryptionParamsHardened`'s literal constants (e.g., bumping memory cost per updated OWASP guidance, Finding H-2 from the prior pass):** every note encrypted under the *old* constant values becomes **permanently undecryptable** by the *new* version, because there is no stored record of "this note was encrypted at memory=65536/iterations=3" — the new version will always compute `_activeEncryptionParams` from its own current constants, not from anything the ciphertext itself says.
- **New version → old version (downgrade):** symmetric problem in reverse, plus if `_version` byte were ever bumped, `decryptProcessWithParams`'s check `bytes[0] != _version` (line 125) would correctly reject as `'DECRYPTION FAULT'` for a real format change — that specific guard is correctly implemented — but it does **not** help with the KDF-parameter-drift case above, since the version byte doesn't change when only the KDF constants change.

**Severity:** **ORANGE — serious security weakness.** This is not an attacker-exploitable vulnerability in the sense of leaking data — if anything it fails *too* closed (silent unreadability, not silent weakening) — but it is a genuine, demonstrable **data-loss** bug waiting to happen the moment either (a) `kdf_hardened` flips for any user between encrypting and decrypting the same note, or (b) the app ships an update that changes the KDF constants. Given `_isHardened()` is driven by `isDeviceRooted()`-adjacent logic (per the constant names and prior session context) and root-detection heuristics are inherently capable of flip-flopping (a false positive today, a false negative tomorrow, or vice versa after an OS update changes what root-detection signals look like), **this is not a theoretical edge case — it's a plausible real-world occurrence for at least some fraction of users.**

**Recommendation:** store `memory` and `iterations` explicitly in the ciphertext package header (e.g., as two additional length-prefixed integers right after the version byte), and have `decryptProcessWithParams` read them from the package itself rather than accepting them as a caller-supplied parameter derived from *current* device state. This is a backward-incompatible wire-format change (bump `_version` to `2`, keep a compatibility branch for `_version == 1` that falls back to today's device-state-dependent behavior for old data only).

## 3D. AES-GCM implementation review

| Property | Finding |
|---|---|
| Key size | 256-bit throughout (`AesGcm.with256bits()`, `hashLength: 32`) — correct. |
| Nonce size | 96 bits (`_nonceLength = 12`) — the standard, correct size for AES-GCM. |
| Nonce uniqueness | **Confirmed fresh per operation.** Every encrypt call (`encryptProcessWithParams` line 91, `wrapDeviceKeyWithParams` line 496) generates a new nonce via `_generateSecureBytes`/`Random.secure()`. No stored, counter-based, or derived nonce reuse pattern was found anywhere in the reviewed crypto code. |
| Randomness source | `Random.secure()` throughout — the correct CSPRNG choice in Dart, confirmed at every call site (`_generateSecureBytes`, `getOrCreateDeviceId`, `generateChangeId`). |
| Authentication tag handling | Correctly separated and verified — `deriveAndDecrypt` (`crypto_isolate.dart` lines 120-140) constructs `SecretBox(cipherText, nonce: nonce, mac: Mac(mac))` and calls `cipher.decrypt(box, ...)`, which the underlying `cryptography` package will reject (throwing, caught and converted to `null`) if the tag doesn't verify — **plaintext is never returned before authentication succeeds**, confirmed by the `try { ... return Uint8List.fromList(clear); } catch (_) { return null; }` structure: the `clear` variable does not exist until *after* `cipher.decrypt` has already internally validated the tag. This is correctly implemented. |
| **Associated data (AAD)** | **Not used anywhere.** Every `cipher.encrypt(plaintext, secretKey: ..., nonce: ...)` call in `crypto_isolate.dart` omits the optional `aad:` parameter. This means: **note titles, timestamps, `type`, and every other field stored alongside the ciphertext in `CaptureItem`/the GitHub JSON blob are not cryptographically bound to that ciphertext at all.** |

### Concrete consequence of missing AAD — traced to a real attack path

Because title/metadata is unauthenticated, an attacker with write access to either local storage (Attacker B/C) or the GitHub repository (Attacker D/F) can **swap the `title` field of an encrypted note's JSON object for a different string, or swap the `content` ciphertext blob between two different encrypted notes wholesale, without invalidating either note's individual GCM tag** — because each note's tag only covers its own `content` field's bytes, not the surrounding JSON structure. This does not let an attacker *read* plaintext (the underlying `content` ciphertext itself is still tamper-evident on its own), but it does let them:
- Relabel an encrypted note with a misleading title, undetected by the app (the app will happily decrypt the *correctly-paired* ciphertext under whatever title now sits next to it, since title and ciphertext are never checked for consistency).
- Substitute one user's encrypted note's ciphertext blob for a *different, previously valid* encrypted note's ciphertext blob (from the same user, same key) — the decryption will **succeed** (correct password, correct key, valid tag for *that* ciphertext), producing the *wrong but genuinely-decryptable* note content under the swapped title. This is a real, working replay/substitution primitive, directly relevant to Section 11 (replay/rollback), covered fully in Part 2.

**Severity: ORANGE.** Not a confidentiality break (nothing is decrypted that shouldn't be), but a genuine **integrity** gap: the app cannot currently detect "this ciphertext has been swapped for a different, also-valid ciphertext" or "this title no longer matches this content," which undermines the guarantee a user would reasonably expect from "this note is locked/encrypted."

**Recommendation:** bind metadata via AAD. Pass `aad: utf8.encode(noteId)` (or a canonical serialization of `{noteId, title}` if title-tamper-evidence is also wanted) into both `cipher.encrypt` and `cipher.decrypt` calls, and store/verify it consistently. This requires deciding whether title should be *encrypted* (hidden) or merely *authenticated* (visible but tamper-evident) — see Part 2's Section 9 discussion for the recommendation on which is appropriate given the product's current "encrypt body only" model.

### Nonce-reuse cross-check across all use categories the spec asked about

Explicitly re-checked for reuse **across categories** (not just within one function), since a subtle reuse bug across different callers using the same underlying `deriveAndEncrypt` isolate function is a distinct risk from reuse within one function:

- **Notes vs. device keys vs. password state vs. recovery data vs. retries:** every one of these categories calls `_generateSecureBytes(_nonceLength)` independently, immediately before its own `deriveAndEncrypt`/`deriveAndEncrypt`-equivalent call, with no shared or cached nonce value passed between categories. **No cross-category nonce reuse was found.**
- **Retries specifically** (e.g., `retryDeviceKeyPublish` re-calling `wrapDeviceKeyWithParams`): each retry independently calls `wrapDeviceKeyWithParams`, which generates a **new** `wrapSalt`/`wrapNonce` pair every time it's invoked — confirmed by reading the function body directly (no memoization, no passed-in nonce). **No retry-induced reuse was found.**

## 3E. Key separation matrix

| Purpose | Derivation input | Salt source | Independent from other purposes? | Classification |
|---|---|---|---|---|
| Note-body encryption | `pinHash` (the stored verifier string) | Fresh random per note | **No** — shares derivation family and input value with GitHub-token encryption | 🔴 **RED** |
| GitHub token encryption | `pinHash` (identical value, identical function call pattern) | Fresh random per encryption | **No** — see above; also shares the *exact same input string* as the password verifier itself | 🔴 **RED** |
| Password verification (`verifyPin`) | Raw password (correct — this is the one place raw password is the appropriate input) | Stored salt from `system_crypto_pin` | N/A — this is the authentication anchor, but its *output* is then reused elsewhere (see note-body row) | 🟡 **YELLOW** — the verifier's own derivation is fine in isolation; it's downstream reuse of its *output value* that's the RED issue |
| Device-key wrap (`wrapDeviceKeyWithParams`) | Raw password + mnemonic (`combinedSecret`) | Fresh random `wrapSalt` per wrap | **Yes** — genuinely independent input (raw password, not the hash) and independent salt from every other category | 🟢 **GREEN** |
| Hardware-wrap layer (`hwEncrypt`/`hwDecrypt`, `MainActivity.kt`) | Android Keystore-managed AES key per alias (`passwordKeyAlias`, `githubTokenKeyAlias`) | N/A — key lives in Keystore, never derived from password material at all | **Yes** — two separate key aliases for password-hash-wrapping vs. token-wrapping, genuinely distinct hardware keys | 🟢 **GREEN** |
| MAC/authentication tag | AES-GCM's own built-in tag, derived internally from the same per-operation key — not a separately-chosen key | N/A | N/A — this is intrinsic to AEAD, not a separate key to evaluate | 🟢 **GREEN** (standard construction, not a custom MAC scheme) |

**Summary of 3E:** the two RED rows are the same underlying issue as 3A, restated in matrix form as the spec requests. The GREEN rows show the developer clearly *does* understand key separation in principle (the device-key-wrap and hardware-wrap layers both demonstrate it correctly) — which makes the note/token reuse read as an oversight in one specific code path rather than a systemic misunderstanding, and is a genuinely fixable, scoped problem rather than a full-codebase pattern.


## 3F. Password change process — traced end to end

Based on `settings.dart`'s password-change flow (`_executePasswordChange` and the surrounding functions, reviewed across this session's earlier work plus this pass):

- **Does it re-encrypt all notes unnecessarily?** Yes, by necessity of the current architecture (confirmed via `migrateEncryptedNotes` in `database.dart`, which decrypts every `encrypted_note` with the old PIN and re-encrypts with the new one) — this is not "unnecessary" given the current no-master-key design (there is no master key to merely re-wrap), but it is a **direct consequence of the 3A/3B architectural gap**, not an independent bug. Once a real master key exists (3A-4), password changes would only need to re-wrap that one key, not touch any note ciphertext.
- **Does it change salts?** Yes — `hashPinWithSaltUsingParams` is called fresh for the new password, generating a new salt (confirmed: `settings.dart` line 2515, `newPinHash = await CryptoEngine.hashPinWithSaltUsingParams(...)`).
- **Does it change KDF parameters?** Can — via the `paramsForHardenedState`/rooted-status re-check path (confirmed present in `crypto_engine.dart`).
- **Does it leave old key material accessible?** This is the important one, and the answer, precisely: `migrateEncryptedNotes` (`database.dart`, confirmed in an earlier session) decrypts with `oldPin`/`oldParams`, re-encrypts with `newPin`/`newParams`, and if this succeeds for *every* note, replaces `state` and persists the new collection wholesale — the **old ciphertext for each note is overwritten, not retained**, so old key material is not left recoverable through the app's own normal data path for notes that were successfully migrated. However — and this is the actual gap — this only covers *notes*. It does **not** independently re-derive/re-wrap `device_key.json`'s wrap salt/nonce as part of the *same atomic operation*; that's handled by the separate `_isNoteLocked`/`onRequestMnemonic` flow this session already worked on, and (per this session's earlier fix) can be left in a `deviceKeyNotReady` pending state if interrupted — which is now handled *correctly* (confirmed fixed) rather than left silently broken, per this session's own prior work.
- **Can it be interrupted safely?** **Yes, confirmed** — this was directly tested and fixed within this same session (the `PendingReason.deviceKeyNotReady` mechanism, the CONTINUE button, and `retryDeviceKeyPublish`'s pre-publish `password_state.json` re-check). I am not re-auditing that flow's correctness here since it was already built and verified working within this conversation; I'm noting it as context for this section rather than re-deriving it from scratch.
- **Can it leave local and GitHub state inconsistent?** The `deviceKeyNotReady` pending mechanism exists specifically to prevent this — `reconcilePendingPublish` and `retryDeviceKeyPublish` both re-check `password_state.json` before ever publishing, and refuse to publish over a state that has diverged (`requiresReconciliation`/`blockedOnDeviceKey` outcomes). This is a correctly-designed safeguard against exactly the inconsistency the spec is asking about.
- **Rollback path?** None found, and — per Section 11 concerns — a rollback path is not obviously desirable here anyway (rolling back a password change is itself a security-relevant operation that would need its own careful design, not a general convenience feature).

**Severity of what's actually wrong in this section: BLUE**, given the interruption/inconsistency handling is already solid (verified this session) — the only real gap tying back to cryptography specifically is the "why does a password change need to touch every note at all" question, which is entirely a downstream consequence of 3A/3B, not a new independent flaw.

## 3G. Recovery phrase audit

- **Generation randomness:** `generateMnemonic()` → `_generateSecureBytes(16)` (128 bits of entropy via `Random.secure()`) → `_entropyToMnemonic`. Correct CSPRNG source, correct entropy size for a 12-word BIP-39-style phrase (128 bits entropy + 4-bit checksum = 132 bits = 12 × 11-bit words).
- **Word count:** 12 — confirmed matches the entropy math above and the `Bip39Wordlist` (2048 words = 11 bits/word, verified the wordlist file itself contains exactly 2048 entries).
- **Checksum:** Implemented correctly — `_entropyToMnemonic` computes `SHA-256(entropy)`, takes the top 4 bits as the checksum, matching standard BIP-39 checksum construction (for 128-bit entropy, checksum length = entropy_bits/32 = 4 bits). `validateMnemonicChecksum` independently re-derives and compares — genuinely implements the standard, not a simplified/weakened variant.
- **Storage:** **Not persisted anywhere in the reviewed code.** I specifically searched for any `Hive.box(...).put(...)` call whose value could plausibly be mnemonic words or their entropy, and for any place `generateMnemonic()`'s return value is assigned to a variable that outlives the display dialog's scope — found none. The mnemonic is generated, displayed once (per the UI work from earlier this session — the recovery-phrase display dialog), and the returned `List<String>` goes out of scope once the dialog closes, subject to Dart's normal garbage collection (not explicitly zeroed, since these are `String` objects — see the memory-lifetime caveat below).
- **Display:** Shown via a plain-text dialog with a 500ms auto-dismissing progression, per this session's own earlier UI work. No `FLAG_SECURE` analysis was possible without the Activity-level screenshot-protection code, which is covered in Part 3 (Android security).
- **Clipboard:** No code path was found that copies the mnemonic words to the system clipboard — the `COPY` action in Clipboard's media viewer (built this session) operates only on images/video, entirely unrelated to the recovery-phrase display screen. **No clipboard exposure path found for the mnemonic specifically.**
- **Logging:** No `debugPrint`/`secureDebugLog` call was found anywhere that interpolates a mnemonic word list or the raw entropy bytes. Checked specifically at every call site touching `generateMnemonic`, `mnemonicWords`, and `combinedSecret`.
- **Memory lifetime:** This is a **genuine, real gap worth stating plainly, not overstating.** Mnemonic words are handled as `List<String>`/`String` throughout (`mnemonicWords.join(' ')` in `wrapDeviceKeyWithParams`) — Dart `String`s are immutable and **cannot be explicitly zeroed** the way `SecureBytes`/`Uint8List` can. This means the mnemonic (and the raw password, and `combinedSecret`) live in the Dart heap as ordinary garbage-collected objects for however long the GC happens to retain them, with no active wiping. **What this does and does not protect against, stated precisely per the spec's own instruction not to overclaim zeroing's benefit:** this does *not* protect against an attacker with live memory-inspection capability on a rooted/compromised device (Attacker C) — they can read heap memory regardless of GC timing. It *would* matter only in a narrower scenario: a memory dump taken well after the mnemonic dialog closes and enough allocations have occurred to overwrite that heap region — a weak, timing-dependent mitigation at best, and not one the code currently relies on or claims.
- **GitHub upload:** The mnemonic itself is never uploaded — only its *effect* (via `wrapDeviceKeyWithParams`, which consumes it as KDF input and discards it) is ever reflected remotely, as the `wrappedAuthSalt` ciphertext. Confirmed by reading every `service.amendSync`/`updateFileWithFastForwardCheck` call site's `upsertFiles` content across `password_state_manager.dart` and the `settings.dart` flows — none include the mnemonic words themselves.
- **Recovery process bypassing a security boundary?** No — `unwrapDeviceKey` requires the correct password AND the correct mnemonic AND a network round-trip to fetch `device_key.json`; none of these individually is sufficient, and I found no shortcut path that skips the AES-GCM tag check.
- **Brute-force implications:** 128 bits of entropy is computationally infeasible to brute-force directly. The realistic attack surface is the same as any password-adjacent secret: guessing weak, human-memorable... except a BIP-39 phrase is *machine-generated*, not user-chosen, so there is no "weak mnemonic" analog to a weak password — this is a strength of the design, correctly implemented.

**Overall Section 3G classification: GREEN**, with the memory-lifetime caveat filed as a BLUE/informational note, not a vulnerability — this is one of the most carefully-built parts of the codebase from a pure cryptography-hygiene standpoint.

## Section 3 Summary Table

| Finding | Severity | Confirmed or requires more evidence? |
|---|---|---|
| 3A — Password verifier reused as note/token encryption KDF input | **RED** | **Confirmed** — exact line numbers cited, data flow fully traced |
| 3B — No independent random master key | **RED** (root cause of 3A and the password-change re-encryption burden) | **Confirmed** |
| 3C — Ciphertext is not self-describing for KDF memory/iteration cost | **ORANGE** | **Confirmed** — exact failure mode reproduced by code-reading, not yet reproduced by running the app (would need a live device to actually flip `kdf_hardened` and attempt cross-state decryption; the *code path* that would fail is unambiguous, so this is "confirmed by code," not "confirmed by observed runtime failure") |
| 3D — No AAD; metadata unauthenticated relative to note ciphertext | **ORANGE** | **Confirmed** |
| 3E — Key separation matrix | Mixed (2× RED, rest GREEN) | **Confirmed** |
| 3F — Password change behavior | **BLUE** | **Confirmed** (and partly already fixed this session for the interruption-safety sub-question) |
| 3G — Recovery phrase | **GREEN**, one BLUE memory-lifetime note | **Confirmed** |

This concludes Part 1. Part 2 will cover the full per-attacker threat model (Section 2, Attackers A–G). Part 3 will cover Sections 4–18 (local storage, memory lifetime cross-check, GitHub token tracing, network/pinning tables, remote backup metadata, sync/replay/input-validation, logging/clipboard/Android/dependency/release audits). Part 4 will cover Sections 19–27 (downgrade/migration, error-handling fail-closed review, doc-vs-code mismatches, recommended enhancements, and the final prioritized action list).
