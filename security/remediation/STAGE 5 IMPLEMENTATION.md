# Rocen — Stage 5 Implementation Summary

> **Scope:** Stage 5 session security, key ownership, authorization, lifecycle, provider/UI isolation, and stale-async protection. Stage 6 migration/encryption cutover is intentionally out of scope.

## 1. Stage 5 objective

Stage 5 creates a hard session-security boundary around the existing Stage 1–4 cryptographic architecture.

### Target state machine

```text
BOOTSTRAP
    ↓
LOCKED
    ↓
UNLOCKING
    ↓
ACTIVATING
    ↓
UNLOCKED
```

### Required security behavior

```text
LOCKED
  → no protected authorization
  → no protected ProviderContainer
  → no protected UI/navigation
  → no live authoritative session-key material

ACTIVATING
  → temporary transaction resources may exist
  → normal protected authorization remains denied

UNLOCKED
  → protected session exists
  → authorization is bound to the current epoch

LOCK
  → authorization invalidated
  → epoch invalidated
  → MK/NEK/TEK destroyed synchronously
  → protected providers disposed
  → protected UI removed
  → stale async results rejected
```

## 2. Cryptographic architecture retained

Stage 5 does **not** redesign the established cryptographic protocols.

```text
Cryptography password
    ↓
Password verifier
    ↓
Password-KEK
    ↓
passwordWrap
    ↓
authoritative MK
    ↓
Stage 4 HKDF
    ├── NEK
    └── TEK
```

Recovery remains:

```text
Recovery credential
    ↓
Recovery-KEK
    ↓
recoveryWrap
    ↓
same MK
```

The interactive Stage 5 unlock credential is the existing cryptography password.

```text
Password ≠ MK
Password ≠ NEK
Password ≠ TEK
```

---

## 3. Historical Stage 3 blocker

The old Stage 5 document contained a blocker claiming production MK establishment/recovery was incomplete.

The current source audit found that blocker is stale.

### Current production integration already present

`settings.dart` calls:

- `establishFirstDevice(...)`
- `recoverFromRemote(...)`
- `associateRemote(...)`
- `changePassword(...)`

The current Stage 3 production path already provides:

- random MK generation;
- Password-KEK and Recovery-KEK wrappers;
- same-MK validation;
- local revision checks;
- remote conflict detection;
- crash/reconciliation handling;
- Recovery-KEK wrapper refresh on password change;
- clean-cutover behavior.

No `authSalt` compatibility path is used by the current production crypto flow.

The old `system_crypto_pin`/legacy `CryptoEngine` encryption path is gone; obsolete artifacts are handled by clean-cutover deletion rather than migration.

**Conclusion:** Stage 5 proceeds on top of the current Stage 3 implementation instead of redesigning Stage 3 from scratch.

---

# 4. Files added

## Production files

| File | Purpose |
|---|---|
| `lib/core/session_key_material.dart` | Sole live session owner of MK/NEK/TEK. Secure installation, derivation, and synchronous destruction. |
| `lib/core/session_security_manager.dart` | Central Stage 5 state machine, epochs, authorization, activation, rollback, locking, and cleanup registry. |
| `lib/core/session_unlock_service.dart` | Password-based cold-start/session unlock support. Later hardened so raw MK access is not exposed to arbitrary callers. |
| `lib/features/lock_screen.dart` | Locked-state password UI and explicit re-unlock flow. |

## New tests

```text
test/lock_screen_test.dart
test/session_key_material_test.dart
test/session_security_manager_test.dart
test/session_unlock_service_test.dart
test/session_authorization_gate_test.dart
test/settings_sensitive_cleanup_test.dart
test/key_ownership_audit_test.dart
```

---

# 5. Production files changed

```text
lib/main.dart
lib/navbar.dart
lib/settings.dart
lib/core/master_key_manager.dart
lib/core/master_key_production_service.dart
lib/core/domain_key_derivation.dart
```

### `main.dart`

Adds the session gate and protected application root.

Responsibilities:

- route startup through `BOOTSTRAP`;
- show locked UI when authority already exists;
- construct the protected application only for an active session;
- create a session-owned `ProviderContainer`;
- remove the protected root on lock;
- lock on app lifecycle loss;
- do not automatically unlock on resume.

### `navbar.dart`

Navigation was changed from retaining widget instances to storing only navigation data.

