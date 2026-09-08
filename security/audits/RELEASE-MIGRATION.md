# Rocen Security Audit — Part 4 of 4: Sections 14–18 & Final Consolidated Action List

Concludes the audit begun in Part 1 (Cryptography), Part 2 (Threat Model), and Part 3 (Storage/Memory/Network/Sync/Logging/Android/Dependencies). This part covers release/supply-chain detail, downgrade/migration testing, a full fail-open/fail-closed review of every exception-handling path checked, documentation-vs-code mismatches, and closes with one consolidated, prioritized action list spanning all four parts.

## Section 14 — Release & Supply-Chain Detail

Expands Part 2's Attacker-G finding with the specific checklist items the spec requests.

| Item | Status | Evidence |
|---|---|---|
| Release build signing | **Debug keystore** — confirmed, `build.gradle.kts`, `buildTypes { release { signingConfig = signingConfigs.getByName("debug") } }` | Restated from prior report Finding H-4; this is the single most severe release-hygiene issue found across the whole audit |
| Reproducible builds | Not evaluated — no build-reproducibility tooling (`--split-debug-info` determinism, source-date-epoch pinning, etc.) was found referenced anywhere, and reproducibility was not independently tested (would require actually running two clean builds and diffing them, which is outside static review) | Not confirmed — requires dynamic testing |
| Version/commit/checksum publication | **None found.** No `SECURITY.md`, no release-notes template referencing a git tag, commit hash, or APK SHA-256 | Confirmed absent by their absence from every uploaded file |
| ProGuard/R8 configuration | Default-only; `proguard-rules.pro` referenced in `build.gradle.kts` but absent on disk, confirmed via the supplied `configuration.txt`/`seeds.txt`/`usage.txt` build artifacts showing no third rule-source in the merged configuration | Restated from prior report Finding H-5, with the artifact-based evidence already gathered |
| Obfuscation of Dart code (`--obfuscate`) | Not confirmed either way from the available files — `flutter build apk --release` does not enable Dart-level obfuscation by default unless explicitly passed the `--obfuscate --split-debug-info=<dir>` flags, and no CI/build script was supplied showing whether this flag is used | Not confirmed — requires the actual build invocation/CI config, not supplied |
| Dependency lock file (`pubspec.lock`) | Not supplied for this review | Not confirmed — cannot verify exact transitive dependency versions actually shipped, only the version *ranges* declared in `pubspec.yaml` |
| Third-party native plugin provenance (`smart_dev_pinning_plugin`, `super_native_extensions`) | Sourced from pub.dev per standard Flutter dependency resolution; no vendoring/checksum-pinning beyond pub.dev's own package-integrity mechanisms was found configured | This is normal, standard practice for the Flutter ecosystem — not a Rocen-specific gap, included here for completeness per the spec's checklist |

**Overall Section 14 severity: RED**, driven entirely by the debug-signing issue, which is a genuine release blocker as already established. Every other item in this section is either "not confirmed due to missing artifacts" (properly caveated, not assumed either way) or "standard practice, no gap found."

## Section 15 — Downgrade & Migration Testing

**Question asked:** if the encrypted-package format version, KDF parameters, or on-disk schema ever changes, does Rocen handle old data gracefully?

**Confirmed, with direct code evidence:**

