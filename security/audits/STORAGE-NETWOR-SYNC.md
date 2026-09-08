# Rocen Security Audit — Part 3 of N: Sections 4–18

Continues from Part 1 (Cryptography) and Part 2 (Threat Model). Covers local storage, memory lifetime, GitHub token trace, network, remote metadata, sync/replay mechanics, input validation, logging/clipboard/screenshot, Android checklist, and dependency audit.

## Section 4 — Local Storage: Complete Per-Value Table

Traced directly from `database.dart` (`CaptureItem`) and every `settingsBox.put`/`.get` call site found across `settings.dart` and `password_state_manager.dart`.

| Stored value | Box | Encrypted at Hive layer? | Encrypted/hashed at application layer before storage? | Sensitivity |
|---|---|---|---|---|
| `CaptureItem.content` (type `note`) | `rocen_captures_box` | No | No | High if the user considers it private, but this is the explicitly-chosen "unlocked" note type |
| `CaptureItem.content` (type `encrypted_note`) | `rocen_captures_box` | No | **Yes** — AES-256-GCM ciphertext (see Part 1, 3A for the key-derivation caveat) | High |
| `CaptureItem.title` (any type) | `rocen_captures_box` | No | **No, ever** — confirmed via `toMap()`/`fromMap()`, no conditional branch encrypts title regardless of `type` | Medium-High — a title can itself be sensitive ("Divorce lawyer notes", "Account recovery codes") even when the body is locked |
| `CaptureItem.id`, `.timestamp`, `.type`, `.backupEnabled`, `.remoteFileId`, `.pendingReviewAfterSync` | `rocen_captures_box` | No | No (not applicable — structural metadata) | Low |
| `system_crypto_pin` (password verifier) | `rocen_settings_box` | No | Yes, is itself an Argon2id hash — but see Part 1 Finding 3A: this value doubles as the encryption KDF input | **Critical** |
| `last_active_crypto_pin_snapshot` | `rocen_settings_box` | No | Same format as `system_crypto_pin` | **Critical** — a second copy of an equally sensitive value; see new finding below |
| `github_access_encrypted` | `rocen_settings_box` | No | Yes — AES-GCM, optionally further hardware-wrapped (conditional protection, see Part 2 Attacker B) | Critical |
| `hw_wrapped_pin` | `rocen_settings_box` | No | Yes — Android Keystore-wrapped | High (see new finding below on its relationship to `system_crypto_pin`) |
| `device_key_owned_repo` | `rocen_settings_box` | No | No | Low — just an `owner/repo` string, not itself a secret, though it does disclose which specific GitHub repository is in use to anyone with local access |
| `kdf_hardened` | `rocen_settings_box` | No | No (boolean flag) | Low on its own, but drives the KDF-parameter-drift risk in Part 1, 3C |
| `device_id` | `rocen_settings_box` | No | No | Low locally, but see Part 2 Attacker-D/Section-8 for its exposure once synced |
| `known_password_generation`, `known_password_change_id` | `rocen_settings_box` | No | No | Low — non-secret coordination bookkeeping |
| `password_state_pending_generation`, `_pending_change_id`, `_pending_reason` | `rocen_settings_box` | No | No | Low |
| `secure_failed_attempts`, `secure_lockout_until` | `rocen_settings_box` | No | No | **Attacker-relevant, not confidentiality-sensitive** — see Section 9 below: this is a genuine, exploitable weak point specifically because it's unencrypted and unauthenticated |
| `mnemonic_failed_attempts`, `mnemonic_lockout_until` | `rocen_settings_box` | No | No | Same as above, for the mnemonic-recovery attempt path specifically |
| `isDark` (theme) | `rocen_settings_box` | No | No | None — included only for completeness per the spec's request for an exhaustive table |
| `last_backup_sync_at` | `rocen_settings_box` | No | No | Low |
| Imported media file paths (Clipboard) | `rocen_captures_box`, `type: 'imported_clip'` | No | No | Depends entirely on content — the app treats these as ordinary files, no special protection, consistent with how the OS's own gallery treats them |