Old pattern:

```text
CaptureModule → constructed widget instance
```

New pattern:

```text
CaptureModule → data only
Protected root → constructs the selected screen
```

This prevents protected widget instances from surviving outside the protected tree.

### `settings.dart`

Sensitive credential dialogs are connected to the Stage 5 cleanup registry.

Tracked sensitive inputs include:

- password/PIN;
- mnemonic fields;
- GitHub token.

Non-sensitive repository-path data is not treated as key material.

The file also retains its existing first-device/recovery/password-change production flows.

### `master_key_manager.dart`

The most important ownership refactor.

`MasterKeyManager` no longer persistently stores the live MK.

Its role is now:

```text
authority/control state
+ operation serialization
+ lease validation
```

instead of:

```text
authority state
+ persistent live MK buffer
```

The old byte-access APIs were removed/reworked, including:

```text
requireAuthoritativeMasterKeyBytes()
requireProvisionalMasterKeyBytes()
```

The new model uses operation-scoped transitions such as:

```text
generateProvisionalMasterKeyBytes()
markAuthoritative()
markNoAuthority()
acknowledgeRecoveredAuthority(...)
```

### `master_key_production_service.dart`

Stage 3 operations were adapted to the new transaction-local key ownership model.

The cryptographic semantics and local/remote consistency rules are preserved while key custody moves away from a persistent `MasterKeyManager` buffer.

### `domain_key_derivation.dart`

HKDF derivation now receives MK bytes explicitly instead of obtaining them from `MasterKeyManager`.

The Stage 4 cryptographic meaning remains unchanged:

- same HKDF construction;
- same labels;
- same lengths;
- same output semantics.

---

# 6. `SessionKeyMaterial` — single live session-key owner

### Ownership

```text
UNLOCKED
    ↓
SessionKeyMaterial
    ├── MK
    ├── NEK
    └── TEK
```

`SessionKeyMaterial` uses the existing secure-memory abstraction and is the only persistent authoritative owner while the session is active.

### Installation

```text
transaction-local MK
    ↓
authorization/epoch validation
    ↓
SessionKeyMaterial.install()
    ↓
copy into secure storage
    ↓
derive NEK/TEK
    ↓
zero transaction-local candidate
```

### Destruction

```text
lock
    ↓
SessionKeyMaterial.destroy()
    ↓
zero MK
zero NEK
zero TEK
```

The implementation added generation checks so destruction during async derivation prevents stale material from becoming active.

---

# 7. `SessionSecurityManager` — session authority

`SessionSecurityManager` owns the security boundary.

## State

```text
BOOTSTRAP
LOCKED
UNLOCKING
ACTIVATING
UNLOCKED
```

## Epoch authorization

Two opaque capabilities are used:

```text
SessionAuthorizationToken
ActivationCapability
```

They are:

- constructed only inside the session-security library;
- bound to the current epoch;
- invalid after lock;
- invalid for a newer session.

Therefore an old callback cannot reuse an old authorization token after relocking.

---

# 8. Transactional unlock

Unlock is not just:

```text
password → unlocked = true
```

It is:

```text
password authentication
    ↓
MK unwrap
    ↓
transaction-local candidate
    ↓
epoch/authorization validation
    ↓
SessionKeyMaterial installation
    ↓
NEK/TEK derivation
    ↓
ACTIVATING
    ↓
protected root activation
    ↓
COMMIT
    ↓
UNLOCKED
```

A failure before commit rolls back the transaction.

### Rollback property

```text
stale/failing candidate
    ↓
zero
    ↓
never authorize
    ↓
never persist as replacement
    ↓
never enter another session
```

---

# 9. Lock behavior

`lockSync()` is deliberately synchronous.

It invalidates the current authorization and destroys session resources without depending on:

- an async teardown;
- a future Flutter frame;
- navigation completion.

The protected root/provider container is disposed as the session ends.

Double-lock behavior is designed to be idempotent.

---

# 10. Lifecycle behavior

Lifecycle loss triggers locking for:

```text
inactive
hidden
paused
detached
```

Resume does **not** automatically unlock.

```text
resume
  ↓
LOCKED
  ↓
user must authenticate again
```

This keeps lifecycle events separate from authorization.

---

# 11. Provider and UI lifetime

The protected application tree is created only for `UNLOCKED`.