1. **Format version (`_version` byte):** checked for strict equality only (`crypto_engine.dart` lines 125, 183) — no branching logic exists for "if this is an older version, interpret it the old way." The current behavior for a version mismatch is a clean, safe failure (`StateError`/format exception), **not** silent misinterpretation of incompatible bytes — this is the correct *safe* failure mode, but it means **any future format change requires a dedicated migration pass over all existing data before the version byte can be bumped**, or every existing encrypted note becomes permanently unreadable the moment the app updates. No such migration mechanism currently exists in the reviewed code.
2. **KDF parameter drift (`kdf_hardened` flag):** already established in Part 1, Section 3C, as a **live, reproducible-by-code-reading hazard** — decryption silently uses whatever parameters are "active" *right now*, not whatever was active when the ciphertext was created. This is the single most concrete "migration" gap in the entire codebase, because it doesn't even require a version bump to trigger — it can happen between any two decrypt attempts on the same device if the rooted-status heuristic ever changes its answer.
3. **`migrateLegacyRemoteFileId`/`migrateEncryptedNotes`** (`database.dart`): these two functions demonstrate the developer *has* previously built migration logic for other schema changes (legacy remote-filename format, and full-database re-encryption during a password change) — this is genuinely useful context: **the pattern of "how to migrate this app's data safely" is already established and working elsewhere in the codebase**, which makes fixing the two gaps above (encryption-format version, KDF-parameter recording) a matter of extending an existing, proven pattern rather than inventing a new one from scratch.
4. **App downgrade (installing an older APK version over a newer one's data):** not directly testable via static review — would require either dynamic testing (installing two different build versions in sequence) or a full version-history of the on-disk schema across releases, neither of which was available. **Filed as: "Not confirmed — requires dynamic testing across at least two real app versions."**

**Overall Section 15 severity: ORANGE**, same root cause as Part 1's 3C finding — restated here specifically under the "migration testing" framing the spec requests, to confirm it was evaluated from this angle too, not just the cryptography angle.


## Section 16 — Fail-Open vs. Fail-Closed: Full Exception-Handling Review

Every `catch` block in `crypto_engine.dart` (10 total) was individually reviewed for this section, not sampled — this is the specific, exhaustive check the spec's fail-closed requirement calls for.

| Function | Failure behavior | Correctly fail-closed? |
|---|---|---|
| `isDeviceRooted()` | Returns `false` (assumes **not rooted**) on any channel exception | **No — fails open.** See detailed finding below. |
| `_isHardened()` | Returns `false` (assumes **standard, weaker** KDF tier) on any Hive-read exception | **No — fails open**, same category as above, and compounds it: two independent fail-open defaults both defaulting toward the *weaker* security posture rather than the stronger one |
| `decryptProcess`/`decryptProcessWithParams` | Returns the literal string `'DECRYPTION FAULT'` on any exception (wrong password, corrupted data, or an unrelated bug) | **Yes — fails closed.** No plaintext is ever returned on any exception path; a genuine decrypt failure and an unrelated internal error are indistinguishable to the caller, which is the safe direction to be ambiguous in. |
| `verifyPin` | Returns `false` on any exception | **Yes — fails closed.** Confirmed directly, shown above. |
| `hardwareWrap`/`hardwareUnwrap` | Returns `null` on any exception; callers (confirmed in `settings.dart`) treat `null` as "hardware wrap unavailable, fall back to software-only encryption" — **not** as "treat the data as already secured" | **Yes — fails closed in the sense that it never claims a wrap succeeded when it didn't**, though see the cross-reference below for what "falling back to software-only" means given Finding 3A |
| `keyTier` | Returns `null`/defaults to `'tee'` string on exception (per the earlier-read code, `cachedTiers[alias] ?? 'tee'`) | **Borderline — informational only.** This value is used for *display/diagnostic* purposes (telling the user which hardware tier protected their data), not for any security *decision* — reporting `'tee'` as a fallback when the real tier is unknown is a minor accuracy issue, not a security fail-open, since nothing in the reviewed code branches its actual crypto behavior based on this specific return value. |
| `splitForBackup`/`mergeFromBackup` | Both throw `StateError` on version mismatch — no swallowed exception, no fallback value at all | **Yes — fails closed** (in fact, the strictest of all the reviewed functions: it doesn't even offer a soft `null`/`false`, it throws) |

### Detailed finding: the two fail-open defaults are a real, if narrow, security weakening

**File:** `crypto_engine.dart`, lines 40-51 (`isDeviceRooted`) and 53-60 (`_isHardened`).

**Why this matters concretely:** the entire purpose of root detection in this codebase is to decide whether to apply the **hardened** (128MB/4-iteration) or **standard** (64MB/3-iteration) Argon2id tier — the implicit threat model being "a rooted device is more exposed, so spend more KDF cost to compensate." If the native `isRooted` channel call throws for *any* reason (a bug in the native root-detection library, an OS update that changes the platform-channel's behavior, a transient error), the app silently proceeds as if the device is **not** rooted — the *less* cautious assumption — rather than the *more* cautious one. The correct, security-conservative default for an ambiguous/unknown root status should be to **assume the worse case** (rooted) and apply the stronger KDF tier, not the weaker one, precisely because the failure mode of "I unnecessarily used the stronger tier on a safe device" (slightly slower password checks) is far less costly than "I used the weaker tier on an actually-compromised device."

**Severity: ORANGE.** This does not expose data outright — the *worst* outcome is using a KDF tier that is still independently reasonable (64MB/3 iterations is not weak in absolute terms, per Part 1's OWASP comparison) — but it is a clear, demonstrable instance of the exact fail-open anti-pattern the spec asked me to specifically hunt for, and it's compounding: both functions independently default toward the weaker posture, for unrelated failure conditions.

**Recommendation:** invert both defaults. `isDeviceRooted()`'s catch block should set `_cachedRootStatus = true` (assume rooted, apply hardened parameters) rather than `false`. `_isHardened()`'s catch block should similarly default to `true`. This is a minimal, two-line change with no architectural implications, unlike most of this audit's other recommendations.

### Cross-reference: how the hardware-wrap fallback interacts with Finding 3A

Confirmed in Part 2 (Attacker B): when `hardwareWrap` correctly and safely returns `null` on failure, the calling code in `settings.dart` falls back to storing the token via `CryptoEngine.encryptProcess(payload, pinHash)` alone — which, per Finding 3A, is the weaker of the two protection tiers already. This isn't a new fail-open bug in the hardware-wrap function itself (it behaves correctly, reporting failure honestly) — but it does mean the **overall system's** fail-open behavior, when hardware wrapping isn't available, is to silently accept the already-weaker 3A-affected protection level with **no user-visible indication** that this happened. This was already noted in Part 2's storage table; restated here specifically under the fail-open framing to show it was evaluated from this angle too.

## Section 17 — Documentation vs. Code Mismatches

### D-1 (headline finding, carried through from the original pass, now with full, exact evidence)

**CHANGELOG.md, `[0.4.0]` entry, "Security & Cryptography" section, states verbatim:**
> "Removed the **'NO SAME LETTER IN UPPER + LOWER'** password restriction. The rule rejected passwords when the same alphabetic letter appeared in both uppercase and lowercase forms. The restriction was removed from the displayed password requirements and from the actual password-validity checks."

**Actual code, `crypto_engine.dart`, confirmed this pass at exact current line numbers:**
- Line 291, inside `isPasswordComplexityValid` (the actual gating function used to accept/reject a password): `if (lowerLetters.intersection(upperLetters).isNotEmpty) return false;`
- Line 316, inside `missingPasswordRequirements` (the function that generates the user-facing requirement list): `missing.add('NO SAME LETTER IN UPPER + LOWER');`

**Both halves of the CHANGELOG's claim are false as of the current code.** The rule is enforced in the validity check (contradicting "removed... from the actual password-validity checks") and still displayed to the user (contradicting "removed from the displayed password requirements"). This is not a partial or nuanced mismatch — it is a complete, direct contradiction between what the documentation asserts and what the code does, on both dimensions the CHANGELOG specifically claims.

**Why this matters beyond "the changelog is wrong":** a developer or auditor relying on the CHANGELOG's claim (as this very audit's earlier passes initially did, before verifying directly) would believe this restriction no longer applies, and could reasonably build other logic, tests, or user-facing help text on that false premise. Given the audit's own governing instruction — "do not assume the README, CHANGELOG, comments, or developer claims are correct; treat the actual source code as truth" — this finding exists precisely to demonstrate why that instruction matters: it was correct to distrust the CHANGELOG here.

**Recommendation:** this needs a decision, not just a fix in one direction. Either (a) actually remove the rule from `crypto_engine.dart` to match the documented intent, or (b) correct the CHANGELOG to accurately reflect that the rule remains in place. Given the rule itself is not a security weakness (a *stricter* password policy than documented is the safer direction to be wrong in, as noted in the original pass), **the lower-risk fix is correcting the documentation**, not removing a working security control to match a changelog entry that may itself have been the actual mistake (e.g., an intended-but-never-shipped change, or a change that was reverted without updating the changelog).

### Additional doc-vs-code checks performed this pass, found consistent (no mismatch)

- **CHANGELOG's claim about `password_state.json`/`device_key.json` exclusion from pull/refresh:** verified consistent with the actual code in `quicknote.dart`'s pull-and-reconcile flow (confirmed directly in this session's much earlier work fixing this exact feature) — the CHANGELOG's description matches what the code does.
- **CHANGELOG's claim about the CONTINUE button / interrupted-password-change recovery:** verified consistent — this was built and directly tested within this same session; the CHANGELOG's description accurately reflects the implemented behavior, including the pre-publish `password_state.json` re-check.
- **CHANGELOG's claims about the Clipboard media overhaul** (zoom sequence, crop fixes, video support, etc.): all verified consistent with the actual final code state, since every one of these was built, debugged, and directly tested within this same session with real device logs — no daylight was found between what's claimed and what's implemented for this entire section of the changelog.

**This selective-verification result is itself a useful, fair finding to state plainly:** the CHANGELOG is **not uniformly unreliable** — the mismatch is isolated to one specific, older entry (the `[0.4.0]` password-policy claim), while everything added or changed later in the same document, during this session, checks out accurately. This suggests the mismatch is a stale/incomplete-edit artifact from before this session began, not a pattern of the documentation process being generally untrustworthy.

## Section 18 — Recommended Security Enhancements (Not Yet Filed as Findings)

Distinct from the "recommendation" attached to each finding above — this section is for constructive additions the spec asks for that go beyond fixing what's broken:

1. **Biometric unlock as an optional, additional gate** (confirmed absent in Part 3, Section 12) — layering `local_auth` on top of the existing password would not replace the cryptographic password-derived key (which must remain password-based, since biometrics can't feed a KDF the same way), but could gate *access to attempt* decryption at the UI layer, adding a meaningful friction layer against Attacker A specifically (someone with brief physical access to an unlocked phone).
2. **A dedicated `SECURITY.md`** documenting the trust model, supported threat scenarios, and a responsible-disclosure contact — directly addresses Section 14's finding that no such documentation exists, and is standard practice for any app handling user secrets.
3. **Provisioning the backup SPKI pin** (Part 2/3, already flagged as H-3) — low-effort, meaningfully reduces the operational risk of a hard connectivity outage on GitHub's next key rotation.
4. **A settings-screen indicator showing which protection tier the GitHub token is actually under** (hardware-wrapped vs. software-only fallback) — directly addresses the "no user-visible indication" gap noted in this part's fail-closed cross-reference, turning a silent fallback into an informed one.
5. **Migrating off `hive`/`hive_flutter` to a maintained, encryption-capable fork** (`hive_plus_secure` or equivalent) — directly resolves Finding H-1 with comparatively low migration cost given the API surface is designed to be a near-drop-in replacement (per the pub.dev evidence gathered in Part 3).

## Final Consolidated, Prioritized Action List (All Four Parts)

Ordered by actual risk-reduction-per-effort, not strictly by severity label alone — a RED finding requiring a full architectural rebuild is listed after an ORANGE finding fixable in one line, where the smaller fix meaningfully reduces risk sooner.

### Do before any real-world release (release blockers)

1. **Replace the debug keystore with a real release signing key** (Part 2/4, Finding H-4/Section 14). One-time setup, blocks every other supply-chain concern from being moot.
2. **Create a real `android/app/proguard-rules.pro`**, even minimal, and re-verify via a fresh release build + diff against `seeds.txt`/`usage.txt` that no crypto-relevant class or the `Isolate.run` entry point is stripped/renamed (Part 1/4, Finding H-5).
3. **Invert the two fail-open defaults** in `isDeviceRooted()` and `_isHardened()` to assume the worse case on failure (Part 4, Section 16). Two-line fix, immediately closes a real gap.
4. **Correct the CHANGELOG's password-policy claim** to match actual code behavior, or remove the rule from code to match the claim — pick one, but stop the current direct contradiction (Part 4, Finding D-1).

### High-priority, plan before shipping password/crypto changes

5. **Introduce an independent, randomly-generated master key**, with the password/verifier/KEK properly separated per Part 1's 3A-4 design (Part 1, Findings 3A/3B). This is the single highest-leverage architectural fix in the whole audit — it also simplifies the password-change re-encryption burden (Part 1, 3F) as a side effect.
6. **Make the ciphertext package self-describing for KDF parameters** (store memory/iterations alongside salt/nonce, version-bump the format with a compatibility branch for old data) (Part 1, Finding 3C / Part 4, Section 15).
7. **Add AAD binding note metadata (at minimum, note ID) to the encryption/decryption calls**, closing both the metadata-tamper gap (Part 1, 3D) and providing the mechanism for anti-replay binding (Part 3, Section 9).
8. **Add an explicit monotonicity check inside `publishNewState`** (`newGeneration > remoteGeneration`) so the function is self-defending regardless of caller discipline (Part 3, Section 9).

### Medium-priority hardening, meaningfully reduces real exposure

9. **Encrypt the Hive boxes**, ideally by migrating to a maintained fork with built-in encryption (Part 3, Section 13 evidence directly supports this path) (Part 1/3, Finding H-1).
10. **Set `android:allowBackup="false"`** explicitly (Part 1, Finding H-6). One manifest line.
11. **Scope `FLAG_SECURE` screenshot protection to every screen displaying sensitive content**, not just the Settings tab, and specifically to the moments a secret is actually on-screen rather than the whole screen indiscriminately (Part 2, Attacker A).
12. **Add a payload-size limit before `jsonDecode`** on any GitHub-fetched content (Part 3, Section 10).
13. **Provision a backup SPKI pin** (Part 2/3, Finding H-3).
14. **Stop persisting the stable `deviceId` in the shared plaintext `password_state.json`**; keep only `deviceNumber` remotely, with `deviceId` mapped locally per-device (Part 3, Section 8 / Finding P-1).
15. **Zero the plaintext `Uint8List` buffers in `crypto_isolate.dart`**, not just the derived key (Part 3, Section 5).

### Lower-priority, worth doing but not urgent

16. Surface `amendSync`'s silent partial-failure (dropped delete/rename requests) to callers instead of a bare success (Part 1 prior-report Finding I-2, carried through).
17. Reconcile the `secureDebugLog` vs. raw `debugPrint` inconsistency once `debug_log.dart` itself is reviewed (Part 3, Section 11 — this item is itself gated on obtaining that still-missing file).
18. Consider biometric unlock as an additional UI-layer gate (Part 4, Section 18).
19. Add a `SECURITY.md` and a release-checksum/commit-hash publication process (Part 4, Sections 14/18).
20. Add an explicit `network_security_config.xml` as defense-in-depth alongside the existing app-layer pinning (Part 3, Section 7).

### Still outstanding — cannot be resolved by code review alone

- **Obtain and review `smart_dev_pinning_plugin`'s native source** — this is the single largest remaining blind spot in the entire audit; the app's *entire* network-security posture rests on a component that was never independently verified.
- **Obtain and review `debug_log.dart`** — needed to confirm or refute whether `secureDebugLog` actually provides meaningful redaction over raw `debugPrint`.
- **Obtain `pubspec.lock`** to confirm exact shipped transitive dependency versions rather than declared ranges.
- **Dynamic testing**: install a real build, deliberately flip `kdf_hardened` between encrypt and decrypt of the same note to confirm the Part 1/3C failure mode actually reproduces as predicted; test an actual app downgrade scenario; capture live network traffic to independently confirm the pinning behavior end-to-end rather than relying on static code review of the Dart-side contract alone.

This concludes the four-part Rocen security audit. Across all parts, the strongest-evidenced, most consequential finding remains **Finding 3A** (Part 1): the password verifier doubles as the note/token encryption key input, meaning a cold local-storage extraction — not even a fully-compromised, rooted device — is sufficient to defeat note encryption entirely, without cracking the user's actual password. The second most consequential is the **debug-signed release build** (Part 2/4), which undermines every other protection in this audit if a tampered build can be distributed as if it were legitimate. Both are fixable without a full rewrite, and both are listed first in the action list above for exactly that reason.