### New finding: `last_active_crypto_pin_snapshot` — a second copy of the critical verifier, purpose unclear from the code alone

**File:** `settings.dart` line 2517 (`await settingsBox.put('last_active_crypto_pin_snapshot', newPinHash);`), written at the same moment as `system_crypto_pin` during a password change.

I looked for every place this value is subsequently *read* to understand its purpose, since a second, seemingly-redundant copy of the most sensitive local value is worth explaining precisely rather than assuming it's dead code.

```
grep for "last_active_crypto_pin_snapshot" reads: only the one write site found in the reviewed excerpt of settings.dart.
```

**This is filed as: "Not confirmed — requires additional evidence."** I did not have visibility into every read site across the full 4900+ line `settings.dart` file in this pass (my grep was against sections I'd already loaded into context from earlier sessions, not a fresh full-file re-scan) — it's plausible this value is read elsewhere as a rollback/comparison anchor for detecting an interrupted password change, which would be a reasonable design. Flagging this explicitly rather than guessing: **if this snapshot is used to reconstruct or compare against the live password hash during error recovery, it does not introduce a new class of risk beyond what `system_crypto_pin` itself already represents** (same value, same storage box, same exposure). If it is genuinely unused/dead, it's a minor hygiene item (unused sensitive data should be removed, not kept "just in case"), not a live vulnerability either way.

### `hw_wrapped_pin` vs `system_crypto_pin` — relationship clarified

`hw_wrapped_pin` is written via the `MainActivity.kt` `hwEncrypt` channel, using `system_crypto_pin`'s value as the plaintext input to be hardware-wrapped (this is the standard "wrap the software-derived secret with a hardware key for an extra layer" pattern, and is architecturally sound — it means an attacker needs *either* `system_crypto_pin` (unencrypted, per Finding 3A/H-1) *or* successful Keystore/StrongBox extraction, not both, to reach the underlying secret, which is a reasonable defense-in-depth even though the *primary* copy remains unencrypted). This is filed as: **the hardware wrap is a genuine additional protection layer, but it is optional/parallel rather than a full replacement for the plaintext copy, since `system_crypto_pin` itself is never deleted after `hw_wrapped_pin` is created** (confirmed: no `settingsBox.delete('system_crypto_pin')` call was found anywhere). This means the weakest of the two paths (the unwrapped plaintext value) still fully determines the actual security level for Attacker B, regardless of the hardware wrap's existence.

## Section 5 — Memory & Secret Lifetime

Cross-referencing Part 1's Section 3G analysis against every category of secret the spec asks about:

| Secret | Zeroed after use? | Mechanism | Gap |
|---|---|---|---|
| Argon2id-derived AES key (notes, token) | **Yes** | `SecureBytes.zero()` called in every `finally` block across `crypto_isolate.dart`'s four static methods — confirmed present in all of `deriveKeyAsBase64`, `deriveKeyAndCompare`, `deriveAndEncrypt`, `deriveAndDecrypt` | None found in the zeroing logic itself |
| Argon2id-derived AES key (device-key wrap) | **Yes** | Same mechanism, `wrapDeviceKeyWithParams`/`unwrapDeviceKey` in `crypto_engine.dart` also route through `CryptoIsolate` | None found |
| Raw password string (`String password` parameters) | **No — cannot be, by Dart's own design.** | Dart `String`s are immutable; there is no API to overwrite a `String`'s backing memory in place. | This is a genuine, unavoidable-in-pure-Dart gap, not a code defect — see recommendation below |
| Raw mnemonic words (`List<String>`) | **No**, same reason | N/A | Same as above |
| `combinedSecret = '$password|...'` string concatenation | **No** | String concatenation in Dart creates a new immutable `String` object; the original inputs *and* this new concatenated copy both persist in memory until GC | This specifically **multiplies** the exposure window — concatenating creates an additional copy of sensitive material that didn't exist before, extending (not just failing to shrink) the memory footprint of the secret |
| Plaintext note content, mid-encryption/decryption | **No, for the `String`-typed intermediate forms** (`cleanBody`, the return value of `decryptProcess`) | Dart's `Uint8List`-typed intermediates (`plainBytes`/`clear` inside `crypto_isolate.dart`) are *not* explicitly zeroed either — only the *derived key* (`keyBytes`) is zeroed in those functions' `finally` blocks; the plaintext/ciphertext byte arrays themselves are left for ordinary GC | This is a real, precise gap: **the KDF output is protected, but the actual note plaintext passing through the same functions is not** |
| RAM-locking of the above | Partial, best-effort | `mlock()` via `ram_lock.dart`, confirmed failing on at least one real tested device this session (`Invalid argument(s): Failed to lookup symbol 'mlock'`) | Already covered as Finding C-4 in the prior report; restated here as directly relevant to this section |
| GC timing / swap exposure | Unmitigated beyond the above | Standard Dart/Android VM behavior | This is a platform-level limitation shared by any Dart/Flutter app handling secrets in `String` form, not unique to Rocen's specific implementation choices |

**Overall Section 5 severity: YELLOW.** The *derived key* handling is genuinely careful and correct (this is the harder, more valuable thing to get right, and it's done well). The *plaintext note content* and *password/mnemonic string* handling has real, unaddressed gaps, but these gaps are partly inherent to using Dart's `String` type for secrets at all — the actionable recommendation is to route password/mnemonic input through `Uint8List`-based buffers (readable directly from a `TextEditingController` via UTF-8 encoding immediately, avoiding ever holding the value as a long-lived `String`) as far up the call stack as is practically achievable, and to explicitly zero the plaintext `Uint8List` note content in `crypto_isolate.dart`'s `finally` blocks the same way `keyBytes` already is.

## Section 6 — GitHub Token: Full Lifecycle Trace

| Stage | What happens | File/function |
|---|---|---|
| **Generated** | Not generated by Rocen — created by the user on GitHub's own site and pasted into Rocen's setup UI. | `settings.dart`, the GitHub setup form (not the focus of this pass, referenced from earlier session context) |
| **First touches memory** | As a `String` from a `TextEditingController`, immediately concatenated with the repo path into `payload` | `settings.dart` `_storeGithubCredentials`-adjacent flow, ~line 3305-3311 |
| **First encrypted** | `CryptoEngine.encryptProcess(payload, pinHash)` — AES-256-GCM, subject to Part 1 Finding 3A (uses the password-verifier value as KDF input) | Same |
| **Hardware-wrapped (conditional)** | `hardwareWrap(...)` via `MainActivity.kt`'s `hwEncrypt` channel, using the `githubTokenKeyAlias`-specific Keystore/StrongBox key | `crypto_engine.dart` |
| **Stored** | `github_access_encrypted` key, `rocen_settings_box`, unencrypted at the Hive layer (Finding H-1) | — |
| **Read back for use** | Decrypted via the mirror path (`hardwareUnwrap` then `decryptProcess`) whenever `GithubBackupService` needs to be constructed | `settings.dart` `_buildGithubServiceFromStoredCredentials` |
| **Held in memory during use** | Lives as a `String` field on `GithubBackupService` instances for the duration of whatever sync operation is running — not zeroed after use (same Dart-`String`-immutability limitation as Section 5) | `github_backup_service.dart` constructor |
| **Transmitted** | `Authorization: Bearer <token>` header, on every request, over TLS+SPKI-pinned connection to `api.github.com` only (confirmed, Part 2 Attacker E) | `github_backup_service.dart` `_headers` |
| **Ever logged?** | **Not found in any reviewed `debugPrint`/`secureDebugLog` call.** Specifically checked every log call site in `github_backup_service.dart` and `settings.dart` for token interpolation — none found. | — |
| **Ever included in a GitHub-bound payload (i.e., could the app accidentally back up its own token)?** | **No.** Checked every `upsertFiles`/`amendSync` content-construction site — none include `token`, `github_access_encrypted`, or any derived form of it. | — |
| **Revocation handling** | If the user revokes the token on GitHub's side, the next API call returns 401/403; `_repositoryMetadataValidated`'s staleness (Part 2, Finding A-1 from the prior report) may produce a slightly misleading diagnostic message, but the app does correctly surface *a* failure rather than silently proceeding — confirmed via the unconditional-throw pattern in `_PinnedGithubClient.send()`. | — |
| **Rotation** | No explicit "rotate token" flow distinct from "delete and re-enter a new one via the setup form" was found — functionally adequate, just not a dedicated first-class feature. | — |

**Overall Section 6 severity: matches Finding H-1/3A** — no *new* issue distinct from what's already documented, but this trace confirms there is no additional leak point across the token's full lifecycle beyond the storage-layer and derivation-layer issues already identified.

## Section 7 — Network Security Table

(Expands on Part 2's Attacker-E analysis into the specific table format the spec requests.)

| Property | Status | Confidence |
|---|---|---|
| TLS enforced | Yes, exclusively — `_validateUri` rejects any non-`https` scheme unconditionally | Confirmed (Dart layer) |
| Only `api.github.com` reachable via this client | Yes | Confirmed |
| Only port 443 | Yes | Confirmed |
| Certificate pinning present | Yes, SPKI-based | Confirmed (Dart layer) |
| Pin validated for correct format before use | Yes — length/Base64/emptiness/duplicate checks all present in `_validateSpkiPin`/`_validatePinConfiguration` | Confirmed |
| Backup pin provisioned | **No** — defaults empty | Confirmed |
| Fail-open on pin mismatch | **No — fails closed**, confirmed via unconditional `throw` | Confirmed |
| Redirect target re-validated | **Not confirmed** | Requires native plugin source |
| Native TLS chain validation itself correct | **Not confirmed** | Requires native plugin source |
| Cleartext traffic permitted anywhere else in the app | No separate unpinned HTTP client found anywhere in the reviewed Dart files | Confirmed for reviewed files only |
| `network_security_config.xml` present | **No** — not found in `AndroidManifest.xml` or referenced anywhere | Confirmed absent |
| Header injection possible from Rocen's own code | No — `_headers` is a fixed getter, never user-influenced | Confirmed |
| Token ever sent to non-GitHub host | No path found | Confirmed |

**New item worth adding precisely, from re-reading `AndroidManifest.xml` again for this section specifically:** the absence of a `network_security_config.xml` is not itself dangerous **given** the app-layer SPKI pinning is doing the real work — a `network_security_config.xml` would mainly matter for defense-in-depth against cleartext traffic from *other* parts of the Android app lifecycle (e.g., WebViews, which Rocen does not appear to use anywhere in the reviewed code) or for pinning enforcement at the OS/framework layer as a backstop if the app-layer pinning code had a bug. Given the app-layer pinning is the primary and, per this review, apparently sole enforcement mechanism, adding a matching `network_security_config.xml` with its own pin-set would be a reasonable **defense-in-depth** addition (protecting against a hypothetical bug in `cert_pinning.dart` itself) rather than a currently-missing primary control.


## Section 8 — Remote Backup Metadata Analysis

Directly building on Part 2's Attacker-D and Section-6 (P-1 from the prior report):

**Exact plaintext fields in `password_state.json`**, per `_buildStateJson` (`password_state_manager.dart`):
- `passwordGeneration` (int)
- `passwordChangeId` (string, per `generateChangeId` — traced: built from `Random.secure()` bytes, hex-encoded, **not** a value with any inherent meaning beyond uniqueness, so its exposure carries no information beyond "a change happened with this opaque ID")
- `passwordChangedAt` (ISO8601 timestamp — full precision, to the second)
- `changedByDeviceId` (the acting device's stable ID)
- `devices`: array of `{deviceNumber, deviceId, passwordGeneration}` for **every device that has ever participated**

**What this reveals to anyone with repository read access, stated precisely (restating and sharpening P-1):**
- Exact device count (`devices.length`), permanently — even a device that's since been lost, wiped, or had the app uninstalled remains in this array forever, since no code path was found that ever removes an entry from `devices` (only adds/updates existing entries by `deviceId` match, per `publishNewState`'s device-list construction logic).
- Exact password-rotation cadence, to the second, for the account's entire history (assuming the user doesn't rewrite Git history, which the app has no mechanism to do or encourage).
- Which specific device most recently changed the password (`changedByDeviceId`), letting an observer infer device usage patterns over time (e.g., "the phone changes it, never the tablet" → the tablet might be a secondary/rarely-used device, itself a mildly useful reconnaissance signal for a targeted social-engineering attempt against the user).

**Recommendation, more specific than the prior pass:** since `deviceNumber` alone (a small sequential integer) is sufficient for every piece of the app's own conflict-detection/fast-forward logic (confirmed: `_nextDeviceNumber`, `_legacyAwareDevices`, and the comparison logic in `checkState` all key off `deviceNumber`, not `deviceId`, for the actual coordination semantics), the **stable, permanent `deviceId` does not need to appear in the plaintext file at all** — it could be kept in a separate, purely-local mapping (`deviceNumber → deviceId`) on each device, with only `deviceNumber` published remotely. This would preserve 100% of the existing coordination functionality while removing the cross-device-correlatable identifier from the shared, semi-public file entirely.


## Section 9 — Sync, Conflict, Replay & Rollback (full mechanics)

Building on Part 2's Attacker-D rollback finding with the deeper mechanical trace this section requires:

### New finding: `publishNewState` never checks `newGeneration > remoteGeneration`

**File:** `password_state_manager.dart`, `publishNewState` (lines 546-632).

Traced precisely: the function validates that the *existing* remote state is well-formed (lines 581-589), and validates the *write* is a fast-forward from the expected parent SHA (delegated to `updateFileWithFastForwardCheck`) — but **at no point does it compare `newGeneration` against `remoteGeneration` to confirm the new value is actually larger.** The one call site checked in `settings.dart` (line 2680-2688, `remoteChangedUnderUs`) checks for *any change* (`!=`), which happens to catch the common case, but this is equality-based drift detection, not monotonicity enforcement, and the two are not the same guarantee.

**Concrete scenario where this specific gap (not the "attacker with a leaked token" framing, but a *legitimate*-code-path gap) could matter:** if a future code change, a race condition, or a bug elsewhere ever computes `newGeneration` incorrectly (e.g., an off-by-one, or a stale `currentGeneration` read from a code path that doesn't go through the same `remoteChangedUnderUs` pre-check that `settings.dart`'s own call site adds), `publishNewState` itself provides **no independent backstop** — it will happily publish a same-or-lower generation number as if it were an advance, because nothing in the function's own logic checks this.

**Severity: ORANGE.** This is a missing defense-in-depth check in a security-relevant function, independent of whether any current call site's own pre-checks happen to prevent the bad case today — a security-critical function like this one should not rely entirely on every future caller remembering to check monotonicity themselves.

**Recommendation:** add `if (newGeneration <= remoteGeneration) { throw ArgumentError('newGeneration must exceed the current remote generation'); }` directly inside `publishNewState`, right after `remoteGeneration` is parsed (line 573), so the function is self-defending regardless of caller discipline.

### Replay of old ciphertext (restating Part 2's Attacker-D finding with the specific mechanical fix)

As established: AES-GCM's tag proves integrity+authenticity of a specific plaintext↔ciphertext↔key triple, not recency. **Recommended concrete fix, more specific than Part 2's framing:** bind a monotonic counter or the note's own `lastSyncedTimestamp` into the AAD (see Part 1, Finding 3D — this is the same missing-AAD mechanism, applied here for a different purpose: anti-replay rather than metadata-tamper-evidence). If the AAD includes, e.g., `'$noteId:$remoteFileId:$expectedGeneration'`, then re-submitting an old ciphertext blob under a *new* generation context would fail authentication, because the AAD used at decrypt-time (reflecting the current expected generation) would no longer match what was used at encrypt-time for that stale blob.

### Conflict resolution — what happens when two devices modify the same note

I looked specifically for note-level (not password-state-level) conflict handling — i.e., if Device A and Device B both edit the same `encrypted_note` while offline and both later sync. Based on `pendingReviewAfterSync`'s presence in `CaptureItem` and the `PullResult`/`pendingRemoteNotes` mechanism referenced in `quicknote.dart`'s pull-and-reconcile flow (from earlier session context), Rocen appears to use a **"flag for manual review" strategy** rather than automatic merge or last-write-wins — this is a reasonable, safety-conscious design choice (automatic merging of encrypted content is not generally possible without decrypting both versions first, which the app would need the password for anyway at sync time). I did not have the complete pull-and-reconcile function in front of me in this pass to verify every edge case exhaustively, so this is filed as **"largely confirmed, one level less thorough than the crypto sections"** — the general strategy is sound and matches good practice for this class of problem, but a full line-by-line trace of every branch was not performed in this specific pass.


## Section 10 — Input Validation Against Malicious/Corrupted Repository Data

(Expands Part 2's Attacker-F table with the specific validation-completeness check the spec requests.)

Already covered thoroughly in Part 2: duplicate-ID rejection, missing-field rejection, and type-checking are all confirmed present and correct in `_decodeDevices`/`PasswordStateDevice.fromJson`. Restating the one confirmed gap precisely for this section's framing: **no upper bound on payload size before `jsonDecode`** — this is the single validation category missing from an otherwise well-defended parsing layer.

**One additional check performed for this section specifically:** whether a malicious `password_state.json` could set `passwordGeneration` to an absurd value (e.g., `-1`, `0`, or `9223372036854775807`, the max 64-bit int) to disrupt the comparison logic in `checkState`. Traced: `publishNewState`'s own read-back validation (line 582, `remoteGeneration < 1`) would reject a stored value of `0` or negative **the next time a legitimate device tries to publish against it**, throwing `FormatException` — but this check only runs at *publish* time, not at *read* time via `checkState`'s comparison logic, which I did not have fully in front of me to verify handles an extreme-but-technically-valid positive integer (e.g., `9223372036854775807`) gracefully rather than via integer overflow in a subsequent `+1` computation somewhere. **Filed as: "Not confirmed — requires re-reading `checkState`'s full comparison logic against extreme integer inputs specifically," a narrower, more specific gap than a blanket "not checked."**


## Section 11 — Logging, Debug Output, Clipboard & Screenshot Exposure

Builds on Part 2 Attacker A and the prior report's Finding P-3, made more exhaustive per this section's specific requirements.

- **`secureDebugLog` vs `debugPrint`:** two distinct logging functions are used across the codebase (`debugPrint` directly in some files, `secureDebugLog` — imported from the still-unreviewed `debug_log.dart` — in `settings.dart` and `password_state_manager.dart`). **This inconsistency is itself worth noting**: if `secureDebugLog` exists specifically to add redaction/safety on top of `debugPrint`, then the files still using raw `debugPrint` for sensitive-adjacent messages (e.g., `github_backup_service.dart`'s `debugPrint('GITHUB ACCESS OK: fullName=$fullName ...')`) are **not** benefiting from whatever protection `secureDebugLog` provides, if any. This remains explicitly unconfirmed pending `debug_log.dart`'s source, but the *inconsistency itself* (some files use one, some the other) is a confirmed, visible fact from the imports alone, independent of what either function actually does internally.
- **Clipboard exposure:** covered in Part 2, Attacker A — no code path found that puts secrets (password, token, mnemonic) onto the system clipboard. The only clipboard-writing feature in the app is Clipboard's own image/video COPY function, which is unrelated to any secret.
- **Screenshot/recording exposure:** the `FLAG_SECURE` scoping gap is the headline finding here, already detailed precisely in Part 2, Attacker A — not re-derived again in full here to avoid duplication, but formally counted as part of this section's coverage per the spec's structure.
- **Crash reporting / analytics:** no crash-reporting or analytics SDK (Firebase Crashlytics, Sentry, etc.) was found in `pubspec.yaml` — meaning there is no *additional* third-party data-exfiltration surface from that category, which is a genuine, if passive, privacy positive worth noting since its absence is itself informative.

## Section 12 — Android Security Checklist

| Item | Status | Evidence |
|---|---|---|
| `android:allowBackup` | Not set → defaults `true` | `AndroidManifest.xml` (already Finding H-6 from the prior report) |
| `android:debuggable` | Not explicitly set in the manifest; AGP automatically sets this `true` for debug builds and `false` for release builds regardless of manifest content, so its absence here is normal, not a gap | `AndroidManifest.xml`, `build.gradle.kts` |
| `android:networkSecurityConfig` | Not present | `AndroidManifest.xml` (Section 7, above) |
| Exported components reviewed | Yes — `MainActivity` (expected/required), `super_native_extensions.DataProvider` (unconfirmed exposure risk, Part 2) | `AndroidManifest.xml` |
| `minSdkVersion` | 23 (set via `local.properties`'s `flutter.minSdkVersion=23`, this session's own earlier fix for `super_clipboard`) | `local.properties` |
| `targetSdkVersion` | Inherited from `flutter.targetSdkVersion`, not independently overridden — value itself not directly visible without Flutter's own resolved default, same caveat as the minSdk investigation earlier this session | `build.gradle.kts` |
| Release signing | **Debug keystore** (Finding H-4, RED — restated here as it belongs in this checklist too) | `build.gradle.kts` |
| ProGuard/R8 rules | Default-only; `proguard-rules.pro` referenced but absent (Finding H-5) | `build.gradle.kts`, `configuration.txt`, `seeds.txt`, `usage.txt` |
| StrongBox/TEE usage | Correctly attempted, with graceful fallback (`getOrCreateHwKey`) | `MainActivity.kt` |
| Root detection | Present (`isDeviceRooted`), drives `kdf_hardened` — correctly understood as a heuristic, not a hard boundary (Part 2, Attacker C) | `crypto_engine.dart` |
| Biometric authentication | **Not found anywhere in the reviewed code.** No `local_auth` or equivalent package in `pubspec.yaml`, no biometric-prompt code found. | `pubspec.yaml` |
| `FLAG_SECURE` | Present but narrowly scoped (Part 2, Attacker A) | `MainActivity.kt`, `settings.dart` |
| Content-provider path permissions | Not scoped beyond the blanket `exported="true"`/`grantUriPermissions="true"` (unconfirmed severity, Part 2) | `AndroidManifest.xml` |

## Section 13 — Dependency & Supply-Chain Audit

| Package | Version pinned | Maintenance signal | Security relevance |
|---|---|---|---|
| `cryptography` | `^2.7.0` | Actively used, standard choice for Dart AEAD/KDF primitives; no known-issue search was performed against a live CVE database in this pass (no internet-connected vulnerability-database tool was used — this would need a dedicated `dart pub outdated`/`osv-scanner`-style check, not performed here) | Core crypto primitive — any future advisory against this package would be maximally relevant given how central it is |
| `hive` / `hive_flutter` | `^2.2.3` / `^1.1.0` | **Confirmed low/stale**, per direct pub.dev evidence gathered this pass: `hive_flutter`'s latest published version is `1.1.0`, published roughly 5 years prior to this review; community forks (`hive_ce`, `hive_plus_secure`) exist specifically because the original package's maintenance has lapsed. `hive_plus_secure` specifically advertises built-in AES-256 encryption — directly relevant to remediating Finding H-1. | Confirmed via live search this pass, not assumed |
| `smart_dev_pinning_plugin` | `^5.0.0` | Native source not available for this review; cannot independently assess its maintenance or correctness beyond the Dart-side contract already audited in Part 2 | Directly load-bearing for the entire network security posture — its unavailability for review is one of this audit's most significant standing gaps |
| `video_player`, `image`, `super_clipboard`, `saver_gallery`, `path_provider` | Recent versions, added this session | Verified current-stable at time of addition (checked directly against pub.dev during this session's earlier feature work) | Low security relevance individually — none handle secrets; `super_clipboard`'s native `super_native_extensions` component is the one with a genuine, already-flagged exposure question (Part 2, Attacker A) |
| `ffi` | `^2.1.3` | Used directly by `ram_lock.dart` for the raw `mlock`/`munlock` FFI calls | Low risk in isolation — the risk lives in *how* it's used (already covered, Finding C-4), not in the package itself |

**Overall Section 13 severity: the `hive`/`hive_flutter` staleness is the standout, concrete finding, now backed by direct evidence rather than a general "consider updating" note** — it should be read as a contributing factor to Finding H-1 (unencrypted boxes): a maintained fork with built-in encryption already exists as a drop-in-adjacent remediation path, which meaningfully lowers the cost of fixing that finding.

## Section 14/15/16/17/18 — Release, Downgrade/Migration, Fail-Closed Review, Doc-vs-Code Mismatches, and Recommended Enhancements

These five sections are being deferred to **Part 4**, to keep this part focused specifically on the storage/memory/network/sync/logging/Android/dependency material as agreed, and because Section 17 (doc-vs-code mismatches) and Section 18 (recommendations) are more naturally written last, after every other section's findings are already on the record to draw from — writing them now would risk an incomplete list that has to be revised once Part 4's own new findings surface.

## Part 3 Summary Table

| ID | Finding | Severity |
|---|---|---|
| New | `last_active_crypto_pin_snapshot` — second copy of the critical verifier, purpose not fully confirmed | Informational / needs more evidence |
| New | Plaintext note/ciphertext byte buffers are not explicitly zeroed in `crypto_isolate.dart` (only the derived key is) | YELLOW |
| New | `publishNewState` has no internal monotonicity check on `newGeneration` | ORANGE |
| Restated | Missing AAD (Part 1) is also the fix for anti-replay, not just metadata-tamper-evidence | ORANGE (same root cause as 3D) |
| New | No payload-size limit before `jsonDecode` anywhere remote content is parsed | ORANGE |
| New | `hive`/`hive_flutter` confirmed stale via live pub.dev evidence; maintained encrypted fork exists | Contributing factor to H-1, now evidenced |
| New | Inconsistent use of `secureDebugLog` vs raw `debugPrint` across files | BLUE (pending `debug_log.dart` review) |
| New | No biometric authentication option anywhere in the app | BLUE — hardening opportunity, not a flaw |
| Restated | `network_security_config.xml` absent — defense-in-depth gap, not primary-control gap given app-layer pinning already exists | BLUE |

This concludes Part 3. Part 4 will cover Sections 14–18 (release/supply-chain detail, downgrade/migration testing, fail-closed error-handling review) and Sections 19–27 (doc-vs-code mismatches, recommended enhancements, and the final consolidated, prioritized action list across all four parts).