```text
Outer application scope
    ↓
SessionGate
    ↓
ProtectedAppRoot
    ↓
session-owned ProviderContainer
    ↓
navbar + feature widgets
```

On lock:

```text
SessionSecurityManager.lockSync()
    ↓
destroy session keys
    ↓
remove protected root
    ↓
dispose ProviderContainer
    ↓
protected feature state is released
```

No protected widget/state instance is intended to remain in global navigation state.

---

# 12. Navigation lifetime

`CaptureModule` is now data-only.

Actual feature screens are constructed inside the protected root.

This specifically prevents patterns such as:

```text
enum value
    → QuickNoteScreen()
```

from keeping protected widget instances alive for the whole process.

---

# 13. Sensitive UI cleanup

`settings.dart` credential dialogs are registered with the session cleanup registry.

The cleanup mechanism exists so that session lock can clear sensitive text even when a dialog is still active or its normal disposal path has not completed.

Sensitive controller categories covered include:

```text
password
PIN
mnemonic
GitHub token
```

The implementation deliberately does not treat repository path text as a credential.

---

# 14. Screen-capture protection

The existing Settings screen had screenshot protection tied to the Settings tab's lifecycle.

Stage 5 extends the protection intent to the protected session root so it is not dependent on which feature tab is open.

The native Android implementation cannot be verified because the supplied source contains no:

```text
android/
AndroidManifest.xml
MainActivity.kt
```

No Android files were invented.

Status:

```text
Dart-side protected-session integration → implemented
native FLAG_SECURE enforcement → unavailable/unverified
```

---

# 15. Fail-closed handling for corrupt local authority

A malformed local authority record is treated differently from "no authority."

The intended behavior is:

```text
corrupt authority
    ↓
explicit failure
    ↓
do not unlock
    ↓
do not silently treat as fresh setup
```

This avoids accidentally turning corrupted persisted state into an unintended setup/reset path.

---

# 16. Lower-layer authorization and async fencing

Stage 5 security is not intended to depend only on UI code.

Sensitive production operations are protected at the service/security boundary.

Relevant operations include:

```text
associateRemote
changePassword
recoverFromRemote
```

The model is:

```text
authorization check at entry
        +
authorization/epoch check before sensitive completion
```

The existing `runExclusiveInitialization` lease still provides operation serialization.

---

# 17. Corrected MK lifecycle

The final ownership model is:

| Stage | MK location | Owner | Authoritative? |
|---|---|---|---|
| Cold start | nowhere in RAM | none | no |
| Password unwrap | local transaction buffer | current unlock operation | no |
| Pre-install validation | transaction-local candidate | current operation | no |
| Installation | `SessionKeyMaterial` | session | yes |
| UNLOCKED | `SessionKeyMaterial` only | session | yes |
| LOCKED | nowhere in authoritative live state | none | no |
| Second unlock | new transaction-local candidate | new operation | no → yes after install |

NEK and TEK follow the same session ownership boundary.

`MasterKeyManager` contains control state only; it does not retain a persistent authoritative MK buffer.

---

# 18. Ownership audit

A repository-wide audit was performed against the final ownership model.

The latest implementation log reports:

- no MK field remains on `MasterKeyManager`;
- the only intended class-level key fields are the three secure fields in `SessionKeyMaterial`;
- no feature file directly accesses low-level session key ownership;
- no static widget retention was found in the new session code;
- navigation and navbar construction occur only inside the protected tree;
- no new logging of passwords/MK/NEK/TEK was introduced;
- an obsolete raw-MK audit getter was removed.

The intended invariant is:

```text
UNLOCKED
    → SessionKeyMaterial owns live authoritative MK/NEK/TEK

LOCKED
    → SessionKeyMaterial destroyed
    → MasterKeyManager has no live MK
    → providers/session state have no authoritative key copy
```

---

# 19. Test changes

## Existing tests modified

```text
test/domain_key_derivation_test.dart
test/master_key_manager_test.dart
test/master_key_production_service_test.dart
test/widget_test.dart
```

`widget_test.dart` was updated because the old expectation was that Quick Notes appeared immediately at startup. Stage 5 intentionally changes startup behavior to a locked/protected flow.

## New security tests

```text
test/lock_screen_test.dart
test/session_key_material_test.dart
test/session_security_manager_test.dart
test/session_unlock_service_test.dart
test/session_authorization_gate_test.dart
test/settings_sensitive_cleanup_test.dart
test/key_ownership_audit_test.dart
```

Reported test coverage includes:

- session key installation/destruction;
- authorization and epoch invalidation;
- lock/unlock races;
- activation rollback;
- session replacement;
- sensitive cleanup;
- ownership/static audits;
- lock screen behavior.

The implementation log reports approximately:

```text
SessionKeyMaterial       11 cases
SessionSecurityManager   24 cases
SessionUnlockService      8 cases
```

---

# 20. Security issues found during implementation

The implementation process did not blindly accept its first design. Important issues were identified and corrected.

### Persistent MK copy

The first Stage 5 implementation left an authoritative MK copy inside `MasterKeyManager`.

That contradicted the intended single-owner invariant.

**Correction:** remove persistent MK custody from `MasterKeyManager`.

### Public raw-MK unlock API

A later audit found that a public password-unlock method could return raw MK bytes to arbitrary callers.

**Correction in progress at the end of the log:** move raw-MK authentication behind the session-security library and have callers provide the password rather than receive key material.

### Lock/rollback teardown race

Hand-tracing found a possible double protected-root teardown.

A per-activation teardown guard was added.

### Authentication exception mismatch

The lock UI expected specific authentication exceptions while the session manager wrapped them.

**Correction:** preserve the original cause for the caller to inspect.

### Screenshot protection scope

Protection tied only to Settings was recognized as insufficient for a session boundary.

**Correction:** also engage it at the protected root/session lifetime.

---

# 21. Explicitly out of scope

Stage 5 does **not** implement:

```text
Stage 6 ciphertext/envelope migration
Envelope v2
AAD/ciphertext migration
legacy compatibility readers
data migration
dual-format support
new cryptographic protocols
```

The current lack of note/token encryption is expected at this stage.

`DatabaseNotifier` remains a stub, so there is no live persisted-note decryption pipeline to move into the Stage 5 session container yet.

---

# 22. Verification status

The implementation log explicitly reports that Flutter/Dart were unavailable.

Therefore:

```text
flutter analyze → NOT RUN
flutter test    → NOT RUN
```

The work was verified by:

- direct source inspection;
- repository-wide searches;
- static/regex ownership checks;
- hand-traced execution paths;
- hand-traced race scenarios;
- manual review of test logic.

These checks are **not equivalent to compiling or executing the suite**.

Native Android screen-capture enforcement is also unverified because Android sources were not supplied.

---

# 23. Final state of the work recorded in the log

## Substantially implemented

- Stage 5 session state machine;
- epoch-bound authorization;
- transactional activation and rollback;
- `SessionKeyMaterial`;
- single-owner MK/NEK/TEK model;
- `MasterKeyManager` ownership refactor;
- explicit-MK Stage 4 derivation API;
- protected ProviderContainer/root lifetime;
- data-only navigation;
- lifecycle locking;
- sensitive settings cleanup;
- protected-session screenshot-protection integration;
- service-layer fencing;
- ownership/static audits;
- Stage 5 tests.

## Not fully closed at the end of the log

The log ends while applying an additional hardening pass to the password unlock API.

That work was changing:

```text
public raw-MK unlock API
        ↓
library-private authentication
        ↓
SessionSecurityManager.unlock(password)
        ↓
raw MK never exposed to the UI/composition root
```

The final compilation state after this last refactor was **not verified**.

---

# 24. Stage 5 runtime summary

```text
APP START
   ↓
BOOTSTRAP
   ↓
local authority exists?
   ├── NO  → first-device setup flow
   └── YES → LOCKED
                ↓
             password
                ↓
             MK unwrap
                ↓
          transaction-local MK
                ↓
          epoch validation
                ↓
            ACTIVATING
                ↓
          SessionKeyMaterial
            owns MK/NEK/TEK
                ↓
       protected ProviderContainer
       + protected navigation/UI
                ↓
              COMMIT
                ↓
            UNLOCKED
                ↓
        lifecycle / user lock
                ↓
             LOCKED
                ↓
       synchronous key destruction
       protected root/provider disposal
       stale-result rejection
                ↓
          explicit re-unlock
```

## Core Stage 5 invariant

```text
UNLOCKED
  → SessionKeyMaterial is the sole authoritative live owner of MK/NEK/TEK.

LOCKED
  → no long-lived authoritative session-key material remains.
```
