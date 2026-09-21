# AUDITOR

I audited the actual Stage 4 audited snapshot rather than treating the frozen architecture as if it were already wired into production. The important result is that Stage 5 needs a stronger and slightly different design than the earlier proposal.

## Revised Stage 5 security boundary

The implementation target should be:

```text
                         RocenApp
                            │
                  AppLifecycleListener
                            │
             ┌──────────────┴──────────────┐
             │                             │
        lifecycle lock               lifecycle resumed
             │                             │
             ▼                             │
 SessionSecurityManager ◄──────────────────┘
             │
   authoritative session state
   authoritative session epoch
             │
      SessionKeyMaterial
      ├── MK
      ├── NEK
      └── TEK
             │
        lockSync()
             │
      epoch ← epoch + 1
             │
      zero all SecureBytes
             │
      clear key references
             │
      run registered cleanup
             │
      dispose session ProviderContainer
             │
             ▼
          LOCKED
             │
      no protected Navigator
      no protected providers
      no sensitive controllers
```

The key architectural correction is this:

**`MasterKeyManager`** **must stop owning the live MK buffer.**

It should retain its existing Master-Key authority/generation state machine, but the actual live bytes move into a single `SessionKeyMaterial` owned by `SessionSecurityManager`.

That gives us one authoritative owner instead of:

```text
MasterKeyManager → MK
SessionManager   → another MK
```

which would violate the requirement you gave.

### Ownership model

`SessionSecurityManager` becomes the only production class containing the live:

```text
SecureBytes? masterKey
SecureBytes? noteEncryptionKey
SecureBytes? githubTokenEncryptionKey
```

`MasterKeyManager` becomes an authority/controller façade:

```text
MasterKeyManager.state
    ↓ delegates
SessionSecurityManager.sessionKeyMaterial.masterKeyState

generateProvisionalMasterKey()
    ↓
SessionSecurityManager.installProvisionalMasterKey()

promoteProvisionalToAuthoritative()
    ↓
SessionSecurityManager.promoteProvisionalMasterKey()

setAuthoritativeMasterKeyFromRecovery()
    ↓
SessionSecurityManager.installRecoveredMasterKey()
```

`MasterKeyManager.requireAuthoritativeMasterKeyBytes()` remains for Stage 4 compatibility, but it returns a defensive transient copy exactly as today. It does **not** retain another copy.

So the invariant becomes:

> There is exactly one authoritative in-memory copy of each session key inside `SessionKeyMaterial`; any returned byte buffer is temporary caller-owned material and must be destroyed after use.

That is materially stronger than simply adding a lock manager beside the existing Stage 4 manager.

---

# 1. Epoch design

Use one monotonically increasing `int sessionEpoch` in `SessionSecurityManager`.

I recommend a small immutable token:

```text
SessionEpochToken
    final int epoch
```

Operations do:

```text
token = session.captureEpoch()
↓
start async work
↓
await
↓
session.requireCurrent(token)
↓
install/use/return result
```

`requireCurrent()` fails when:

```text
token.epoch != currentEpoch
OR
session is locked
```

## Epoch transitions

I would increment on both lock and creation of a new unlocked session:

```text
initial            epoch 0, LOCKED
successful unlock  epoch 1, UNLOCKED
lock               epoch 2, LOCKED
successful unlock  epoch 3, UNLOCKED
lock               epoch 4, LOCKED
```

That prevents an especially subtle reuse race where an old operation from an earlier session finishes after a new session has already been established.

`lockSync()` must not increment repeatedly while already locked. That keeps `doubleLockIsIdempotent` genuinely idempotent.

---

# 2. `lockSync()` must be truly synchronous

The destruction path should be entirely synchronous:

```text
lockSync()
    1. mark state LOCKED
    2. increment epoch
    3. zero SessionKeyMaterial
    4. clear references
    5. invoke registered sensitive-cleanup callbacks
    6. dispose session ProviderContainer
    7. notify listeners
```

There must be **no** **`await`** **anywhere in that sequence**.

The important ordering is that the epoch becomes invalid **before** cleanup work begins.

Dart code cannot normally interleave another Dart callback in the middle of a synchronous method, so there is no need for an asynchronous mutex around this sequence.

Future cancellation remains best-effort. Dart `Future`s generally are not cancellable, so the security primitive is **epoch invalidation**, not pretending every Future can be cancelled.

---

# 3. Master-Key initialization must become epoch-aware

This is one of the most important real-code changes.

The actual Stage 4 `initializeOrRecoverMasterKey()` has this sequence:

```text
fetch remote
↓
generate provisional MK
↓
await conditional publish
↓
promote provisional
```

That is currently vulnerable to the exact lifecycle race you identified: the async publish can complete after a session lock.

Stage 5 should change the body to:

```text
epoch = captureEpoch()
↓
await fetch
↓
requireCurrent(epoch)

generate provisional MK
↓
await conditional publish
↓
requireCurrent(epoch)
↓
promote provisional
```

No promotion is allowed after an epoch transition.

### Defense in depth

`promoteProvisionalToAuthoritative()` itself should also refuse when the session is locked or the supplied operation epoch is stale.

I would make the internal promotion API require the current epoch rather than relying only on callers:

```text
promoteProvisionalToAuthoritative(SessionEpochToken token)
```

That way a future caller cannot accidentally reintroduce the race by forgetting its post-`await` check.

The public Stage 4 API can remain as the authority-level method, while the initialization implementation uses the epoch-bound internal method.

### Lock during initialization

On:

```text
PROVISIONAL
↓
await createDeviceKeyJsonIfAbsent()
↓
LOCK
```

the lock zeroes the provisional MK and changes the epoch.

When the publish completes:

```text
requireCurrent(oldEpoch)
```

fails.

The code must:

```text
not promote
not persist
not sync
not install anything
throw SessionEpochInvalidatedException
```

The stale provisional buffer is already destroyed by the synchronous lock.

This directly satisfies the required regression test.

---

# 4. Unlock/recovery must use the same epoch mechanism

The same primitive should handle:

```text
Password-KEK unwrap
Recovery-KEK unwrap
legacy device-key recovery
future hardware unwrap
```

The generic pattern should be:

```text
epoch = captureEpoch()

result = await resolver()

if stale:
    zero result
    reject

if current:
    install into SessionKeyMaterial
```

Crucially, **the returned MK must not be installed before the epoch check**.

That makes this race safe:

```text
unlock starts
↓
await Argon2 / decrypt / unwrap
↓
lock
↓
epoch changes
↓
unwrap finishes with MK
↓
MK is explicitly zeroed
↓
result rejected
↓
session stays LOCKED
```

That is the exact behavior your required `staleUnlockResultRejected` test should prove.

---

# 5. Stage 4's actual production crypto must also get epoch fencing

This is where the real codebase changes the design significantly.

The archive shows that production note/token handling still uses:

```text
system_crypto_pin
    ↓
CryptoEngine.encryptProcess/decryptProcess
```

rather than the Stage 4 `DomainKeyDerivation`/`PasswordKeyDerivation` path.

So Stage 5 must **not** pretend those flows are already MK-based.

But the legacy crypto APIs are still asynchronous secret-producing operations and therefore need epoch fencing.

## `CryptoEngine.decryptProcess*`

Current:

```text
await CryptoIsolate.deriveAndDecrypt(...)
↓
clear
↓
return String
```

Stage 5:

```text
epoch = captureEpoch()
↓
await CryptoIsolate.deriveAndDecrypt(...)
↓
if stale:
    zero clear
    reject
↓
convert to String
↓
return
```

For compatibility with the existing code, a stale decrypt can be surfaced as the existing `"DECRYPTION FAULT"` result **only if the stale plaintext is destroyed first**. A dedicated exception is cleaner, but the important security property is that plaintext never escapes.

## `CryptoEngine.encryptProcess*`

Capture the epoch before the isolate call and validate before building/returning the ciphertext package.

Also explicitly zero its temporary `Uint8List` input/salt/nonce buffers in `finally` blocks. The immutable `String` input itself cannot be physically zeroed in Dart, so the documentation must not claim that.

## `CryptoEngine.hardwareUnwrap`

This is especially important because the current implementation returns plaintext from the native Keystore channel.

The epoch check must occur immediately after the native `await` and **before** that plaintext becomes an accepted return value.

The native-returned strings themselves cannot be reliably scrubbed from Dart memory, so this remains best-effort memory hygiene, not guaranteed erasure.

## `CryptoEngine.unwrapDeviceKey`

Same rule:

```text
await unwrap
↓
epoch check
↓
if stale:
    zero returned Uint8List
    reject
```

This matters because this is the current production recovery-style path, unlike the unused Stage 3 wrapper path.

---

# 6. `DomainKeyDerivation` also becomes epoch-aware

`DomainKeyDerivation` must:

```text
capture epoch
↓
get authoritative MK
↓
await HKDF
↓
validate epoch
↓
install derived key into SessionKeyMaterial
↓
return transient defensive copy
```

If the epoch changed after HKDF:

```text
destroy SensitiveBytes
destroy derived SecretKeyData
destroy temporary buffers
reject
```

The authoritative NEK/TEK live copy remains in `SessionKeyMaterial`.

For Stage 4 API compatibility, the public methods may still return `SecureBytes`, but that returned object is explicitly a temporary operational copy, not the authoritative session copy.

That distinction needs to be documented clearly.

---

# 7. `PasswordKeyDerivation` gets fencing without protocol changes

Stage 5 should not change:

- the wrap envelope
- Argon2 parameters
- canonical recovery encoding
- password-change semantics

But the async operations must become epoch-aware.

Especially:

```text
unwrapMasterKeyWithPassword()
unwrapMasterKeyWithRecovery()
changePassword()
```

For `changePassword`, every async secret-producing stage needs a current-epoch check before the returned artifacts can be accepted.

A lock during password change must not permit:

```text
old MK unwrap finishes
↓
new wrappers finish
↓
password state is persisted
```

after the session has already been invalidated.

The password-change protocol itself stays exactly the same; only its session validity boundary changes.

---

# 8. The biggest UI correction: `ProviderScope` must become session-scoped

This is the other major finding from the actual codebase.

The current application has its global `ProviderScope` above `RocenApp`. The database provider stores `List<CaptureItem>` in Riverpod state, including plaintext/decrypted note content.

Therefore this would **not** be sufficient:

```text
dispose QuickNoteScreen
show LockScreen
```

because the Riverpod database provider could still hold the sensitive state.

### Correct design

Use a dedicated session `ProviderContainer`:

```text
LOCKED
    session container does not exist

UNLOCK
    create new ProviderContainer
    mount it via UncontrolledProviderScope
    build protected application

LOCK
    dispose ProviderContainer synchronously
    protected widgets/routes/providers disappear
```

This is much stronger than trying to manually zero every provider field.

The session container should own the protected application providers, including the actual database state and navigation state.

The non-sensitive shell state, such as global theme configuration, can remain outside it.

This produces:

```text
SessionSecurityManager
        │
        ├── SessionKeyMaterial
        ├── epoch
        └── session ProviderContainer lifecycle
```

and gives us a real application-session boundary rather than merely a visual one.

---

# 9. Root gate placement

The gate should sit **above the existing root Navigator**.

The clean place is `MaterialApp.builder`:

```text
MaterialApp
    builder:
        SessionGate
            ├── LOCKED → LockScreen
            └── UNLOCKED → existing Navigator
                               │
                               └── session ProviderContainer
```

That matters because dialogs/routes currently live on the MaterialApp navigator.

Putting a lock screen *inside* the existing navigator would leave old routes alive.

By conditionally removing the navigator itself, the following disappear together:

- current feature screen
- dialogs
- routes
- modal sheets
- edit screens
- conflict dialogs
- navigation state

This satisfies the “protected subtree genuinely removed” requirement much more convincingly.

---

# 10. Sensitive controller cleanup needs an explicit registry

The actual codebase has a mix of:

```text
State-owned controllers
```

which already dispose correctly, and:

```text
controllers created locally inside dialog/helper functions
```

which are much easier to leave alive across an abrupt lock.

The latter category includes PIN, mnemonic, token, and other dialog inputs.

So I would add a tiny synchronous cleanup registry to `SessionSecurityManager`:

```text
registerSensitiveCleanup(void Function())
```

On lock:

```text
run every registered cleanup
remove registrations
```

A dialog can register:

```text
controller.clear()
controller.dispose()
timer.cancel()
```

and unregister on normal completion.

This is specifically for things that are otherwise difficult to reach synchronously.

It is **not** a substitute for widget `dispose()`. Stateful widgets should still clean themselves normally.

### Scope

At minimum audit:

- `settings.dart` dialog-created PIN controllers
- mnemonic controller lists
- token/repository controllers
- QuickNote PIN dialog controller
- IdeaInbox editor controllers
- any temporary debounce/timer created outside widget state

The existing QuickNote title/body controllers are already disposed in the widget state, which is good; the Stage 5 change should preserve that behavior.

---

# 11. Lifecycle policy

Use `AppLifecycleListener` at the application root.

Lock on:

```text
inactive
hidden
paused
detached
```

Do nothing on:

```text
resumed
```

Flutter explicitly notes that lifecycle notifications are not guaranteed in abnormal termination cases; some states can be skipped or never delivered. ([Flutter API Docs](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html?utm_source=chatgpt.com "AppLifecycleState enum - dart\:ui library - Dart API"))

So the correct documentation claim is:

> When Rocen receives a lifecycle transition that leaves the active session, it immediately invalidates the current session and destroys reachable session-held key/application state. Flutter cannot guarantee delivery of a lifecycle callback before every abnormal process termination, so this is not equivalent to guaranteed physical memory erasure.

That is honest and technically defensible.

### One additional rule

On `resumed`, **never** call `unlock()` automatically.

The application remains locked until an explicit authentication operation completes successfully.

---

# 12. Current first-run flow needs to be redesigned around the new gate

This is an important integration issue.

The current app does not have a global application-session login screen. Existing password dialogs are per-feature/per-note operations, not an application boundary.

Also, a fresh install may not yet have `system_crypto_pin`.

Therefore a global gate that simply says:

```text
"Enter existing password"
```

would risk locking a brand-new user out of the application before the password setup screen can be reached.

### Correct Stage 5 shell

Use three shell states:

```text
FIRST_RUN_SETUP
        ↓
      LOCKED
        ↓
     UNLOCKED
```

`FIRST_RUN_SETUP` is a tiny non-sensitive shell whose only purpose is establishing the existing application password.

It must **not** instantiate the protected provider container.

After setup succeeds:

```text
FIRST_RUN_SETUP → LOCKED
```

and the next transition into the protected app requires explicit unlock.

For existing installations with `system_crypto_pin`, startup goes directly to `LOCKED`.

This keeps the session gate real without creating a first-run dead end.

---

# 13. What “unlock” means in Stage 5, given the actual Stage 4 code

Because the current production note/token flows are still legacy PIN-based, Stage 5 should explicitly separate:

### Session authentication

Current Stage 5 production bridge:

```text
entered application password
↓
existing CryptoEngine verifier
↓
session becomes UNLOCKED
```

This creates the application session boundary.

### Session cryptographic key loading

Framework already supports:

```text
Password-KEK unwrap → MK
Recovery unwrap → MK
HKDF → NEK/TEK
```

but those keys are **not yet used by the production note/token flows**.

So Stage 5 documentation must state:

> Stage 5 introduces the application-session lifecycle boundary and makes its future MK/NEK/TEK material session-owned and epoch-protected. It does not convert existing legacy note/token encryption to the Stage 4 MK hierarchy.

That is exactly the distinction you asked for.

---

# 14. Screen capture protection

The current screenshot protection is tied to `SettingsScreen` through a `screen_security` MethodChannel. That is not the right security boundary.

Stage 5 should remove that Settings-scoped model and move protection to the Android Activity/window.

Use:

```kotlin
window.setFlags(
    WindowManager.LayoutParams.FLAG_SECURE,
    WindowManager.LayoutParams.FLAG_SECURE
)
```

Android documents `FLAG_SECURE` as preventing the window from appearing in screenshots or being viewed on non-secure displays. ([Android Developers](https://developer.android.com/reference/android/view/WindowManager.LayoutParams?utm_source=chatgpt.com "WindowManager.LayoutParams  |  API reference  |  Android Developers"))

Screenshot detection APIs should not be the primary control.

### Critical implementation gate

The supplied Stage 4 archive does **not** contain:

```text
android/app/src/main/...
AndroidManifest.xml
MainActivity.kt
```

only a partial Gradle tree.

Therefore:

**I would not implement or claim the Android half of Stage 5 until the real Android project tree is present.**

We should not manufacture a `MainActivity.kt` or infer its current contents.

That is an actual unresolved input dependency, not a reason to weaken the security design.

---

# 15. Clipboard

No Stage 5 clipboard subsystem.

The actual current clipboard feature is media-oriented, and there is no Stage 4 sensitive password/token/mnemonic copy path that needs a session clipboard mechanism.

So Stage 5 should:

```text
not clear clipboard globally
not add a clipboard manager
not modify unrelated clipboard behavior
```

Future sensitive text-copy functionality should handle sensitivity locally.

---

# 16. Exact file plan

### New Dart files

```text
lib/core/session_security_manager.dart
```

Owns:

- `SessionKeyMaterial`
- lock state
- session epoch
- synchronous destruction
- cleanup registry
- epoch tokens
- async master-key installation guards

```text
lib/features/session_lock_screen.dart
```

Real locked UI.

```text
lib/features/session_setup_screen.dart
```

First-run password setup bridge so the root gate does not dead-end new installations.

I would also consider:

```text
lib/core/session_lifecycle_policy.dart
```

for a pure, testable mapping of lifecycle states → lock/no-lock. This keeps lifecycle policy independently testable.

### Existing files to modify

```text
lib/core/master_key_manager.dart
```

Remove live MK ownership; delegate to `SessionSecurityManager`; epoch-protect initialization and promotion.

```text
lib/core/domain_key_derivation.dart
```

Add epoch fencing and session-owned derived-key installation.

```text
lib/core/password_key_derivation.dart
```

Add epoch fencing around async MK unwrap/recovery/password-change operations without altering the protocol.

```text
lib/core/crypto_engine.dart
```

Epoch-protect the **actual legacy production crypto paths**:

- encryption
- decryption
- hardware unwrap
- device-key unwrap

No wire-format changes.

```text
lib/main.dart
```

Add:

- root lifecycle listener
- MaterialApp root gate
- session ProviderContainer creation/disposal
- no automatic unlock on resume

```text
lib/features/settings.dart
lib/features/quicknote.dart
lib/features/ideainbox.dart
```

Add/route sensitive controller/timer cleanup where local dialog resources currently escape normal widget disposal.

Remove the Settings-only screenshot protection call path.

### Tests

```text
test/session_security_manager_test.dart
test/session_lifecycle_policy_test.dart
test/session_gate_test.dart
```

plus modifications to:

```text
test/master_key_manager_test.dart
test/domain_key_derivation_test.dart
```

and legacy crypto tests for stale encrypt/decrypt/unwrap behavior.

---

# 17. Mandatory test matrix

Your required tests remain, but I would expand them slightly because of the actual provider architecture:

| TestRequired behavior                            |                                                  |
| ------------------------------------------------ | ------------------------------------------------ |
| `lockZeroesMasterKey`                            | live MK buffer is destroyed                      |
| `lockInvalidatesSessionEpoch`                    | pre-lock epoch rejected                          |
| `lockZeroesDerivedKeys`                          | NEK + TEK destroyed                              |
| `staleDecryptResultRejected`                     | plaintext never escapes after lock               |
| `staleHkdfResultRejected`                        | derived key destroyed/rejected                   |
| `staleUnlockResultRejected`                      | returned MK zeroed, not installed                |
| `lockDuringMasterKeyInitializationCannotPromote` | post-lock init cannot promote                    |
| `lockDuringRecoveryCannotInstallMasterKey`       | stale recovery MK rejected                       |
| `doubleLockIsIdempotent`                         | no duplicate destruction/state churn             |
| `resumeDoesNotUnlock`                            | resumed stays locked                             |
| `inactiveLocks`                                  | yes                                              |
| `hiddenLocks`                                    | yes                                              |
| `pausedLocks`                                    | yes                                              |
| `detachedLocks`                                  | yes                                              |
| `protectedUiRemoved`                             | protected Navigator/subtree disappears           |
| `sensitiveControllersCleaned`                    | registered controller/timer cleanup runs         |
| `sessionProviderContainerDisposed`               | plaintext provider state is destroyed            |
| `staleEncryptResultRejected`                     | stale ciphertext result cannot reach persistence |
| `staleHardwareUnwrapRejected`                    | stale native plaintext cannot reach caller       |
| `newSessionGetsNewEpoch`                         | unlock creates a distinct session generation     |

The `sessionProviderContainerDisposed` test is especially important because the current codebase's provider-held plaintext would otherwise survive a UI lock.

---

# 18. Completion gate

I would freeze Stage 5 only when all of these are true:

```text
[ ] SessionSecurityManager is sole authoritative live key owner
[ ] MasterKeyManager no longer owns a second live MK
[ ] epoch fencing covers initialization/recovery/HKDF/legacy crypto
[ ] lockSync() destroys keys synchronously
[ ] stale unlock cannot resurrect session
[ ] stale initialization cannot promote provisional MK
[ ] protected root Navigator is removed
[ ] protected ProviderContainer is disposed
[ ] sensitive dialog resources have explicit lock cleanup
[ ] inactive/hidden/paused/detached all lock
[ ] resumed never unlocks
[ ] first-run setup cannot bypass the gate
[ ] Settings-only screenshot protection is removed
[ ] real Android Activity gets FLAG_SECURE
[ ] Android manifest/project files are verified from the actual tree
[ ] no clipboard subsystem added
[ ] no Stage 6 envelope/AAD migration
[ ] no Stage 3 recovery/password protocol redesign
[ ] required regression suite passes
[ ] docs state lifecycle/GC limitations honestly
```

## Two things I would **not** let implementation quietly sidestep

**First:** the Android source-tree gap. The real `MainActivity.kt` and manifest must be supplied before the native capture-control portion can be implemented or signed off.

**Second:** the actual production crypto cutover gap. Stage 5 may harden the legacy `CryptoEngine` operations with epoch fencing, but it must not claim that notes/tokens are now encrypted under the Stage 4 MK/NEK/TEK hierarchy. They are not. That remains a later cutover.

This revised design is the one I would use as the Stage 5 implementation baseline.

# AUDIT

The revised Stage 5 design is substantially correct, but it is not yet approved for implementation. Apply the following corrections before writing production code.

## 1. Epoch fencing is NOT sufficient by itself

The most important requirement is:

> When the application session is LOCKED, new production cryptographic operations must be refused before they begin.

The current Stage 4 production path still allows callers to read `system_crypto_pin` and pass it directly into `CryptoEngine.encryptProcess/decryptProcess/...`.

Therefore Stage 5 must enforce:

```text
LOCKED
    ↓
legacy CryptoEngine operation requested
    ↓
REJECT immediately
```

not:

```text
LOCKED
    ↓
operation starts
    ↓
await
    ↓
stale result rejected
```

Every production secret-using crypto entry point must perform a synchronous unlocked/session-validity check before starting its asynchronous work.

At minimum audit:

* encryptProcess
* encryptProcessWithParams
* decryptProcess
* decryptProcessWithParams
* hardwareUnwrap
* unwrapDeviceKey
* future MK/NEK/TEK operations

The check must happen BEFORE:

* reading/using session-sensitive key material
* dispatching work to a crypto isolate
* invoking a native unwrap operation

The post-await epoch check remains mandatory as defense in depth.

## 2. Separate “operation invalidation” from “transaction atomicity”

Do not claim that session epochs make password changes or GitHub writes atomic.

Example:

```text
password change begins
↓
remote request starts
↓
LOCK
↓
remote request may still finish
```

Dart Future cancellation does not roll back an already-started network side effect.

Stage 5 must therefore distinguish:

### Session-security invariant

```text
stale secret results
→ rejected
→ zeroed where possible
→ never installed into active session state
```

from:

### Persistence/remote transaction consistency

```text
local/remote password-state consistency
```

which remains governed by the existing Stage 3 reconciliation/pending mechanisms.

Do not redesign the Stage 3 remote protocol as part of Stage 5.

Before any new persistent local commit that depends on an async secret-producing result, validate the current epoch.

Do not pretend an epoch check can undo a remote write that already occurred.

## 3. `lockSync()` must be failure-resistant

The destruction path must remain synchronous and must not be abortable by cleanup errors.

Required order:

```text
lockSync()
    1. mark session LOCKED
    2. increment epoch
    3. synchronously zero all session SecureBytes
    4. clear authoritative key references
    5. detach/clear cleanup registry
    6. execute each cleanup callback independently
       - catch errors
       - continue to the next callback
    7. dispose session ProviderContainer
    8. notify listeners
```

A cleanup callback throwing an exception must never prevent:

* key destruction
* epoch invalidation
* remaining cleanup callbacks
* ProviderContainer disposal
* locked state completion

Do not log arbitrary cleanup exceptions if they could contain sensitive values.

## 4. Avoid a circular ownership dependency

Do not implement this as:

```text
SessionSecurityManager → MasterKeyManager
MasterKeyManager       → SessionSecurityManager
```

Create an independent low-level ownership object, for example:

```text
lib/core/session_key_material.dart
```

Conceptually:

```text
SessionKeyMaterial
    ├── MK
    ├── NEK
    └── TEK
```

Then:

```text
SessionSecurityManager
        ↓
SessionKeyMaterial

MasterKeyManager
        ↓
SessionKeyMaterial
```

There must still be only one authoritative live copy of each session key.

`MasterKeyManager` may expose authority/state APIs, but it must not maintain a second persistent live MK buffer.

## 5. Explicit ownership-transfer rules

For every function that installs an MK/NEK/TEK into session state, define exactly who owns the supplied buffer.

Preferred rule:

```text
caller obtains Uint8List
    ↓
SessionKeyMaterial copies into SecureBytes
    ↓
caller-owned Uint8List is immediately zeroed
    ↓
only SessionKeyMaterial retains authoritative SecureBytes
```

Never retain a mutable caller-owned `Uint8List` as authoritative session state.

For stale results:

```text
result returned
↓
epoch invalid
↓
zero result before throwing/returning failure
```

## 6. Lock-time cleanup must cover more than widgets

The protected ProviderContainer is necessary because the current database provider holds plaintext `CaptureItem` state.

Do a complete audit of all providers capable of containing sensitive data.

The session container must own the protected application state, including the database state and any other providers that can contain:

* decrypted notes
* tokens
* plaintext editor state
* sensitive remote data

Do not instantiate those providers in the outer/global container before the session is unlocked.

Verify with tests that:

```text
UNLOCK
→ provider container created
→ plaintext provider state exists

LOCK
→ provider container disposed
→ protected provider state no longer exists
```

The fact that the UI disappeared is not sufficient evidence.

## 7. First-run behavior must preserve existing semantics

The proposed:

```text
FIRST_RUN_SETUP
    ↓
LOCKED
    ↓
UNLOCKED
```

architecture is acceptable only after checking the actual existing meaning of the “cryptographic access password.”

Do not silently turn an optional/feature-level password mechanism into a mandatory global authentication policy without documenting that as an intentional product/security decision.

Fresh installation must not become trapped behind a global lock because the required password state does not yet exist.

Existing installations with a configured security password must enter the appropriate locked state.

## 8. The legacy crypto path must be session-gated

Stage 5 does NOT migrate the legacy ciphertext format.

However, because the current production note/token path still uses:

```text
system_crypto_pin
    ↓
CryptoEngine
```

those APIs must still obey the application-session security boundary.

Therefore add:

```text
session.requireUnlocked()
```

or an equivalent epoch/token-based precondition BEFORE the asynchronous legacy crypto operation starts.

Do not merely hide those calls behind a locked UI.

Background operations and future code must receive the same protection even when no sensitive widget is visible.

## 9. DomainKeyDerivation ownership

`DomainKeyDerivation` must no longer create the illusion that every returned `SecureBytes` object is the authoritative session key.

Use:

```text
derive
↓
epoch validate
↓
install authoritative SecureBytes into SessionKeyMaterial
↓
return only a temporary defensive operational copy if required
```

Do not maintain separate authoritative NEK/TEK buffers in both `DomainKeyDerivation` and `SessionKeyMaterial`.

## 10. Current Flutter application structure must be respected

The current root is:

```text
MaterialApp
    ↓
home: AnimatedSplashScreen
    ↓
application UI
```

not a hand-written root Navigator architecture.

A `MaterialApp.builder`-based session gate can still be used, but verify that the implementation actually removes the Navigator/protected subtree rather than placing another widget above it.

Desired result:

```text
LOCKED
    → protected Navigator/application subtree does not exist

UNLOCKED
    → protected Navigator exists inside session ProviderContainer
```

The existing splash screen may remain outside the protected session only if it contains no sensitive state.

## 11. `resumed` never unlocks

Preserve this invariant exactly:

```text
inactive / hidden / paused / detached
    ↓
LOCKED

resumed
    ↓
STILL LOCKED
```

No automatic restoration of MK, NEK, TEK, providers, navigation state, or decrypted content on resume.

## 12. Native Android portion remains blocked until the real files exist

The supplied Stage 4 project archive currently contains only a partial Android tree and does not contain the actual Activity/manifest source required for the `FLAG_SECURE` implementation.

Therefore:

* do not invent `MainActivity.kt`
* do not invent the manifest
* do not claim the native control is complete

The Android portion may be designed, but it is not implementation-complete until the actual project tree is available.

## 13. Mandatory regression tests added to the previous matrix

Add these specifically:

```text
cryptoDeniedWhileLocked
legacyDecryptDeniedWhileLocked
legacyEncryptDeniedWhileLocked
hardwareUnwrapDeniedWhileLocked
deviceKeyUnwrapDeniedWhileLocked

lockDuringAsyncLegacyDecrypt
lockDuringAsyncLegacyEncrypt
lockDuringAsyncHardwareUnwrap

cleanupCallbackFailureDoesNotAbortLock
allCleanupCallbacksRunAfterOneFails

sessionKeyInstallationCopiesAndZeroesCallerBuffer

sessionProviderContainerDisposed

noProtectedProviderInstantiatedBeforeUnlock

lockDuringPasswordChangeDoesNotAcceptStaleSecrets

lockDuringMasterKeyInitializationCannotPromote

lockDuringRecoveryCannotInstallMasterKey
```

Also test this invariant explicitly:

```text
SESSION N
    ↓
start secret-producing operation
    ↓
LOCK → epoch N+1
    ↓
operation completes
    ↓
result is destroyed/rejected
    ↓
NEW SESSION
    ↓
old result still cannot enter the session
```

## 14. Stage 5 completion gate

Do not declare Stage 5 complete until all of the following are demonstrated:

```text
[ ] One authoritative live key owner exists
[ ] No second persistent live MK remains in MasterKeyManager
[ ] Locked state blocks NEW crypto work before it starts
[ ] Post-await epoch checks reject stale results
[ ] Stale unlock cannot resurrect MK
[ ] Stale recovery cannot resurrect MK
[ ] Stale initialization cannot promote provisional MK
[ ] lockSync cannot be aborted by cleanup exceptions
[ ] protected ProviderContainer is actually disposed
[ ] plaintext provider state disappears with the session
[ ] protected Navigator/application subtree is actually removed
[ ] inactive/hidden/paused/detached lock
[ ] resumed never unlocks
[ ] first-run behavior is deliberate and cannot dead-end
[ ] global FLAG_SECURE is implemented in the real Android project
[ ] Settings-only screenshot protection is removed
[ ] no arbitrary clipboard-clearing subsystem is introduced
[ ] no Stage 6 envelope/AAD migration is introduced
[ ] no Stage 3 protocol redesign is introduced
[ ] tests cover both pre-await lock denial and post-await stale-result rejection
[ ] documentation does not claim guaranteed physical memory erasure
```

Do not weaken any of these requirements merely to make the implementation smaller or easier.

If the actual codebase prevents one of these invariants from being implemented cleanly, stop and report the architectural conflict instead of silently choosing a weaker security behavior.

#IMPLEMENTER

This is what AI said: The Stage 5 design is revised again. **No production implementation should start yet.** The corrections below make the design consistent with the actual Stage 4 codebase, including its legacy crypto path, current Riverpod structure, initialization race, and first-run semantics.

## Implementation status

There are now **two explicit blockers to full Stage 5 implementation/sign-off**:

1. The current app has no independent application-session credential. `system_crypto_pin` is currently an optional **cryptography password**, so making it the mandatory app-unlock credential would be a deliberate product/security-policy change, not an invisible implementation detail.
2. The supplied Stage 4 archive still lacks the real Android Activity and manifest, so the `FLAG_SECURE` portion cannot yet be implemented or verified.

Everything else can be designed concretely without weakening the security requirements.

---

# 1. Final ownership architecture

The previous design still left too much ownership responsibility in `MasterKeyManager`. The corrected structure is:

```text
                 SessionKeyMaterial
             ┌────────────────────────┐
             │ authoritative buffers  │
             │                        │
             │ MK   : SecureBytes?    │
             │ NEK  : SecureBytes?    │
             │ TEK  : SecureBytes?    │
             └───────────┬────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
   SessionSecurityManager     MasterKeyManager
              │                     │
       session lifecycle       authority/state façade
       epoch                   initialization rules
       lock/unlock             provisional/promotion
       cleanup                 recovery installation
       provider lifetime
```

The actual Stage 4 manager currently contains its own `_masterKeyBytes` and `_state`, so Stage 5 must remove the persistent MK buffer from that class rather than merely adding another owner beside it.

### `SessionKeyMaterial`

New:

```text
lib/core/session_key_material.dart
```

This is the only authoritative live owner.

It owns:

```text
SecureBytes? masterKey
SecureBytes? noteEncryptionKey
SecureBytes? githubTokenEncryptionKey
```

It must never expose those mutable buffers directly.

Its public operational APIs return defensive copies only.

### `MasterKeyManager`

It remains responsible for:

- provisional vs authoritative rules
- dataset initialization
- race handling
- recovery installation
- existing Stage 4 public state API

But:

```text
MasterKeyManager
    does NOT own a second MK SecureBytes
```

Its `state` should delegate to the state represented by `SessionKeyMaterial`.

### `SessionSecurityManager`

Owns:

- locked/unlocked session state
- session epoch
- lifecycle response
- synchronous destruction
- cleanup registry
- session ProviderContainer lifetime
- unlock transaction state

It does **not** contain another MK.

---

# 2. Four session states internally

Externally the application remains simply:

```text
LOCKED
UNLOCKED
```

Internally Stage 5 needs two transitional states:

```text
BOOTSTRAP
LOCKED
UNLOCKING
UNLOCKED
```

### `BOOTSTRAP`

Only for a fresh installation where the existing cryptography password has not yet been configured.

It must not create the protected ProviderContainer.

### `LOCKED`

No protected UI, no protected provider container, no session keys.

Only tightly controlled authentication/setup primitives may execute.

### `UNLOCKING`

A credential operation is in progress.

The protected application is still absent.

This state exists specifically so an unlock/recovery operation can legally run while the public session remains locked without turning general `CryptoEngine` APIs into locked-state bypasses.

### `UNLOCKED`

Protected application subtree exists.

Session crypto is permitted.

---

# 3. Locked-state crypto policy

This is the major correction.

The rule becomes:

```text
LOCKED
  ├── generic legacy crypto → REJECT BEFORE START
  ├── generic hardware unwrap → REJECT BEFORE START
  ├── generic device-key unwrap → REJECT BEFORE START
  ├── HKDF/session-key operations → REJECT BEFORE START
  └── authentication/unlock primitive → ALLOWED ONLY through
      dedicated narrow unlock path
```

The exception is important.

Otherwise there is no way to perform an authentication operation while locked.

So **generic crypto APIs are locked-gated**, while a small allowlisted authentication path is not.

---

# 4. `CryptoEngine` needs two layers

The actual Stage 4 production API accepts the PIN directly and dispatches asynchronous isolate work.

Stage 5 should separate:

### Public production session APIs

These are always session-gated:

```text
encryptProcess
encryptProcessWithParams
decryptProcess
decryptProcessWithParams
hardwareUnwrap
unwrapDeviceKey
future MK/NEK/TEK operations
```

Each begins with a synchronous:

```text
session.requireUnlocked()
```

**before**:

- reading/using a sensitive session credential supplied by the caller,
- decoding/processing protected material,
- sending work to `CryptoIsolate`,
- invoking native Keystore methods.

Then it captures the epoch and performs the async work.

So:

```text
LOCKED
  ↓
encryptProcess()
  ↓
requireUnlocked()
  ↓
throw immediately

CryptoIsolate NEVER STARTS
```

That is now a mandatory security invariant.

### Private/authentication paths

Unlocking is handled through a separate internal path.

For example conceptually:

```text
SessionSecurityManager.beginUnlock()
    ↓
capture epoch
    ↓
verify password
    ↓
optional hardware-bound verification
    ↓
epoch check
    ↓
install session material
    ↓
UNLOCKED
```

A generic caller cannot invoke the internal privileged path merely because the session is locked.

This resolves the apparent contradiction between:

```text
hardwareUnwrapDeniedWhileLocked
```

and:

```text
lockDuringRecoveryCannotInstallMasterKey
```

A normal `hardwareUnwrap()` call is denied while locked. A dedicated unlock/authentication operation has narrowly scoped authority and remains epoch-protected.

---

# 5. `verifyPin` vs hardware-bound authentication

This matters because the current `verifyPinWithHardwareBinding()` ultimately uses hardware unwrap.

Therefore the lock screen must **not** call the now-generic locked-denied `hardwareUnwrap()`.

Instead:

```text
verifyPin(...)
```

can remain a locked-safe boolean authentication primitive.

For the existing hardware-binding behavior, create an internal:

```text
verifyPinWithHardwareBindingForUnlock(...)
```

that:

- is callable only by the session authentication path,
- performs its own epoch capture,
- uses a private hardware unwrap operation,
- returns only the authentication result,
- never exposes the unwrapped stored secret to the UI.

That preserves the existing authentication semantics without turning `hardwareUnwrap()` itself into a locked-state escape hatch.

---

# 6. Epoch becomes a session generation, not just a stale-result flag

Use:

```text
SessionEpochToken
```

with monotonically increasing epochs:

```text
session 0: LOCKED

unlock succeeds
session 1: UNLOCKED

LOCK
session 2: LOCKED

new unlock succeeds
session 3: UNLOCKED
```

Every secret-producing operation captures the current epoch before its first asynchronous step.

After **every security-relevant await boundary**, it verifies the epoch.

The critical rule is:

```text
stale result
    ↓
destroy mutable secret material where possible
    ↓
reject
    ↓
never install
    ↓
never persist
    ↓
never sync
    ↓
never update protected UI
```

---

# 7. Pre-await + post-await protection

For legacy encryption/decryption:

```text
requireUnlocked()
↓
captureEpoch()
↓
dispatch isolate
↓
await
↓
requireCurrent(epoch)
↓
accept result
```

Not:

```text
dispatch isolate
↓
await
↓
check epoch
```

The latter is insufficient because work has already begun.

### Required tests

```text
cryptoDeniedWhileLocked
legacyDecryptDeniedWhileLocked
legacyEncryptDeniedWhileLocked
hardwareUnwrapDeniedWhileLocked
deviceKeyUnwrapDeniedWhileLocked
```

The tests should also prove that the underlying isolate/native operation was **never dispatched**.

That requires a small test seam around the asynchronous backend rather than merely testing the thrown exception.

---

# 8. Secret material representation matters

For asynchronous decryption, epoch checking must happen **before converting temporary decrypted bytes into immutable** **`String`** **plaintext**.

Conceptually:

```text
CryptoIsolate → Uint8List plaintext
                       ↓
                 epoch check
                  ↙       ↘
             stale          current
               ↓                ↓
           zero bytes      SecureBytes
                                ↓
                           UTF-8 decode
```

This is substantially better than:

```text
Uint8List
↓
String plaintext
↓
epoch check
```

because the immutable String cannot be reliably zeroed.

The same principle applies to native hardware unwrap results: reject the stale native result before materializing plaintext into an application `String` wherever the existing platform channel permits.

---

# 9. Explicit caller-buffer ownership

Every session-key installation follows:

```text
caller Uint8List
        ↓
SecureBytes copies it
        ↓
caller Uint8List immediately zeroed
        ↓
SessionKeyMaterial owns authoritative copy
```

For example:

```text
installMasterKey(bytes)
installNoteEncryptionKey(bytes)
installGithubTokenEncryptionKey(bytes)
```

The caller never transfers ownership by reference.

### Failure rule

If copying into `SecureBytes` fails:

```text
caller buffer still gets zeroed
existing authoritative key remains intact
```

So replacement must be constructed before destroying an existing authoritative key.

---

# 10. `lockSync()` final ordering

This is now strict and failure-resistant:

```text
lockSync()
    1. state = LOCKED
    2. epoch++
    3. synchronously destroy MK
    4. synchronously destroy NEK
    5. synchronously destroy TEK
    6. clear session-key references
    7. detach cleanup callbacks
    8. detach ProviderContainer disposer
    9. execute cleanup callback #1
         catch
   10. execute cleanup callback #2
         catch
       ...
   11. dispose session ProviderContainer
         catch
   12. notify listeners independently
```

Nothing may `await`.

### Important refinement

An exception from one cleanup callback must not affect any later step.

Likewise, ProviderContainer disposal must be isolated from notification.

Do not log arbitrary cleanup errors because the exception could contain sensitive data.

The manager should therefore have no security-sensitive logging such as:

```text
"cleanup failed: $exception"
```

---

# 11. In-flight initialization gets detached on lock

The actual Stage 4 `MasterKeyManager` uses a single-flight Future for initialization.

Stage 5 must not simply leave that Future as the manager's active in-flight operation after locking.

On lock:

```text
current initialization handle
        ↓
detached from current session
```

but the Future itself is **not falsely claimed to be cancelled**.

When that Future later finishes:

```text
old epoch
↓
stale
↓
cannot promote
↓
cannot install
```

The completion callback must only clear the in-flight slot if it still belongs to that exact operation.

This also means a new session can start its own initialization even if an obsolete Future from the previous session is still finishing.

That is a useful additional invariant:

> Session N+1 must never join Session N's invalidated initialization Future.

---

# 12. Initialization promotion must be epoch-bound twice

The existing flow is effectively:

```text
fetch
→ generate provisional
→ publish
→ promote
```

It becomes:

```text
capture epoch
↓
fetch
↓
check epoch

generate provisional
↓
conditional publish
↓
check epoch

promote with epoch-bound authorization
```

The promotion method itself must require the current operation/session authorization.

Therefore even if a future caller forgets its post-await check, promotion itself still fails.

This directly covers:

```text
lockDuringMasterKeyInitializationCannotPromote
```

---

# 13. Recovery installation follows the same rule

Recovery:

```text
start recovery
↓
capture epoch
↓
await unwrap
↓
epoch changed?
      YES → zero result + reject
      NO  → install into SessionKeyMaterial
```

Installation itself must require the current epoch/session authorization.

This covers:

```text
lockDuringRecoveryCannotInstallMasterKey
```

The recovered caller buffer is copied and then zeroed immediately.

---

# 14. Password-change handling: epochs are not transactions

This distinction is now explicit.

### Session-security guarantee

```text
old async secret result
→ rejected after lock
→ zeroed where possible
→ never installed into active session
```

### Persistence/remote consistency

```text
remote request already started
→ may still finish
```

The epoch **cannot roll back GitHub**.

So the password-change implementation must:

```text
capture epoch
↓
async crypto work
↓
check epoch
↓
before NEW local commit, check epoch again
↓
before NEW remote write, check epoch again
↓
perform side effect
```

But if:

```text
remote write starts
↓
LOCK
↓
remote write completes
```

Stage 5 does not attempt to undo it.

Existing Stage 3 pending/reconciliation machinery remains responsible for dealing with consistency.

No password-state protocol redesign belongs here.

---

# 15. Same rule for GitHub sync

The actual code obtains the persisted crypto PIN, decrypts stored GitHub credentials, constructs a `GithubBackupService`, and performs remote writes.

The sequence should become:

```text
requireUnlocked()
↓
capture epoch
↓
read stored credential material
↓
await unwrap
↓
check epoch
↓
await decrypt
↓
check epoch
↓
construct remote service
↓
check epoch before each NEW remote side effect
↓
await remote write
↓
check epoch before local queue commit/clear
```

This means a lock can produce:

```text
remote write succeeded
local queue was NOT cleared because epoch changed
```

That is acceptable and should remain governed by existing reconciliation semantics.

We must not describe the epoch system as making that transaction atomic.

---

# 16. Provider boundary is now a hard security requirement

The actual app currently has the global Riverpod scope above `RocenApp`, while the plaintext `CaptureItem` collection is held by `localDatabaseProvider`. The codebase also contains `todoProvider` with plaintext task text.

Therefore the protected application container must own at least:

```text
localDatabaseProvider
todoProvider
navigationProvider
gridColumnsProvider
```

`themeProvider` may remain outside because it is non-sensitive.

More importantly:

```text
LOCKED
→ protected ProviderContainer does not exist
```

not:

```text
LOCKED
→ same ProviderContainer with widgets hidden
```

---

# 17. No protected provider may instantiate before unlock

The root architecture becomes:

```text
outer/global scope
    └── non-sensitive theme only

LOCKED
    └── no session ProviderContainer

UNLOCKED
    └── create Session ProviderContainer
            ├── localDatabaseProvider
            ├── todoProvider
            ├── navigationProvider
            ├── gridColumnsProvider
            └── protected application subtree
```

The existing provider declarations can remain globally declared; **provider instances**, not declarations, are session-owned.

The important code rule is that no protected provider is read by the shell, splash, lock screen, or bootstrap screen.

---

# 18. Database provider needs stale-load protection too

`DatabaseNotifier.build()` starts asynchronous `_initAndLoad()` work. The current implementation can therefore load plaintext after the provider's original UI has disappeared.

Stage 5 should add provider disposal/session invalidation protection:

```text
provider created
↓
capture session/provider generation
↓
await Hive load
↓
provider still alive AND generation valid?
    YES → install state
    NO  → discard result
```

This is not a crypto epoch, but it is the same stale-state principle.

Apply it to:

- `DatabaseNotifier`
- `TodoNotifier`
- relevant async UI loaders

This prevents an old provider operation from repopulating state after its session has been destroyed.

---

# 19. Provider disposal test must prove more than UI disappearance

Required:

```text
UNLOCK
↓
create session container
↓
instantiate localDatabaseProvider
↓
plaintext state exists
↓
LOCK
↓
session container disposed
↓
provider disposal observed
↓
old provider state is inaccessible
```

The test must not simply assert:

```text
LockScreen is visible
```

It must verify the provider lifecycle.

The same principle applies to any future provider capable of holding:

- decrypted notes
- tokens
- plaintext editors
- sensitive remote responses

Riverpod's disposal hooks are appropriate for provider-specific cleanup, but the outer session-container disposal remains the primary boundary. ([Riverpod](https://docs-v2.riverpod.dev/docs/concepts/provider_lifecycles?utm_source=chatgpt.com "Provider Lifecycles | Riverpod"))

---

# 20. Protected UI architecture

The actual root is:

```text
MaterialApp
    ↓
home: AnimatedSplashScreen
    ↓
Scaffold / active module
```

not a hand-built Navigator.

That is still fine.

Flutter's `MaterialApp.builder` receives the application's Navigator as `child`, and the documentation explicitly states that omitting that `child` replaces/removes the Navigator. ([Flutter API Docs](https://api.flutter.dev/flutter/material/MaterialApp/builder.html?utm_source=chatgpt.com "builder property - MaterialApp class - material library - Dart API"))

So the production structure should be conceptually:

```text
MaterialApp
    builder:
        SessionRoot
            ├── LOCKED
            │     └── LockScreen
            │
            └── UNLOCKED
                  └── Session ProviderContainer
                        └── original Navigator
                              └── AnimatedSplashScreen
                                    └── Rocen UI
```

When locked:

```text
SessionRoot
    → LockScreen
```

and the Navigator `child` is **not returned**.

Therefore the Navigator, its routes, its overlay, its dialogs, and the protected application subtree are removed.

That is materially different from putting a lock widget above the existing Navigator.

---

# 21. Splash screen

The existing splash itself contains only animation/background state and theme access, so it does not need to be treated as sensitive.

However, it should remain **inside** the protected Navigator rather than outside the session boundary unless there is a concrete reason otherwise.

That gives a very simple rule:

```text
new session
→ new Navigator
→ new splash
→ new application tree
```

This also ensures the old navigation state isn't restored automatically.

---

# 22. Sensitive controller cleanup

The actual codebase has many dialog-created controllers and timers, especially in `settings.dart` and `quicknote.dart`.

Use two layers:

### Normal widget disposal

Existing:

```text
TextEditingController.dispose()
Timer.cancel()
```

must remain.

### Session cleanup registry

For resources created outside a durable StatefulWidget lifecycle:

```text
registerSensitiveCleanup(callback)
```

On lock the callbacks are detached and executed independently.

Examples:

```text
PIN dialog controller
mnemonic controllers
token/repository controllers
temporary debounce timers
countdown timers
```

The registry must not contain long-lived session-key ownership. It is only an emergency synchronous cleanup mechanism.

---

# 23. First-run semantics: unresolved policy decision

This is the remaining architectural issue.

The actual UI calls the credential:

> `SETUP CRYPTOGRAPHY PASSWORD`

and uses it for cryptographic operations such as note protection. It is not currently described or implemented as a mandatory application login.

Therefore we cannot silently claim:

```text
system_crypto_pin == application login credential
```

### There are only two honest designs

**Option A — deliberate Stage 5 policy change**

Explicitly redefine the existing cryptography password as the application-session unlock credential.

Then:

```text
fresh install
→ security-password setup
→ LOCKED
→ unlock with that credential
→ UNLOCKED
```

This is straightforward, but it is a **product/security-policy decision**.

**Option B — preserve current semantics**

Introduce a separate application-session credential.

That would require a new credential lifecycle, recovery meaning, storage format, setup UX, and probably new synchronization semantics.

That is not a reasonable thing to smuggle into Stage 5.

So I would **not implement either interpretation without explicit approval**.

Until this is decided, Stage 5 can only be implemented as a framework, not signed off as the final application-session policy.

---

# 24. Fresh installations must not dead-end

Regardless of the decision:

```text
no existing password state
```

must never produce:

```text
LOCKED
→ enter password that doesn't exist
→ no way forward
```

The root state must distinguish:

```text
BOOTSTRAP
```

from:

```text
LOCKED
```

A bootstrap screen is outside the protected session and must not instantiate protected providers.

---

# 25. Clipboard remains explicitly out of scope

No clipboard subsystem.

No global clipboard clearing.

No changes to the current media-oriented clipboard feature.

Future sensitive text-copy functionality gets its own sensitive-clipboard handling.

---

# 26. Android capture protection

The final production design remains:

```text
MainActivity.onCreate()
    ↓
FLAG_SECURE on Rocen window
```

rather than Settings-only protection.

Android documents `FLAG_SECURE` as window-level protection against screenshots and display of the window on non-secure displays. ([Android Developers](https://developer.android.com/about/versions/14/features/screenshot-detection?utm_source=chatgpt.com "Detect when users take device screenshots  |  Android Developers"))

Stage 5 should remove the existing Settings-scoped protection path.

It should **not** claim:

```text
all imaginable capture mechanisms are impossible
```

The accurate claim is window-level Android capture protection.

### Current blocker

I verified the supplied Stage 4 archive contains only:

```text
android/app/build.gradle.kts
```

and not the actual:

```text
android/app/src/main/.../MainActivity.kt
AndroidManifest.xml
```

Therefore no native implementation should be fabricated or claimed complete.

---

# 27. Final mandatory test matrix

Your original list is retained and expanded.

### Session destruction

```text
lockZeroesMasterKey
lockInvalidatesSessionEpoch
lockZeroesDerivedKeys
doubleLockIsIdempotent
```

### Locked-state preflight denial

```text
cryptoDeniedWhileLocked
legacyDecryptDeniedWhileLocked
legacyEncryptDeniedWhileLocked
hardwareUnwrapDeniedWhileLocked
deviceKeyUnwrapDeniedWhileLocked
```

Each must prove the underlying async/native operation did not begin.

### Stale-result rejection

```text
staleDecryptResultRejected
staleHkdfResultRejected
staleUnlockResultRejected
staleEncryptResultRejected
staleHardwareUnwrapRejected
```

### Race tests

```text
lockDuringAsyncLegacyDecrypt
lockDuringAsyncLegacyEncrypt
lockDuringAsyncHardwareUnwrap

lockDuringMasterKeyInitializationCannotPromote
lockDuringRecoveryCannotInstallMasterKey
lockDuringPasswordChangeDoesNotAcceptStaleSecrets
```

### Ownership

```text
sessionKeyInstallationCopiesAndZeroesCallerBuffer
noSecondPersistentMasterKeyInMasterKeyManager
```

### Failure-resistant locking

```text
cleanupCallbackFailureDoesNotAbortLock
allCleanupCallbacksRunAfterOneFails
```

Also verify that:

```text
ProviderContainer disposal
listener notification
```

still occur after cleanup failure.

### Provider boundary

```text
sessionProviderContainerDisposed
noProtectedProviderInstantiatedBeforeUnlock
protectedProviderStateDestroyedWithSession
```

### Lifecycle

```text
resumeDoesNotUnlock
inactiveLocks
hiddenLocks
pausedLocks
detachedLocks
```

### UI

```text
protectedUiRemoved
sensitiveControllersCleaned
navigationStateDiscardedOnLock
dialogsRemovedOnLock
```

And the central cross-session invariant:

```text
SESSION N
    ↓
begin secret operation
    ↓
LOCK → epoch N+1
    ↓
operation completes
    ↓
result destroyed/rejected
    ↓
NEW SESSION N+2
    ↓
old result still cannot enter session
```

---

# 28. Revised Stage 5 file plan

### New

```text
lib/core/session_key_material.dart
lib/core/session_security_manager.dart
lib/core/session_epoch.dart          // only if needed to keep dependencies clean
lib/features/session_lock_screen.dart
```

Possibly:

```text
lib/features/session_bootstrap_screen.dart
```

depending on the credential-policy decision.

### Modified

```text
lib/core/master_key_manager.dart
lib/core/crypto_engine.dart
lib/core/domain_key_derivation.dart
lib/core/password_key_derivation.dart
lib/core/database.dart
lib/features/settings.dart
lib/features/quicknote.dart
lib/features/ideainbox.dart
lib/features/bookmarks.dart
lib/features/clipboard.dart
lib/main.dart
```

Native, once actual files are supplied:

```text
android/app/src/main/.../MainActivity.kt
android/app/src/main/AndroidManifest.xml
```

### Tests

```text
test/session_security_manager_test.dart
test/session_epoch_test.dart
test/session_gate_test.dart
test/master_key_manager_test.dart
test/domain_key_derivation_test.dart
test/crypto_engine_test.dart
test/password_key_derivation_test.dart
```

No Stage 6 envelope/AAD migration belongs in those changes.

---

# 29. Final completion gate

I would now use this exact gate:

```text
[ ] SessionKeyMaterial is the sole authoritative live key owner
[ ] MasterKeyManager contains no second persistent MK buffer
[ ] LOCKED rejects new generic crypto before async work begins
[ ] Unlock/authentication has a narrow explicit exception path
[ ] Every secret-producing operation captures an epoch
[ ] Every async secret result is epoch-validated
[ ] stale mutable secret material is zeroed where possible
[ ] stale results cannot install/persist/sync/update UI
[ ] stale initialization cannot promote
[ ] stale recovery cannot install MK
[ ] Session N results cannot enter Session N+1
[ ] lockSync is fully synchronous
[ ] cleanup exceptions cannot abort destruction
[ ] ProviderContainer is genuinely session-scoped
[ ] protected providers are not instantiated before unlock
[ ] plaintext provider state disappears with container disposal
[ ] protected Navigator subtree is genuinely removed
[ ] inactive/hidden/paused/detached lock
[ ] resumed never unlocks
[ ] splash cannot preserve protected application state
[ ] sensitive controllers/timers have lock cleanup
[ ] password-change epochs do not masquerade as transaction atomicity
[ ] remote side effects remain governed by Stage 3 reconciliation
[ ] no clipboard subsystem added
[ ] global FLAG_SECURE is implemented only after real Android files are supplied
[ ] Settings-only capture protection removed
[ ] no Stage 6 format/AAD migration
[ ] no Stage 3 recovery/persistence protocol redesign
[ ] all mandatory regression tests pass
[ ] first-run/session credential semantics are explicitly approved
[ ] documentation makes no physical-memory-erasure guarantee
```

## Bottom line

The revised architecture is now security-correct about the two issues that were still missing: **locked-state preflight denial** and **session/provider ownership**.

The remaining issue is not an implementation detail: **the existing** **`system_crypto_pin`** **currently means “cryptography password,” while a real application-session gate requires an authentication credential with global semantics.** That meaning must be explicitly decided before the production root is changed.

The Android native portion is independently blocked until the real Activity and manifest are available.

So the correct state is **Stage 5 design finalized for review, implementation not yet approved**.

# AUDIT

There is still one implementation-blocking architecture issue.

The proposed `MaterialApp.builder` session gate is too deep in the current widget/provider tree to satisfy the invariant:

> No protected provider may instantiate before session unlock.

## Actual current structure

The current `main.dart` does this before `MaterialApp.builder` can execute:

```text
ProviderScope
    ↓
RocenApp.build()
    ↓
ref.watch(navigationProvider)
    ↓
MaterialApp
    ↓
MaterialApp.builder
```

`navigationProvider` is therefore accessed before the proposed session gate.

The current `navigationProvider` also references `CaptureModule` values containing actual screen widget instances such as `QuickNoteScreen()`, `ClipboardScreen()`, `BookmarksScreen()`, `IdeaInboxScreen()`, and `SettingsScreen()`.

Therefore the proposed structure:

```text
MaterialApp
    builder:
        SessionGate
```

does NOT by itself establish:

```text
LOCKED
→ protected providers do not exist
```

## Required correction

Move the protected `MaterialApp`/Navigator/application tree itself inside the unlocked session boundary.

The correct conceptual structure is:

```text
OUTER ProviderScope
    │
    └── RocenShell
          │
          ├── non-sensitive outer state
          │
          └── SessionGate
                │
                ├── BOOTSTRAP
                │     └── setup shell
                │
                ├── LOCKED
                │     └── LockScreen
                │
                └── UNLOCKED
                      │
                      ├── create Session ProviderContainer
                      │
                      └── UncontrolledProviderScope
                            │
                            └── protected MaterialApp
                                  │
                                  └── existing application
                                        └── navigationProvider
```

The critical invariant is:

```text
LOCKED
    → no protected ProviderContainer
    → no protected Navigator
    → no protected application MaterialApp
    → no navigationProvider instance
    → no localDatabaseProvider instance
    → no todoProvider instance
    → no gridColumnsProvider instance
```

## Do not rely on widgets merely being hidden

Do not implement:

```text
existing MaterialApp/Navigator
    +
LockScreen above it
```

and do not accept:

```text
existing ProviderContainer
    +
providers still instantiated
    +
UI visually hidden
```

The protected session must genuinely not exist while locked.

## Refactor navigation state

The current `CaptureModule` stores actual widget instances:

```text
CaptureModule.quickNote → QuickNoteScreen()
CaptureModule.clipboard → ClipboardScreen()
...
```

Change this so the navigation state stores only a module identifier/enum:

```text
CaptureModule
    ├── quickNote
    ├── clipboard
    ├── bookmark
    ├── ideaInbox
    └── settings
```

Construct the actual screen widgets only inside the unlocked session.

This prevents globally retained widget instances from becoming another accidental sensitive-state holder.

## Provider test requirement

Do not merely test that the LockScreen appears.

Add a test proving:

```text
application starts
→ LOCKED
→ navigationProvider has NOT been instantiated
→ localDatabaseProvider has NOT been instantiated
→ todoProvider has NOT been instantiated
→ protected ProviderContainer does not exist
```

Then:

```text
explicit unlock
→ session ProviderContainer created
→ protected MaterialApp created
→ navigationProvider may instantiate
→ protected providers may instantiate
```

Then:

```text
LOCK
→ ProviderContainer disposed
→ protected MaterialApp/Navigator removed
→ protected provider instances disposed
```

## Async provider requirement

Audit EVERY asynchronous provider, not only `DatabaseNotifier` and `TodoNotifier`.

For each async load:

```text
provider/session starts operation
    ↓
await
    ↓
provider/session disposed or generation invalidated
    ↓
operation completes
    ↓
result MUST NOT re-enter provider state
```

`DatabaseNotifier._initAndLoad()` is an immediate example from the current Stage 4 codebase.

Apply the same stale-state principle to every provider or async loader capable of returning protected state.

## Security API requirement

Keep the mandatory preflight rule:

```text
LOCKED
    ↓
generic crypto API
    ↓
reject before async/native work starts
```

But make security-sensitive asynchronous operations carry explicit session/epoch authorization where practical.

Do not rely only on developers remembering to call a global `requireUnlocked()` function.

The desired model is:

```text
SessionSecurityManager
    ↓
capture SessionEpochToken
    ↓
authorized operation
    ↓
await
    ↓
validate token
    ↓
accept/reject result
```

Generic callers must not be able to manufacture a valid authorization token.

## MK ownership verification

After the refactor, perform a repository-wide ownership audit for:

```text
_masterKeyBytes
SecureBytes
requireAuthoritativeMasterKeyBytes
Uint8List.fromList(...)
master-key installation methods
```

Produce a table proving:

```text
SessionKeyMaterial
    → sole authoritative live MK owner

MasterKeyManager
    → no second persistent MK buffer

transient caller copies
    → zeroed after use

stale results
    → zeroed/rejected

Provider state
    → never contains MK
```

Do not consider Stage 5 ownership complete based only on class names or intended design. Verify the final code.

## Unlocking invariant

During:

```text
UNLOCKING
```

the following must remain absent:

```text
protected ProviderContainer
protected Navigator
protected plaintext application state
```

Authentication/setup must happen from the outer shell.

Only after successful, current-epoch authentication should the protected session be created.

## Completion gate addition

Stage 5 must not be marked complete unless:

```text
[ ] Protected providers are provably absent before unlock
[ ] Protected MaterialApp/Navigator is absent while locked
[ ] navigationProvider does not instantiate while locked
[ ] Actual screen widgets are not globally retained by navigation state
[ ] All async providers reject stale post-disposal results
[ ] Session authorization cannot be fabricated by ordinary callers
[ ] Final repository scan proves one authoritative MK owner
```

Do not weaken these requirements by keeping the existing global ProviderContainer and merely hiding the UI.

# IMPLEMENTER

This is what AI said:

Agreed. This correction changes the root architecture again, and it is necessary. The previous `MaterialApp.builder` design did **not** prove the absence of protected provider instances because `RocenApp.build()` already read `navigationProvider` before `MaterialApp.builder` was reached.

I would now freeze the Stage 5 design around the following structure.

## Final Stage 5 root architecture

```text
OUTER ProviderScope
    │
    └── RocenShell
          │
          ├── non-sensitive shell state only
          │
          └── SessionGate
                │
                ├── BOOTSTRAP
                │     └── non-sensitive setup UI
                │
                ├── LOCKED
                │     └── non-sensitive Lock MaterialApp
                │
                └── UNLOCKING
                │     └── authentication/setup UI only
                │
                └── UNLOCKED
                      │
                      ├── create Session ProviderContainer
                      │
                      └── UncontrolledProviderScope
                            │
                            └── protected MaterialApp
                                  │
                                  └── existing application
                                      │
                                      └── navigationProvider
                                            │
                                            ├── QuickNoteScreen
                                            ├── ClipboardScreen
                                            ├── BookmarksScreen
                                            ├── IdeaInboxScreen
                                            └── SettingsScreen
```

The important distinction is that the locked `MaterialApp`, if used for the lock/setup surface, is **not the protected application MaterialApp**. It contains no protected providers, navigation state, or application data.

When unlocked, that entire application MaterialApp is constructed fresh inside the session container.

Riverpod's `UncontrolledProviderScope` deliberately does not dispose the supplied container, so Stage 5 must own and dispose the session `ProviderContainer` explicitly. ([Dart packages](https://pub.dev/documentation/flutter_riverpod/latest/flutter_riverpod/UncontrolledProviderScope-class.html?utm_source=chatgpt.com "UncontrolledProviderScope class - flutter_riverpod library - Dart API"))

---

# 1. `RocenApp` must stop reading protected state

The current problem is exactly:

```text
ProviderScope
    ↓
RocenApp.build()
    ↓
ref.watch(navigationProvider)
    ↓
MaterialApp
    ↓
builder
```

That entire path must disappear.

`RocenApp`/`RocenShell` may read only outer, non-sensitive state.

For example:

```text
themeProvider
```

is acceptable as outer state because it contains only the persisted theme preference.

But these must never be read by the outer shell:

```text
navigationProvider
localDatabaseProvider
todoProvider
gridColumnsProvider
```

The protected MaterialApp owns all of them.

---

# 2. Session ProviderContainer has a real lifetime

I would create it only when the session transitions to `UNLOCKED`.

Conceptually:

```text
LOCKED
    sessionContainer == null

successful unlock
    ↓
new ProviderContainer(parent: outerContainer)
    ↓
UncontrolledProviderScope
    ↓
protected MaterialApp
```

On lock:

```text
protected MaterialApp removed
    ↓
sessionContainer.dispose()
    ↓
sessionContainer = null
```

The manual container is owned by `SessionGate`; nothing else may dispose it.

`ProviderContainer` supports an explicit `parent`, while Riverpod has deprecated relying on `ProviderScope.parent`; the child-container approach is therefore the appropriate composition mechanism for this design. ([Dart packages](https://pub.dev/documentation/flutter_riverpod/latest/flutter_riverpod/ProviderContainer-class.html?utm_source=chatgpt.com "ProviderContainer class - flutter_riverpod library - Dart API"))

The parent container should contain only intentionally outer state.

---

# 3. No protected provider may be instantiated in the outer container

This is now a hard invariant:

```text
before unlock:
    outerContainer.exists(navigationProvider)      == false
    outerContainer.exists(localDatabaseProvider)   == false
    outerContainer.exists(todoProvider)            == false
    outerContainer.exists(gridColumnsProvider)     == false
```

The protected providers may only exist in the child session container.

The test should inspect both containers, not merely inspect widgets.

There must also be no code path such as:

```text
outerContainer.read(localDatabaseProvider)
```

during startup, splash, authentication, lifecycle handling, or settings bootstrap.

---

# 4. `navigationProvider` must become data-only

This change is mandatory.

Current:

```text
enum CaptureModule {
  quickNote('NOTE', QuickNoteScreen()),
  clipboard('CLIP', ClipboardScreen()),
  bookmark('TODO', BookmarksScreen()),
  ideaInbox('YEAR', IdeaInboxScreen()),
  settings('SET', SettingsScreen());
}
```

This globally constructs actual application screens.

That is incompatible with a strict session boundary.

It becomes:

```text
enum CaptureModule {
  quickNote('NOTE'),
  clipboard('CLIP'),
  bookmark('TODO'),
  ideaInbox('YEAR'),
  settings('SET');

  final String label;
  const CaptureModule(this.label);
}
```

Then the protected application constructs the actual widget:

```text
switch (activeModule) {
  case CaptureModule.quickNote:
    return const QuickNoteScreen();
  case CaptureModule.clipboard:
    return const ClipboardScreen();
  ...
}
```

That construction exists only after the protected MaterialApp exists.

So:

```text
LOCKED
    navigationProvider does not exist
    CaptureModule contains no Widget instances
    no protected screen objects exist
```

This removes a second potential route for sensitive widget state to outlive the session.

---

# 5. Move `themeProvider` out of `main.dart`

There is a practical dependency problem created by this refactor.

`navbar.dart` currently imports `main.dart` solely to access `themeProvider`.

Once `main.dart` becomes the composition root, this creates an unnecessary dependency cycle.

I would move:

```text
ThemeNotifier
themeProvider
```

to something like:

```text
lib/core/app_theme.dart
```

Then:

```text
main.dart
navbar.dart
splashscreen.dart
features/*
```

can depend on the theme provider without depending on the application composition root.

This is not a security feature by itself, but it makes the new ownership boundaries enforceable rather than relying on import structure.

---

# 6. Locked `MaterialApp` vs protected `MaterialApp`

This distinction is important.

The strict invariant is:

```text
LOCKED
    → no protected MaterialApp
    → no protected Navigator
```

It does **not** require the process to contain literally zero Material widgets.

The lock screen can use a tiny non-sensitive Material shell:

```text
LOCKED
    Outer/session shell
       ↓
    Lock MaterialApp
       ↓
    LockScreen
```

That MaterialApp must contain no:

- `navigationProvider`
- database provider
- todo provider
- editor state
- decrypted content
- application routes

When the session unlocks:

```text
Lock MaterialApp disposed
       ↓
Session ProviderContainer created
       ↓
Protected MaterialApp created
```

When locking again, that protected MaterialApp is removed entirely.

This gives us a clean separation between **security shell** and **protected application**.

---

# 7. Unlocking stays outside the protected application

During:

```text
UNLOCKING
```

the protected container must still not exist.

Therefore authentication lives in:

```text
RocenShell
    └── SessionGate
          └── UnlockScreen
```

not:

```text
protected application
    └── UnlockDialog
```

The successful sequence is:

```text
UNLOCKING
    ↓
authentication succeeds
    ↓
current epoch confirmed
    ↓
session MK/NEK/TEK installed
    ↓
new Session ProviderContainer created
    ↓
protected MaterialApp constructed
```

If authentication fails or becomes stale:

```text
LOCKED
```

and no protected application is constructed.

---

# 8. Provider inventory from the actual Stage 4 code

The repository scan found five provider declarations:

| ProviderCurrent behaviorStage 5 |                                |                              |
| ------------------------------- | ------------------------------ | ---------------------------- |
| `themeProvider`                 | synchronous                    | Outer shell                  |
| `navigationProvider`            | synchronous but stores Widgets | Session-only, enum/data-only |
| `localDatabaseProvider`         | async initialization           | Session-only                 |
| `todoProvider`                  | async initialization           | Session-only                 |
| `gridColumnsProvider`           | synchronous                    | Session-only                 |

The important async provider cases are therefore:

```text
DatabaseNotifier._initAndLoad()
TodoNotifier._initAndLoad()
```

The database provider is particularly sensitive because `CaptureItem.content` is plaintext in memory.

The todo provider contains plaintext task text.

Both must disappear with the session container.

---

# 9. Async provider generation invalidation

Provider disposal alone is not sufficient.

For every async provider/loader that can produce protected state:

```text
provider starts
    ↓
capture session/generation identity
    ↓
await
    ↓
container/provider still valid?
       │
       ├── yes → commit result
       │
       └── no  → discard result
```

For `DatabaseNotifier._initAndLoad()`:

```text
create provider
    ↓
capture generation
    ↓
await Hive.openBox / read
    ↓
check generation + provider alive
    ↓
only then assign state
```

If the provider has been disposed:

```text
plaintext result
    ↓
must not be assigned to provider state
```

The same rule applies to `TodoNotifier`.

And the implementation audit must enumerate any additional async loader outside a formal provider that can populate protected state.

That includes the feature-level asynchronous operations in:

- QuickNote
- Settings/password handling
- GitHub synchronization
- Clipboard/import/gallery state

The rule is the same: a post-disposal result cannot repopulate protected state.

---

# 10. Provider tests become mandatory architectural tests

The important test is not:

```text
expect(find.byType(LockScreen), findsOneWidget);
```

It must inspect the provider containers.

### Startup

```text
application starts
    ↓
LOCKED
```

Assert:

```text
outerContainer.exists(navigationProvider) == false
outerContainer.exists(localDatabaseProvider) == false
outerContainer.exists(todoProvider) == false
outerContainer.exists(gridColumnsProvider) == false

sessionContainer == null
```

### Unlock

```text
explicit unlock
    ↓
sessionContainer != null
    ↓
protected MaterialApp exists
```

Then instantiate the application and assert:

```text
sessionContainer.exists(navigationProvider) == true
sessionContainer.exists(localDatabaseProvider) == true
```

where those providers are actually accessed.

### Lock

```text
lock
    ↓
protected MaterialApp removed
    ↓
sessionContainer disposed
```

Assert:

```text
sessionContainer no longer exists
protected provider disposal callbacks fired
old provider instances cannot be read
```

This is significantly stronger than testing widget visibility.

---

# 11. Async provider disposal test

For `DatabaseNotifier`:

```text
create session container
    ↓
instantiate database provider
    ↓
block Hive load with Completer
    ↓
dispose session container
    ↓
release Hive load
    ↓
future completes
```

Assert:

```text
no state mutation occurs
```

Do the equivalent for `TodoNotifier`.

Then apply the same pattern to each additional protected async loader discovered during the repository audit.

---

# 12. Session authorization must be capability-based

The generic API should not merely be:

```text
session.requireUnlocked();
final epoch = session.currentEpoch;
```

because ordinary callers can then potentially capture an integer and manufacture equivalent state.

Instead use a non-forgeable authorization capability:

```text
SessionAuthorizationToken
```

with construction controlled by the session-security implementation.

Conceptually:

```text
SessionSecurityManager
    ↓
captureAuthorization()
    ↓
SessionAuthorizationToken
    ↓
authorized operation
    ↓
await
    ↓
validate(token)
```

The token contains an opaque capability/identity plus the epoch.

A caller cannot manufacture a valid token simply by writing:

```text
SessionAuthorizationToken(42)
```

because there is no public constructor that creates a valid capability.

The token should also be tied to the specific session generation:

```text
SESSION N token
    !=
SESSION N+1 token
```

This makes old authorization useless even if an old operation survives until a future session.

---

# 13. Crypto API structure

Every generic production cryptographic operation becomes:

```text
crypto entry
    ↓
obtain valid session authorization
    ↓
reject immediately if locked
    ↓
capture authorization
    ↓
start async/native/isolate operation
    ↓
await
    ↓
validate authorization
    ↓
accept or destroy result
```

Therefore:

```text
LOCKED
    ↓
CryptoEngine.decryptProcess()
    ↓
authorization fails synchronously
    ↓
no isolate dispatch
```

The same applies to:

```text
encryptProcess
encryptProcessWithParams
decryptProcess
decryptProcessWithParams
hardwareUnwrap
unwrapDeviceKey
future MK/NEK/TEK operations
```

Unlock/recovery operations are separate privileged authentication paths.

---

# 14. Master-Key initialization

The initialization race now uses the same capability mechanism.

```text
Session N
    ↓
capture auth N
    ↓
fetch
    ↓
validate N

generate provisional MK
    ↓
publish
    ↓
validate N
    ↓
epoch-bound promotion
```

Then:

```text
LOCK
    ↓
epoch N+1
    ↓
destroy provisional MK
```

When publish returns:

```text
validate auth N
    ↓
FAIL
    ↓
promotion impossible
```

`promoteProvisionalToAuthoritative()` itself should require valid session authorization.

So there are two defenses:

```text
caller post-await check
+
promotion-level authorization check
```

---

# 15. Recovery

Same architecture:

```text
UNLOCKING
    ↓
capture auth N
    ↓
await recovery unwrap
    ↓
validate auth N
    ↓
copy recovered MK into SessionKeyMaterial
    ↓
zero caller buffer
    ↓
session becomes UNLOCKED
```

After a lock:

```text
old recovery result
    ↓
authorization invalid
    ↓
zero
    ↓
reject
    ↓
no MK installation
```

---

# 16. SessionKeyMaterial ownership audit

The final repository audit must search specifically for:

```text
_masterKeyBytes
SecureBytes
requireAuthoritativeMasterKeyBytes
setAuthoritativeMasterKeyFromRecovery
Uint8List.fromList(...)
```

The expected result is:

| LocationAllowed ownership |                                 |
| ------------------------- | ------------------------------- |
| `SessionKeyMaterial`      | sole authoritative MK           |
| `SessionKeyMaterial`      | sole authoritative NEK          |
| `SessionKeyMaterial`      | sole authoritative TEK          |
| `MasterKeyManager`        | no persistent second MK buffer  |
| `DomainKeyDerivation`     | no persistent NEK/TEK owner     |
| callers                   | transient defensive copies only |
| stale results             | destroyed/rejected              |
| providers                 | never contain MK/NEK/TEK        |

The audit should be based on actual repository references, not class names or intended architecture.

---

# 17. DomainKeyDerivation

The final architecture is:

```text
DomainKeyDerivation
    ↓
capture authorization
    ↓
obtain authoritative MK from SessionKeyMaterial
    ↓
HKDF
    ↓
validate authorization
    ↓
install/replace authoritative NEK or TEK
    ↓
return temporary defensive copy
```

`DomainKeyDerivation` owns no long-lived derived-key buffer.

That leaves exactly one owner.

---

# 18. Lock destruction

The final synchronous sequence remains:

```text
lockSync()
    1. sessionState = LOCKED
    2. epoch++
    3. zero MK
    4. zero NEK
    5. zero TEK
    6. clear SessionKeyMaterial references
    7. detach cleanup registry
    8. detach session-container reference
    9. invoke every cleanup independently
       catch without logging sensitive exception content
   10. dispose session ProviderContainer
   11. notify listeners
```

No `await`.

No cleanup callback can prevent key destruction.

No cleanup callback can prevent another cleanup callback.

No cleanup callback can prevent ProviderContainer disposal.

---

# 19. Lifecycle

Lifecycle belongs to `RocenShell`, not protected application code.

```text
inactive → lockSync()
hidden   → lockSync()
paused   → lockSync()
detached → lockSync()

resumed  → do nothing
```

This means:

```text
LOCKED
    ↓
resumed
    ↓
LOCKED
```

The session container is not recreated automatically.

The old navigation tree is not restored.

The old ProviderContainer is not restored.

The old MK/NEK/TEK are not restored.

---

# 20. Global screen-capture boundary

The Android implementation remains blocked until the real native project exists.

Once available:

```text
real MainActivity
    ↓
window FLAG_SECURE
```

The Settings-only MethodChannel protection is removed.

The protected application therefore has a window-wide control rather than one that exists only while Settings is mounted.

`FLAG_SECURE` is documented as preventing the window from appearing in screenshots and from being shown on non-secure displays; it should not be described as defeating every possible capture mechanism.

---

# 21. No clipboard subsystem

No change.

There is no reason for Stage 5 to introduce global clipboard management.

---

# 22. Credential-policy blocker remains real

There is still one deliberate product/security decision that implementation cannot silently make.

The actual code calls `system_crypto_pin` a cryptography password and uses it for cryptographic operations. It is not currently defined as a mandatory application-session credential.

Therefore Stage 5 cannot silently transform:

```text
optional cryptography credential
```

into:

```text
mandatory application login
```

The root architecture is ready for either policy, but the exact unlock credential must be explicitly decided before implementing the production `BOOTSTRAP → LOCKED → UNLOCKED` flow.

Until that decision is made, the security framework can be implemented around a session-authentication abstraction without inventing the credential semantics.

---

# 23. Final Stage 5 architecture

The corrected complete model is therefore:

```text
                     OUTER ProviderScope
                              │
                         RocenShell
                              │
                  ┌───────────┴───────────┐
                  │                       │
             theme/bootstrap        SessionSecurityManager
                  │                       │
                  │                 SessionKeyMaterial
                  │                  ├── MK
                  │                  ├── NEK
                  │                  └── TEK
                  │
                  └──────── SessionGate ──────────┐
                                                   │
                               ┌───────────────────┼───────────────────┐
                               │                   │                   │
                           BOOTSTRAP            LOCKED             UNLOCKING
                               │                   │                   │
                         setup shell         lock MaterialApp   auth only
                               │                   │                   │
                               └───────────────────┴───────────────────┘
                                                   │
                                           successful auth
                                                   │
                                          epoch authorization
                                                   │
                                      create SessionContainer
                                                   │
                                      UncontrolledProviderScope
                                                   │
                                      protected MaterialApp
                                                   │
                                      navigationProvider
                                                   │
                              ┌────────────────────┼───────────────────┐
                              │                    │                   │
                         database state       todo state         UI/editor state
```

On lock:

```text
protected MaterialApp
        ↓
removed

session ProviderContainer
        ↓
disposed

session keys
        ↓
zeroed

epoch
        ↓
invalidated

old async operations
        ↓
rejected

new crypto while locked
        ↓
rejected before starting
```

## Stage 5 implementation blockers after this correction

The architecture itself is now coherent. I would **not** start production coding until these two external decisions/inputs are resolved:

```text
[BLOCKER 1]
Explicit definition of the application-session authentication credential
when system_crypto_pin is currently only a cryptography credential.

[BLOCKER 2]
Actual android/app/src/.../MainActivity.kt + AndroidManifest.xml tree
for real FLAG_SECURE implementation.
```

Everything else is now sufficiently specified to implement without weakening the security boundary.

Most importantly, the previous problematic condition:

```text
LOCKED
    +
global ProviderContainer
    +
navigationProvider already instantiated
    +
UI merely hidden
```

is no longer part of the design.

The intended Stage 5 invariant is now enforceable directly in the architecture:

> **Before unlock, the protected ProviderContainer, protected MaterialApp/Navigator, navigation provider instance, database provider instance, todo provider instance, and protected screen instances do not exist.**

# AUDIT

The architecture is now accepted as the Stage 5 baseline. Do not redesign the root architecture again.

Before implementation begins, add these final mandatory security requirements.

## 1. Unlock must be transactional with rollback

Do not leave session key material installed merely because authentication succeeded.

The unlock flow must behave like:

```text
AUTHENTICATION
    ↓
capture authorization
    ↓
perform async authentication
    ↓
validate authorization
    ↓
prepare/copy session key material
    ↓
create protected ProviderContainer
    ↓
establish protected application root
    ↓
COMMIT SESSION AS UNLOCKED
```

If any step after authentication fails:

```text
rollback
    ↓
zero all prepared/live session keys
    ↓
invalidate authorization/epoch
    ↓
dispose any created session container
    ↓
return to LOCKED
```

There must never be a state where:

```text
session keys exist
+
session is not fully established
```

The protected application must only become `UNLOCKED` after the complete session transaction succeeds.

## 2. BOOTSTRAP and UNLOCKING are credential-sensitive

Do not classify these states simply as "non-sensitive."

They do not contain the protected application dataset, but they can contain:

* password/PIN
* recovery words
* authentication state
* temporary secret buffers

Therefore they must receive the same security treatment for:

```text
screen capture
lifecycle interruption
controller cleanup
timer cleanup
logging
stale async-result rejection
```

Use the terminology:

```text
protected application state
```

for notes/tokens/etc., and:

```text
credential-sensitive shell
```

for bootstrap/authentication UI.

## 3. Provider disposal is not sufficient by itself

A session ProviderContainer destroys provider-owned state, but independent asynchronous closures can still retain plaintext values after the provider has been disposed.

Audit all async application operations that can hold or produce sensitive data.

At minimum inspect:

```text
GitHub synchronization
password rotation
backup restore/import
note decryption
note encryption
hardware unwrap
database loads
todo loads
feature-level async callbacks
timers/debounced saves
```

Required invariant:

```text
SESSION N
    ↓
async sensitive operation starts
    ↓
SESSION N LOCKED
    ↓
async operation completes
    ↓
result cannot update provider state
result cannot update UI
result cannot persist sensitive data
result cannot initiate a new protected remote side effect
```

Use the session authorization/generation mechanism for these operations where applicable.

A disposed provider alone is not proof that stale feature-level async work is harmless.

## 4. Repository-wide sensitive logging audit

The Stage 4 snapshot contains diagnostic logging around restore/sync operations that can expose sensitive metadata and exception information.

Stage 5 must audit and eliminate logging of:

```text
plaintext note data
note titles
potentially sensitive filenames
password/PIN values
mnemonic/recovery words
tokens
crypto inputs/outputs
raw exception strings when they could contain protected data
raw stack traces when they could expose protected data
```

Prefer structured non-sensitive diagnostic events such as:

```text
SESSION_LOCKED
SESSION_EPOCH_INVALIDATED
CRYPTO_OPERATION_REJECTED_LOCKED
RESTORE_DECRYPT_FAILED
SYNC_OPERATION_FAILED
PROVIDER_SESSION_DISPOSED
```

Never interpolate potentially sensitive objects directly into logs.

This requirement applies in debug builds as well as production for security-sensitive material.

## 5. No-secret-after-failed-unlock invariant

Add an explicit regression test:

```text
authentication succeeds
↓
session-key installation succeeds
↓
session ProviderContainer creation fails
↓
session remains LOCKED
↓
all prepared/live session keys are zeroed
↓
no protected provider exists
↓
no protected MaterialApp exists
```

Also test:

```text
authentication succeeds
↓
protected root creation begins
↓
lifecycle lock occurs
↓
old unlock transaction becomes stale
↓
all results are rejected
↓
session remains LOCKED
```

## 6. Credential UI interruption

For BOOTSTRAP and UNLOCKING, test:

```text
credential entry in progress
↓
inactive/hidden/paused/detached
↓
credential controllers/timers cleaned
↓
pending authentication invalidated
↓
session stays LOCKED or returns safely to BOOTSTRAP
↓
no old authentication result can establish a session
```

Do not automatically resume an interrupted credential transaction.

## 7. Sensitive async closures need the same session authority

Where a feature-level async operation can perform a protected action after an `await`, require a valid session authorization before accepting the result.

Examples:

```text
decrypt → provider update
decrypt → UI update
decrypt → Hive write
decrypt → GitHub upload
GitHub read → plaintext state update
password migration → local commit
password migration → remote write
```

The authorization check must happen immediately before the protected side effect, not only at the beginning of the operation.

That matters because:

```text
check at start
↓
await
↓
lock
↓
side effect
```

is unsafe.

The required pattern is:

```text
check
↓
await
↓
check
↓
await
↓
check immediately before protected side effect
↓
perform side effect
```

For a remote request that has already started, do not claim the session mechanism can roll it back. Existing Stage 3 reconciliation remains responsible for remote consistency.

## 8. Final key-ownership scan

After implementation, perform a repository-wide search for:

```text
_masterKeyBytes
SecureBytes
Uint8List.fromList
requireAuthoritativeMasterKeyBytes
master-key installation
derived-key installation
```

The final code must demonstrate:

```text
SessionKeyMaterial
    → sole authoritative live MK owner

SessionKeyMaterial
    → sole authoritative live NEK owner

SessionKeyMaterial
    → sole authoritative live TEK owner

MasterKeyManager
    → no persistent second MK

DomainKeyDerivation
    → no persistent second NEK/TEK

callers
    → transient copies only

stale results
    → rejected and zeroed where possible

providers
    → never own MK/NEK/TEK
```

## 9. Final Stage 5 security invariants

Do not mark Stage 5 complete unless all are true:

```text
[ ] Unlock is transactional and rollback-safe
[ ] Authentication failure cannot leave session keys installed
[ ] Protected ProviderContainer exists only after successful session establishment
[ ] Protected MaterialApp/Navigator exists only in UNLOCKED
[ ] BOOTSTRAP/UNLOCKING treated as credential-sensitive shell
[ ] New generic crypto is denied before starting while LOCKED
[ ] Narrow authentication path is the only locked-state secret-capable exception
[ ] Every sensitive async operation is epoch/capability protected
[ ] Checks occur immediately before protected side effects
[ ] Provider disposal prevents stale provider state restoration
[ ] Feature-level async closures cannot update protected state after lock
[ ] Session N authorization cannot be accepted by Session N+1
[ ] lockSync remains synchronous
[ ] cleanup failure cannot abort key destruction
[ ] sensitive logs are removed/redacted
[ ] global FLAG_SECURE remains pending until real Android source is supplied
[ ] no arbitrary clipboard clearing
[ ] no Stage 6 envelope/AAD migration
[ ] no Stage 3 reconciliation redesign
[ ] first-run credential semantics remain explicitly approved
[ ] final repository key-ownership audit passes
[ ] full regression suite passes
```

Do not weaken these requirements to simplify implementation.

If one cannot be satisfied because of an existing architectural dependency, stop and report that dependency rather than implementing a weaker substitute.

# DEVELOPER

Here is the clean separation between **what the coding AI is proposing** and **what I found that must be resolved before implementation**.

## 1. What the AI is proposing for Stage 5

The AI's final design is essentially turning Rocen into a **real session-isolated application**.

The intended lifecycle becomes:

```text
                    OUTER SHELL
                        │
              ┌─────────┴─────────┐
              │                   │
          BOOTSTRAP            LOCKED
              │                   │
        credential setup       lock screen
              │                   │
              └─────────┬─────────┘
                        │
                    UNLOCKING
                        │
                authenticate safely
                        │
                        ▼
                  UNLOCKED SESSION
                        │
             ┌──────────┴──────────┐
             │                     │
      SessionKeyMaterial      Session ProviderContainer
       ├── MK                  ├── navigation
       ├── NEK                 ├── database
       └── TEK                 ├── todo
                              └── application UI
```

When the session locks:

```text
UNLOCKED
   ↓
lockSync()
   ↓
invalidate session authorization/epoch
   ↓
zero MK / NEK / TEK
   ↓
clean sensitive resources
   ↓
dispose ProviderContainer
   ↓
destroy protected MaterialApp/Navigator
   ↓
LOCKED
```

### Its major design decisions

**A. One authoritative key owner**

The AI wants a new `SessionKeyMaterial` to be the **only authoritative holder** of live:

```text
MK
NEK
TEK
```

`MasterKeyManager` would stop storing its own second live MK.

---

**B. Session epochs/capabilities**

Every sensitive async operation gets a session authorization tied to a specific session generation.

For example:

```text
Session 41
   ↓
start decrypt
   ↓
LOCK
   ↓
Session 42
   ↓
old decrypt finishes
   ↓
authorization invalid
   ↓
result rejected/zeroed
```

This is meant to prevent stale async operations from resurrecting secrets.

---

**C. Locked-state crypto denial**

Generic cryptographic APIs would become:

```text
LOCKED
   ↓
CryptoEngine.decrypt(...)
   ↓
reject immediately
```

before isolate/native work begins.

The only exception is a **narrow internal authentication/unlock path** that is explicitly allowed to perform authentication-related crypto while locked.

---

**D. Real application/session boundary**

Instead of merely showing a lock screen over the existing app, the protected application is actually destroyed while locked.

The AI wants:

```text
LOCKED
→ no protected MaterialApp
→ no protected Navigator
→ no protected ProviderContainer
→ no database provider
→ no todo provider
→ no navigation provider
```

After successful unlock, it creates a **fresh** session container and **fresh** application tree.

---

**E. Navigation becomes data-only**

Currently the architecture stores actual widget instances in the navigation state.

The AI wants to change that from:

```text
navigation state → QuickNoteScreen()
```

to:

```text
navigation state → CaptureModule.quickNote
```

and instantiate the widget only after unlocking.

That prevents application widgets from existing globally outside the session.

---

**F. Async provider protection**

Database/todo providers load data asynchronously.

The AI wants provider/session generation checks so something like:

```text
database load begins
↓
session locks/disposes provider
↓
load finishes
↓
result is discarded
```

instead of repopulating old plaintext state.

---

**G. Synchronous destruction**

`lockSync()` must contain no `await`.

The intended order is:

```text
mark locked
→ invalidate authorization
→ zero keys
→ clear references
→ detach cleanup callbacks
→ run cleanup safely
→ dispose ProviderContainer
→ notify
```

Cleanup failures cannot interrupt key destruction.

---

**H. Android `FLAG_SECURE`**

The AI wants screen-capture protection moved from the current Settings-level behavior to the real Android Activity/window so the entire Rocen window is protected.

---

**I. No clipboard subsystem**

It now agrees clipboard handling should remain outside Stage 5 because the current clipboard feature isn't a sensitive-text clipboard.

---

## 2. The flaws I found

The important thing is that **most of the original flaws have now been corrected by the AI**.

There are only a few remaining things I would insist on before implementation.

### Flaw #1 — The original root architecture was wrong

Initially the AI proposed:

```text
MaterialApp
   ↓
builder
   ↓
SessionGate
```

I found that this was insufficient because `RocenApp.build()` accessed `navigationProvider` **before** `MaterialApp.builder`.

That meant the supposedly protected provider could already exist while locked.

The AI has now fixed this by moving the entire protected `MaterialApp` and ProviderContainer **inside the unlocked session**.

✅ **Fixed.**

---

### Flaw #2 — Legacy crypto could still run while locked

Originally the AI only wanted:

```text
start crypto
↓
lock
↓
reject stale result
```

I pointed out that's insufficient.

You need:

```text
LOCKED
↓
crypto API called
↓
REJECT BEFORE WORK STARTS
```

The latest AI now explicitly accepts this.

✅ **Fixed in design.**

This is particularly important because the current production note/token code still uses the old:

```text
system_crypto_pin
→ CryptoEngine
```

path rather than the new MK/NEK/TEK production path.

The Stage 5 system must therefore gate the **legacy path too** without pretending Stage 5 has migrated the encryption format.

---

### Flaw #3 — Unlock could leave keys alive if session creation failed

The AI's design originally had:

```text
authenticate
↓
install keys
↓
create ProviderContainer
```

What happens if ProviderContainer creation fails?

You could end up with:

```text
keys alive
+
session not actually established
```

I added the requirement that unlock must be **transactional**:

```text
authenticate
↓
prepare
↓
create session
↓
commit UNLOCKED
```

and any failure must:

```text
rollback
→ zero keys
→ dispose container
→ invalidate epoch
→ LOCKED
```

✅ The latest design now incorporates this requirement.

---

### Flaw #4 — Bootstrap/unlock UI was incorrectly described as “non-sensitive”

I flagged this because password/PIN/mnemonic entry is obviously security-sensitive even though it's not application data.

Correct classification:

```text
protected application state
```

versus:

```text
credential-sensitive shell
```

The latter still requires:

* screen-capture protection
* cleanup
* lifecycle interruption handling
* stale-result protection
* safe logging

✅ Added to the final requirements.

---

### Flaw #5 — Provider disposal alone is insufficient

The AI correctly understands that disposing Riverpod providers removes provider-owned plaintext.

But an async feature operation can have its own closure/local variables:

```text
await decrypt()
↓
plaintext still held locally
↓
provider gets disposed
↓
async function resumes
```

So simply disposing the provider is **not enough**.

The operation itself needs session authorization/generation checks before doing something sensitive after `await`.

This applies to things like:

```text
decrypt → UI
decrypt → provider
decrypt → Hive
decrypt → sync
GitHub result → local state
password migration → persistence
```

✅ The AI now acknowledges this, but this is something I would verify extremely carefully in the actual diff.

---

### Flaw #6 — Cleanup callback could abort lock

Imagine:

```text
cleanup #1 throws
```

If the code does not isolate failures, it might never reach:

```text
cleanup #2
ProviderContainer.dispose()
notification
```

and potentially compromise the intended lock sequence.

I required:

```text
zero keys FIRST
+
each cleanup independently caught
+
disposal still happens
```

✅ Added.

---

### Flaw #7 — Potential architecture cycle

There was a period where the design effectively risked:

```text
SessionSecurityManager
    ↓
MasterKeyManager
    ↓
SessionSecurityManager
```

I proposed separating the low-level key owner:

```text
SessionKeyMaterial
```

so both managers can use it without circular ownership.

The latest design accepts this.

✅ Fixed.

---

### Flaw #8 — Credential semantics are still unresolved

This is **the biggest remaining product/security decision**.

Today Rocen's existing:

```text
system_crypto_pin
```

is a **cryptography password**, not explicitly an application login.

The proposed Stage 5 requires:

```text
LOCKED
↓
authenticate
↓
UNLOCKED
```

But what exactly authenticates the user?

There are two possibilities:

```text
A. Reuse system_crypto_pin as the application-session credential
```

or

```text
B. Create a completely separate application-session credential
```

Those are materially different security/product architectures.

I would **not let the AI silently choose A** just because it's convenient.

If you choose A, that should be explicitly recorded as a deliberate Stage 5 policy change.

If you choose B, that's much larger and likely belongs to another stage.

🔴 **Still unresolved.**

---

### Flaw #9 — Android implementation cannot be completed from the supplied archive

The AI wants:

```text
MainActivity.kt
AndroidManifest.xml
```

for `FLAG_SECURE`.

Those actual files are not present in the Stage 4 archive you supplied.

Therefore:

```text
design = ready
native implementation = blocked
```

It must not invent the missing Android structure.

🔴 **Still unresolved.**

---

### Flaw #10 — The current production code has sensitive logging

I also added a final defense-in-depth requirement that the AI didn't originally include strongly enough.

Restore/sync/error logging can potentially expose:

```text
note title
filename
exception
crypto-related information
```

A security-first application should use sanitized structured events rather than dumping sensitive object contents or raw exceptions.

🟠 **Needs implementation audit.**

---

# 3. What is actually left before coding?

At this point, I would stop redesigning the architecture.

You have two genuine blockers:

### 🔴 Blocker A — Decide the session credential

Explicitly decide:

> **Is `system_crypto_pin` going to become Rocen's application-unlock credential in Stage 5?**

That is a product/security decision, not merely a coding decision.

### 🔴 Blocker B — Supply the actual Android project files

The real:

```text
android/app/src/...
MainActivity.kt
AndroidManifest.xml
```

need to be part of the implementation snapshot before the Android half can be done and audited.

---

## 4. Everything else is now an implementation audit

Once those two blockers are resolved, I would **let the AI implement Stage 5** and then act as the adversarial reviewer.

I would inspect its actual diff for:

```text
Key ownership
Session authorization
Pre-await denial
Post-await stale-result rejection
Unlock rollback
Provider isolation
Provider disposal
Async stale-state races
UI subtree destruction
Credential cleanup
Lifecycle handling
Screen capture
Logging
Tests
```

And I would not accept “the tests pass” as sufficient.

The key question after implementation will be:

> **Can I find any execution path where a secret or protected plaintext survives the session boundary, or where stale work can re-enter a newer session?**

That is the standard I would use for Stage 5.

# IMPLEMENTOR:

Accepted. These are now **binding Stage 5 security requirements** on top of the already-accepted root architecture. I will not redesign the root architecture again.

There is one important clarification needed to make the transactional-unlock wording internally precise: the unlock transaction may temporarily hold **transaction-local prepared secret buffers**, but those are not installed into the active `SessionKeyMaterial` and cannot authorize ordinary crypto. The active session key owner remains empty until commit.

## Stage 5 final security model

```text
OUTER ProviderScope
    │
    └── RocenShell
          │
          └── SessionGate
                │
                ├── BOOTSTRAP
                │     └── credential-sensitive shell
                │
                ├── LOCKED
                │     └── credential-sensitive LockScreen
                │
                ├── UNLOCKING
                │     └── credential-sensitive authentication shell
                │
                └── UNLOCKED
                      │
                      ├── Session ProviderContainer
                      │
                      ├── UncontrolledProviderScope
                      │
                      └── protected MaterialApp
                            └── existing application
                                  └── data-only navigationProvider
```

No protected application provider or widget is created by the outer shell.

---

# 1. Transactional unlock is now a two-phase session activation

Use an internal `UnlockTransaction` with a lifecycle such as:

```text
CREATED
  ↓
AUTHENTICATING
  ↓
PREPARED
  ↓
CONTAINER_ESTABLISHING
  ↓
ROOT_ESTABLISHING
  ↓
COMMITTING
  ↓
COMMITTED
```

Any failure before `COMMITTED` goes through the same rollback path.

### Preparation

Authentication completes first.

Then:

```text
capture authorization
        ↓
async authentication
        ↓
validate authorization
        ↓
prepare candidate MK/NEK/TEK
```

The prepared buffers are:

- transaction-owned,
- not visible through `SessionKeyMaterial`,
- not usable by generic crypto APIs,
- destroyed on rollback.

Only at commit are they transferred into the authoritative `SessionKeyMaterial`.

That avoids having two authoritative owners.

---

# 2. No active session keys before commit

The active state must remain:

```text
SessionKeyMaterial:
    MK  = null
    NEK = null
    TEK = null
```

throughout the pre-commit transaction.

The transaction may contain prepared `SecureBytes`, but:

```text
generic CryptoEngine
DomainKeyDerivation
database
sync
feature code
```

cannot obtain those transaction buffers.

Only the session manager has access to the transaction capability.

At commit:

```text
transaction candidate
      ↓ ownership transfer
SessionKeyMaterial
      ↓
active session
```

No byte-for-byte second persistent copy is retained.

---

# 3. Rollback is mandatory and idempotent

Any failure after authentication success triggers:

```text
rollback()
    ↓
invalidate authorization
    ↓
increment session epoch
    ↓
zero candidate MK/NEK/TEK
    ↓
zero/clear any caller-owned temporary buffers
    ↓
dispose session ProviderContainer if created
    ↓
remove protected application root
    ↓
return to LOCKED
```

Rollback itself must be synchronous wherever destruction permits it.

It must tolerate partial construction:

```text
container == null
root == null
keys == partially prepared
```

without throwing its way out of cleanup.

This directly covers:

```text
authentication succeeds
→ key preparation succeeds
→ ProviderContainer creation fails
→ LOCKED
→ no active session keys
→ no protected provider
→ no protected application
```

---

# 4. Protected-root establishment needs a readiness boundary

The protected MaterialApp cannot simply be assigned and considered successful.

The implementation needs a controlled readiness handshake:

```text
create session container
    ↓
mount protected root
    ↓
protected root successfully establishes
    ↓
commit authorization + active keys
    ↓
UNLOCKED
```

If establishment fails:

```text
rollback
```

The root must not autonomously transition the session to unlocked.

The session manager owns the commit decision.

---

# 5. Lifecycle lock aborts an unlock transaction

This is a critical race:

```text
UNLOCKING
   ↓
authentication/key preparation/root setup
   ↓
inactive
   ↓
LOCK
```

The lifecycle handler immediately:

```text
epoch++
authorization invalidated
transaction marked stale
candidate keys destroyed
session container disposed
LOCKED
```

When the old authentication/root Future later completes:

```text
authorization invalid
    ↓
reject
    ↓
zero result where possible
    ↓
never commit
```

So the old transaction cannot establish Session N+1.

---

# 6. BOOTSTRAP and UNLOCKING are credential-sensitive shells

These states are **not** classified as harmless/non-sensitive.

They can hold:

```text
password/PIN
recovery mnemonic
authentication state
temporary secret buffers
credential controllers
authentication timers
```

Therefore the same security treatment applies:

### Capture protection

The entire Android window remains protected by global `FLAG_SECURE` once the real Android files are available.

### Lifecycle

```text
inactive/hidden/paused/detached
    ↓
invalidate credential transaction
    ↓
clean credential state
    ↓
LOCKED or BOOTSTRAP
```

`resumed` never resumes the interrupted authentication transaction.

### Cleanup

Credential controllers and timers are explicitly cleaned.

### Logging

No entered password, PIN, mnemonic, token, temporary key material, or raw authentication exception may be logged.

### Stale results

An old authentication Future cannot establish a session after interruption.

---

# 7. Generic crypto remains denied before work starts

This requirement remains absolute:

```text
LOCKED
    ↓
generic crypto entry point
    ↓
synchronous authorization check
    ↓
REJECT
```

before:

- isolate dispatch,
- native Keystore invocation,
- sensitive key reads,
- crypto preprocessing.

This applies to:

```text
encryptProcess
encryptProcessWithParams
decryptProcess
decryptProcessWithParams
hardwareUnwrap
unwrapDeviceKey
future MK/NEK/TEK operations
```

Authentication uses its narrow privileged path rather than bypassing this generic gate.

---

# 8. Authorization is capability-based

Ordinary callers cannot construct a valid session authorization token.

The model is:

```text
SessionSecurityManager
    ↓
captureAuthorization()
    ↓
opaque SessionAuthorizationToken
    ↓
authorized operation
    ↓
await
    ↓
validate(token)
```

The token is tied to the session generation.

Thus:

```text
Session N token ≠ Session N+1 token
```

Even an old Future completing after a later unlock cannot become authorized again.

---

# 9. Side-effect fencing is now mandatory

An initial authorization check is not enough.

For every sensitive asynchronous operation:

```text
check
↓
await
↓
check
↓
await
↓
check immediately before protected side effect
↓
perform side effect
```

This applies to:

```text
decrypt → provider update
decrypt → UI update
decrypt → Hive write
decrypt → GitHub upload
GitHub read → plaintext state update
password migration → local commit
password migration → remote write
```

A stale result cannot:

- update provider state,
- update protected UI,
- persist sensitive content,
- enqueue a new protected side effect,
- initiate a new protected remote request.

### Existing remote request limitation

Once a network request has actually started:

```text
request starts
↓
LOCK
↓
request completes
```

Stage 5 does not claim to undo it.

Existing Stage 3 reconciliation remains responsible for resulting persistence/remote consistency.

---

# 10. Provider disposal plus operation invalidation

Provider disposal is necessary but insufficient.

Every protected async provider gets:

```text
provider/session generation
```

or equivalent authorization.

The operation pattern is:

```text
provider starts
↓
capture generation
↓
await
↓
check provider/session is still valid
↓
accept result
```

After disposal:

```text
result
    ↓
discard
    ↓
must not update state
```

This applies to every sensitive async provider/loader, not merely the obvious database/todo providers.

At minimum the audit covers:

```text
database loads
todo loads
GitHub synchronization
password rotation
backup restore/import
note decryption
note encryption
hardware unwrap
feature-level async callbacks
timers/debounced saves
```

---

# 11. Provider boundary remains absolute

The outer shell must never instantiate:

```text
navigationProvider
localDatabaseProvider
todoProvider
gridColumnsProvider
```

and `CaptureModule` stores only identifiers/enums, never widget instances.

Thus:

```text
LOCKED
    no protected ProviderContainer
    no protected MaterialApp
    no protected Navigator
    no navigationProvider instance
    no localDatabaseProvider instance
    no todoProvider instance
    no gridColumnsProvider instance
    no globally-retained protected screen widgets
```

On unlock:

```text
new Session ProviderContainer
    ↓
protected MaterialApp
    ↓
navigationProvider
    ↓
actual screen widgets
```

On lock:

```text
protected MaterialApp removed
    ↓
ProviderContainer disposed
    ↓
provider-owned state destroyed
```

---

# 12. Async provider tests are now architectural tests

The final suite must prove:

```text
LOCKED
→ protected provider absent
```

then:

```text
UNLOCK
→ session container created
→ provider instantiated
```

then:

```text
LOCK
→ provider container disposed
→ stale load completes
→ state does not reappear
```

This is required for every sensitive async provider discovered by the audit.

---

# 13. Sensitive logging audit is a Stage 5 security task

The repository-wide logging scan must remove/redact:

```text
plaintext note contents
note titles
sensitive filenames
password/PIN
mnemonic words
tokens
crypto inputs
crypto outputs
raw exception strings containing protected data
raw stack traces where sensitive context may appear
```

The current restore/sync diagnostic logging therefore must be rewritten rather than merely disabled in release builds.

Security-sensitive logging must be safe in debug builds too.

Permitted diagnostic style:

```text
SESSION_LOCKED
SESSION_EPOCH_INVALIDATED
CRYPTO_OPERATION_REJECTED_LOCKED
RESTORE_DECRYPT_FAILED
SYNC_OPERATION_FAILED
PROVIDER_SESSION_DISPOSED
```

No direct interpolation of arbitrary protected objects.

No:

```text
"$exception"
"$fileName"
"$title"
"$response.body"
"$token"
"$mnemonic"
```

in security-sensitive logs.

And cleanup failures must not be logged with arbitrary exception contents.

---

# 14. Explicit no-secret-after-failed-unlock tests

These become mandatory:

```text
authentication succeeds
↓
session-key preparation succeeds
↓
session ProviderContainer creation fails
↓
LOCKED
↓
candidate keys zeroed
↓
active SessionKeyMaterial empty
↓
no protected provider
↓
no protected MaterialApp
```

And:

```text
authentication succeeds
↓
protected-root establishment begins
↓
lifecycle lock
↓
old authorization invalid
↓
root transaction fails/stales
↓
keys zeroed
↓
session remains LOCKED
```

---

# 15. Explicit credential interruption tests

For both BOOTSTRAP and UNLOCKING:

```text
credential entry active
↓
inactive/hidden/paused/detached
↓
credential controllers cleared
↓
credential timers cancelled
↓
authorization invalidated
↓
pending authentication becomes stale
↓
completion cannot unlock
```

There is no automatic continuation after resume.

---

# 16. Updated key-ownership verification

After implementation, perform the repository-wide scan you specified.

Search:

```text
_masterKeyBytes
SecureBytes
Uint8List.fromList
requireAuthoritativeMasterKeyBytes
master-key installation
derived-key installation
```

The final repository must demonstrate:

| Owner/locationRequirement |                                                           |
| ------------------------- | --------------------------------------------------------- |
| `SessionKeyMaterial`      | sole authoritative MK                                     |
| `SessionKeyMaterial`      | sole authoritative NEK                                    |
| `SessionKeyMaterial`      | sole authoritative TEK                                    |
| `MasterKeyManager`        | no persistent second MK                                   |
| `DomainKeyDerivation`     | no persistent second NEK/TEK                              |
| transaction object        | temporary candidate only, inaccessible to generic callers |
| callers                   | transient defensive copies                                |
| stale results             | rejected and zeroed where possible                        |
| providers                 | never own MK/NEK/TEK                                      |

The audit is code-based, not class-name-based.

---

# 17. Final mandatory Stage 5 tests

The previous matrix is now expanded to include all new requirements:

```text
lockZeroesMasterKey
lockInvalidatesSessionEpoch
lockZeroesDerivedKeys
doubleLockIsIdempotent

cryptoDeniedWhileLocked
legacyDecryptDeniedWhileLocked
legacyEncryptDeniedWhileLocked
hardwareUnwrapDeniedWhileLocked
deviceKeyUnwrapDeniedWhileLocked

staleDecryptResultRejected
staleEncryptResultRejected
staleHkdfResultRejected
staleUnlockResultRejected
staleHardwareUnwrapRejected

lockDuringAsyncLegacyDecrypt
lockDuringAsyncLegacyEncrypt
lockDuringAsyncHardwareUnwrap

lockDuringMasterKeyInitializationCannotPromote
lockDuringRecoveryCannotInstallMasterKey
lockDuringPasswordChangeDoesNotAcceptStaleSecrets

cleanupCallbackFailureDoesNotAbortLock
allCleanupCallbacksRunAfterOneFails

sessionKeyInstallationCopiesAndZeroesCallerBuffer

sessionProviderContainerDisposed
noProtectedProviderInstantiatedBeforeUnlock
protectedProviderStateDestroyedWithSession

resumeDoesNotUnlock
inactiveLocks
hiddenLocks
pausedLocks
detachedLocks

protectedUiRemoved
sensitiveControllersCleaned
credentialTransactionInterrupted

unlockRollbackOnProviderContainerFailure
unlockRollbackOnProtectedRootFailure
lockDuringUnlockTransactionCannotCommit

staleFeatureAsyncResultCannotUpdateProvider
staleFeatureAsyncResultCannotUpdateUi
staleFeatureAsyncResultCannotPersist
staleFeatureAsyncResultCannotStartProtectedRemoteSideEffect

navigationProviderDoesNotInstantiateWhileLocked
navigationStateDoesNotRetainWidgetInstances

sensitiveLoggingDoesNotExposeSecrets
```

And the cross-session invariant remains mandatory:

```text
SESSION N
    ↓
authorized sensitive operation
    ↓
LOCK
    ↓
epoch N+1
    ↓
operation completes
    ↓
result destroyed/rejected
    ↓
NEW SESSION
    ↓
old authorization still invalid
```

---

# 18. Final completion gate

Stage 5 cannot be declared complete unless every item below is demonstrated:

```text
[ ] One authoritative live key owner exists
[ ] No persistent second MK exists in MasterKeyManager
[ ] No persistent second NEK/TEK exists in DomainKeyDerivation
[ ] Unlock is transactional
[ ] Authentication success alone does not commit a session
[ ] Failed unlock establishment rolls back completely
[ ] Candidate key material is inaccessible to generic callers before commit
[ ] Locked generic crypto is denied before work starts
[ ] Narrow authentication path is the only locked-state secret-capable exception
[ ] Every sensitive async operation has capability/epoch authorization
[ ] Checks occur immediately before protected side effects
[ ] Stale results cannot mutate providers/UI/persistence/sync
[ ] Session N authorization cannot work in Session N+1
[ ] Initialization cannot promote after lock
[ ] Recovery cannot install after lock
[ ] Password-change stale secrets cannot be accepted
[ ] lockSync remains synchronous
[ ] cleanup errors cannot interrupt destruction
[ ] every cleanup callback is attempted
[ ] credential-sensitive shell is treated as security-sensitive
[ ] interrupted credential transactions cannot resume automatically
[ ] protected ProviderContainer exists only within session establishment/unlocked lifetime
[ ] protected providers are absent before unlock
[ ] protected MaterialApp/Navigator is absent while locked
[ ] navigation state contains no retained Widget instances
[ ] every sensitive async provider/load path has stale-result protection
[ ] provider disposal is verified by tests
[ ] feature-level async closures are separately fenced
[ ] sensitive logging is removed/redacted
[ ] no secret-bearing exception or response body is logged
[ ] inactive/hidden/paused/detached lock
[ ] resumed never unlocks
[ ] global FLAG_SECURE is implemented only with the real Android sources
[ ] Settings-only screenshot protection is removed
[ ] no global clipboard-clearing subsystem
[ ] no Stage 6 envelope/AAD migration
[ ] no Stage 3 reconciliation redesign
[ ] first-run credential semantics remain explicitly approved
[ ] final repository ownership scan passes
[ ] full regression suite passes
[ ] documentation makes no physical-memory-erasure guarantee
```

## Two previously known blockers remain unchanged

The requirements do **not** change these:

**Credential semantics:** `system_crypto_pin` cannot silently be redefined as the mandatory application-session credential without that policy being explicitly approved.

**Android source:** the real `MainActivity.kt` and manifest are still required before the global `FLAG_SECURE` portion can be implemented and verified.

Everything else is now part of the binding Stage 5 baseline. No smaller substitute, UI-only lock, cancellation-only approach, or hidden-provider approach satisfies this specification.

# AUDITOR:

One final internal consistency issue remains before implementation.

The current design says both:

```text
SessionKeyMaterial remains empty until COMMIT
```

and:

```text
create protected ProviderContainer
→ mount protected application root
→ commit keys/session
```

These can conflict because protected application construction may instantiate providers or application code that expects an established session.

Do not allow an intermediate state where:

```text
protected application exists
+
SessionKeyMaterial is empty
+
application is expected to function
```

## Required correction: introduce an internal ACTIVATING state

Keep the public/security-facing states:

```text
BOOTSTRAP
LOCKED
UNLOCKING
UNLOCKED
```

but add:

```text
ACTIVATING
```

as an internal session-activation state.

The intended flow is:

```text
LOCKED
    ↓
UNLOCKING
    ↓
authenticate
    ↓
prepare candidate MK/NEK/TEK
    ↓
validate authorization
    ↓
ACTIVATING
    ↓
install authoritative session key material
    ↓
create session ProviderContainer
    ↓
establish protected application root
    ↓
root successfully established
    ↓
COMMIT
    ↓
UNLOCKED
```

### Crucial rule

During `ACTIVATING`:

```text
SessionKeyMaterial may contain the session keys
```

but:

```text
generic application crypto authorization = DENIED
```

Therefore:

```text
CryptoEngine.encryptProcess()
CryptoEngine.decryptProcess()
CryptoEngine.hardwareUnwrap()
CryptoEngine.unwrapDeviceKey()
DomainKeyDerivation
ordinary feature-level crypto
```

must still reject ordinary callers while the state is `ACTIVATING`.

Only the narrow internal activation capability may access the prepared/installed session material during activation.

The distinction must therefore be:

```text
keys-present
    !=
session-authorized
```

Only the final `UNLOCKED` state grants ordinary application session authorization.

## Why this is required

It prevents these unsafe intermediate states:

```text
protected app exists
+
keys absent
```

and also:

```text
keys exist
+
generic application crypto is authorized
+
protected root has not successfully established
```

Instead:

```text
ACTIVATING
    ↓
keys available only to activation authority
    ↓
protected root establishes
    ↓
ordinary session authorization becomes valid
    ↓
UNLOCKED
```

## Rollback

Any failure anywhere in `ACTIVATING` must execute the same synchronous rollback:

```text
invalidate authorization
→ increment epoch
→ zero MK
→ zero NEK
→ zero TEK
→ clear SessionKeyMaterial
→ dispose session ProviderContainer if created
→ remove protected root
→ clean credential/session resources
→ return LOCKED
```

Rollback must be safe when any of these are only partially constructed:

```text
session keys = none / partial / installed
container = null / created
protected root = not mounted / mounting / established
```

No failure may leave:

```text
keys alive
+
generic crypto authorized
+
session not fully established
```

## Activation capability

The activation authority must be as narrow as the unlock capability.

Ordinary code must not be able to obtain an activation token merely by calling a public constructor.

Conceptually:

```text
SessionSecurityManager
    ↓
private activation capability
    ↓
install/use prepared session material
    ↓
establish protected root
    ↓
commit
```

The activation capability must be tied to the current session epoch so that:

```text
lock during ACTIVATING
→ activation authorization becomes invalid
→ old root/key operation cannot commit
```

## Final state machine

Use:

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

Interruption:

```text
UNLOCKING / ACTIVATING
    ↓
inactive / hidden / paused / detached
    ↓
LOCKED
```

Normal locking:

```text
UNLOCKED
    ↓
inactive / hidden / paused / detached / explicit lock
    ↓
LOCKED
```

Resume:

```text
LOCKED
    ↓
resumed
    ↓
LOCKED
```

No automatic restoration.

## Completion test

Add:

```text
activationStateDoesNotAuthorizeGenericCrypto
```

and:

```text
lockDuringActivationRollsBackKeysContainerAndRoot
```

Also test:

```text
candidate keys prepared
→ activation begins
→ root establishment fails
→ SessionKeyMaterial empty
→ generic crypto denied
→ protected ProviderContainer absent
→ protected application absent
→ LOCKED
```

This is the final ordering correction. Do not redesign the root architecture again after applying it; implement and audit the concrete Stage 5 code against the resulting invariants.

# IMPLEMENTOR

Yes. **Your analysis is correct**, and I would adopt `ACTIVATING` as the final Stage 5 state. The previous design had a real ordering conflict.

There is one refinement I would add: **“protected root successfully established” must be an explicit activation acknowledgment, not merely the act of constructing a** **`Widget`** **or calling** **`setState`****.** That matters for the transactional rollback requirement.

## Final state machine

Keep the external states:

```text
BOOTSTRAP
LOCKED
UNLOCKING
UNLOCKED
```

and add the internal state:

```text
ACTIVATING
```

The final transition model is:

```text
BOOTSTRAP
    ↓
LOCKED
    ↓
UNLOCKING
    ↓
authentication
    ↓
prepare candidate key material
    ↓
validate authorization
    ↓
ACTIVATING
    ↓
install MK/NEK/TEK into SessionKeyMaterial
    ↓
create session ProviderContainer
    ↓
mount protected application root
    ↓
activation readiness acknowledged
    ↓
COMMIT
    ↓
UNLOCKED
```

Interruption from either transitional state:

```text
UNLOCKING / ACTIVATING
    ↓
inactive / hidden / paused / detached / explicit lock
    ↓
rollback
    ↓
LOCKED
```

And:

```text
LOCKED
    ↓
resumed
    ↓
LOCKED
```

No automatic restoration.

---

# The critical distinction

The final security model is:

```text
keys-present
        ≠
session-authorized
        ≠
session-committed
```

During `ACTIVATING`:

```text
SessionKeyMaterial
    MK  = present
    NEK = present
    TEK = present
```

but:

```text
generic application crypto = DENIED
ordinary session authorization = INVALID
session = NOT COMMITTED
```

Only the internal activation capability can use the newly installed session material.

Therefore this remains forbidden during `ACTIVATING`:

```text
CryptoEngine.encryptProcess()
CryptoEngine.decryptProcess()
CryptoEngine.hardwareUnwrap()
CryptoEngine.unwrapDeviceKey()
DomainKeyDerivation
ordinary feature-level protected operations
```

They all require ordinary session authorization, which exists only after `UNLOCKED`.

---

# Why installing keys before root establishment is now safe

The apparent contradiction disappears:

```text
ACTIVATING
    │
    ├── SessionKeyMaterial contains keys
    │
    ├── ProviderContainer exists
    │
    ├── protected root is being established
    │
    └── ordinary crypto authorization = DENIED
```

So we never have:

```text
protected app
+
no keys
+
app expects usable crypto
```

and we also never have:

```text
keys
+
generic crypto authorization
+
session not fully established
```

Instead:

```text
ACTIVATING
    ↓
keys available only to activation authority
    ↓
root establishment
    ↓
activation acknowledgment
    ↓
ordinary authorization enabled
    ↓
UNLOCKED
```

That is exactly the security distinction the previous design was missing.

---

# Ownership during activation

There must still be no duplicate authoritative key copies.

The safe transfer is:

```text
UNLOCKING

transaction-local candidate MK
transaction-local candidate NEK
transaction-local candidate TEK

        ↓ validate authorization

ACTIVATING

SessionKeyMaterial owns:
    MK
    NEK
    TEK

transaction candidate references cleared
candidate buffers zeroed
```

Therefore:

```text
SessionKeyMaterial
    → sole authoritative live owner

UnlockTransaction
    → no longer owns installed material
```

Before transfer, the candidate belongs to the transaction.

After transfer, the candidate is destroyed and only `SessionKeyMaterial` owns the authoritative buffers.

---

# Activation capability

I agree with your requirement here.

The activation capability should be:

```text
opaque
non-forgeable
epoch-bound
session-bound
```

Conceptually:

```text
SessionSecurityManager
        ↓
private ActivationCapability
        ↓
SessionKeyMaterial access
        ↓
activation-only operations
```

Ordinary application code cannot construct one.

It must also become invalid when:

```text
epoch changes
```

So:

```text
SESSION N
    ↓
ACTIVATING
    ↓
LOCK
    ↓
epoch N+1
    ↓
old ActivationCapability invalid
```

An old activation continuation therefore cannot commit.

---

# One important implementation refinement: root readiness

This is the only part of your proposal I would sharpen.

Do **not** define:

```text
create protected MaterialApp
    =
activation succeeded
```

Widget construction alone is not a sufficient transactional acknowledgment.

Instead use an explicit activation barrier:

```text
ACTIVATING
    ↓
create Session ProviderContainer
    ↓
mount activation-aware protected root
    ↓
root performs required activation-time initialization
    ↓
root signals READY
    ↓
SessionSecurityManager validates activation capability
    ↓
COMMIT → UNLOCKED
```

The protected root should be designed so that its activation phase does not perform arbitrary ordinary protected side effects.

In particular, descendant application code must not be allowed to say:

```text
"we are mounted, therefore we are unlocked"
```

The authoritative answer remains:

```text
SessionSecurityManager.state == UNLOCKED
```

and ordinary APIs reject otherwise.

This makes `ACTIVATING` a genuine transaction phase rather than merely a label.

---

# What happens to providers during ACTIVATING

The session ProviderContainer may exist during `ACTIVATING`.

That is acceptable because the requirement is:

```text
LOCKED
    → no protected ProviderContainer
```

not:

```text
ACTIVATING
    → no ProviderContainer
```

However, providers must not mistake container existence for session authorization.

For example:

```text
ProviderContainer exists
+
DatabaseNotifier exists
```

does **not** imply:

```text
ordinary crypto permitted
```

Any provider operation that performs a protected side effect must have valid session authorization.

Async provider initialization must also retain the generation/capability check.

---

# Rollback becomes more important with ACTIVATING

The rollback path now explicitly handles partial construction:

```text
rollback()
    1. mark session non-authorized
    2. invalidate epoch/capability
    3. zero MK
    4. zero NEK
    5. zero TEK
    6. clear SessionKeyMaterial
    7. invalidate activation transaction
    8. remove protected root
    9. dispose Session ProviderContainer
   10. clean credential-sensitive resources
   11. return LOCKED
```

It must tolerate:

```text
keys:        none / partial / installed
container:   null / created
root:        not mounted / mounting / ready
```

and must never leave:

```text
keys alive
+
generic crypto authorized
+
LOCKED/ACTIVATING
```

---

# The two tests you proposed are mandatory

Add:

```text
activationStateDoesNotAuthorizeGenericCrypto
```

which proves that even with:

```text
ACTIVATING
SessionKeyMaterial = populated
```

a normal crypto call is rejected before it starts.

And:

```text
lockDuringActivationRollsBackKeysContainerAndRoot
```

which proves:

```text
ACTIVATING
    ↓
LOCK
    ↓
epoch invalidated
    ↓
keys zeroed
    ↓
container disposed
    ↓
root removed
    ↓
LOCKED
```

Then explicitly test the root-failure case:

```text
candidate keys prepared
    ↓
ACTIVATING
    ↓
keys installed
    ↓
session container created
    ↓
root activation fails
    ↓
rollback
    ↓
SessionKeyMaterial empty
    ↓
generic crypto denied
    ↓
no session ProviderContainer
    ↓
no protected MaterialApp
    ↓
LOCKED
```

---

# Final invariant set

I would now consider these the final Stage 5 invariants:

```text
[ ] LOCKED has no protected ProviderContainer
[ ] LOCKED has no protected MaterialApp/Navigator
[ ] LOCKED has no ordinary session authorization
[ ] LOCKED rejects generic crypto before work starts

[ ] UNLOCKING has no protected application
[ ] UNLOCKING has no active session key ownership
[ ] credential transaction is epoch/capability protected

[ ] ACTIVATING may contain MK/NEK/TEK
[ ] ACTIVATING may contain the session ProviderContainer
[ ] ACTIVATING may mount the protected root
[ ] ACTIVATING does NOT authorize ordinary application crypto
[ ] only activation capability can access activation-time session material
[ ] activation capability cannot be forged
[ ] activation capability is epoch-bound

[ ] root activation has an explicit readiness acknowledgment
[ ] ordinary session authorization is created only at COMMIT
[ ] COMMIT is the only transition to UNLOCKED

[ ] any activation failure performs complete rollback
[ ] lifecycle interruption invalidates activation
[ ] stale activation cannot commit
[ ] Session N authorization cannot work in Session N+1

[ ] UNLOCKED is the only ordinary protected-application authorization state
[ ] resumed never restores a previous session
```

## Verdict

**I agree with your proposed** **`ACTIVATING`** **correction.** It fixes a real internal inconsistency in the previous design.

The only adjustment I would make is to define activation success through an **explicit root-readiness/activation acknowledgment**, rather than treating widget construction itself as proof that the protected application has successfully established.

With that refinement, I would treat the Stage 5 architecture as **internally consistent and implementation-ready**, subject only to the already-known external blockers: the explicit application-session credential semantics and the missing real Android Activity/manifest.

# AUDITOR: FINAL AUDIT

Begin implementing **Stage 5** now.

The Stage 5 security architecture is frozen. **Do not redesign the root architecture again, do not simplify the security requirements, and do not substitute weaker mechanisms merely to reduce implementation complexity.**

Use the actual Stage 4 codebase as the source of truth, not assumptions from the architecture document.

## 0. Implementation discipline

Before changing code:

1. Inspect the actual current repository structure and relevant implementations.
2. Confirm every proposed file change exists and understand its current responsibilities.
3. Do not invent missing Android source files.
4. Do not silently change product/security semantics.
5. Keep Stage 5 strictly scoped to the session-security boundary.
6. Preserve existing Stage 3 behavior and existing encryption formats unless a Stage 5 requirement explicitly requires an API/lifecycle change.
7. After implementation, perform a repository-wide security audit against every invariant below.

If a requirement conflicts with the actual code, **stop at that point and report the exact architectural dependency instead of weakening the requirement.**

---

# 1. Frozen Stage 5 state machine

Use:

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

Lifecycle interruption:

```text
UNLOCKING / ACTIVATING / UNLOCKED
    ↓
inactive / hidden / paused / detached
    ↓
LOCK / ROLLBACK
    ↓
LOCKED
```

Resume:

```text
LOCKED
    ↓
resumed
    ↓
LOCKED
```

There is **never automatic unlock or session restoration on resume**.

`ACTIVATING` is mandatory.

The critical distinction is:

```text
keys-present
    ≠
ordinary session-authorized
    ≠
session-committed
```

---

# 2. SessionKeyMaterial

Create:

```text
lib/core/session_key_material.dart
```

This must be the sole authoritative live owner of:

```text
MK
NEK
TEK
```

using `SecureBytes` or the strongest existing secure buffer abstraction compatible with the project.

There must be no second persistent authoritative MK/NEK/TEK owner.

`MasterKeyManager` must not retain a second live MK buffer.

`DomainKeyDerivation` must not retain a second authoritative NEK/TEK buffer.

Any public operational return value must be a defensive/transient copy where required.

Never expose mutable authoritative buffers directly.

---

# 3. SessionSecurityManager

Create:

```text
lib/core/session_security_manager.dart
```

It owns:

* session state
* session epoch/generation
* session authorization
* activation capability
* lock/unlock lifecycle
* synchronous destruction
* rollback
* sensitive cleanup registry
* session ProviderContainer lifetime
* transactional unlock coordination

There must be one authoritative session-security state machine.

Do not create competing locked/unlocked state authorities.

---

# 4. Session authorization must be non-forgeable

Create an opaque, epoch-bound authorization capability.

Conceptually:

```text
SessionSecurityManager
    ↓
captureAuthorization()
    ↓
opaque SessionAuthorizationToken
```

Ordinary application code must not be able to manufacture a valid token.

The token must be bound to:

```text
session generation
+
authorization identity/capability
```

Therefore:

```text
Session N token
    !=
Session N+1 token
```

Old operations must remain invalid even after a new session is established.

Do not use a publicly constructible token such as:

```text
SessionToken(42)
```

as the security mechanism.

---

# 5. Activation capability

Create a separate narrow activation capability.

During:

```text
ACTIVATING
```

session keys may already be installed into `SessionKeyMaterial`, but:

```text
ordinary application authorization = DENIED
```

Only the internal activation capability may perform activation-specific operations.

The activation capability must be:

```text
opaque
non-forgeable
epoch-bound
session-bound
```

A lifecycle lock must invalidate it immediately.

---

# 6. Transactional unlock

Implement unlock as a true transaction.

Conceptually:

```text
LOCKED
    ↓
UNLOCKING
    ↓
authenticate
    ↓
prepare candidate MK/NEK/TEK
    ↓
validate authorization
    ↓
ACTIVATING
    ↓
install authoritative session material
    ↓
create Session ProviderContainer
    ↓
mount protected application root
    ↓
receive explicit activation readiness acknowledgment
    ↓
validate activation capability
    ↓
COMMIT
    ↓
UNLOCKED
```

Do NOT treat widget construction or `setState()` as activation success.

The protected root must explicitly acknowledge readiness.

Only the session-security manager can perform the final transition to `UNLOCKED`.

---

# 7. Unlock rollback

Any failure after authentication and before final commit must completely roll back.

Rollback must handle partial states such as:

```text
no keys
partial keys
all keys installed

container not created
container created

root not mounted
root mounting
root ready
```

Rollback:

```text
invalidate authorization
↓
increment epoch
↓
zero MK
↓
zero NEK
↓
zero TEK
↓
clear SessionKeyMaterial
↓
invalidate activation transaction
↓
remove protected root
↓
dispose session ProviderContainer
↓
clean credential-sensitive resources
↓
LOCKED
```

No failure may leave:

```text
keys alive
+
generic crypto authorization enabled
+
session not fully established
```

Rollback must be idempotent and failure-resistant.

---

# 8. lockSync()

The normal lock/destruction operation must contain no `await`.

Required ordering:

```text
lockSync()
    1. mark session unauthorized/LOCKED
    2. invalidate current epoch/capability
    3. synchronously zero MK
    4. synchronously zero NEK
    5. synchronously zero TEK
    6. clear SessionKeyMaterial references
    7. invalidate/detach current transaction
    8. detach cleanup registry
    9. detach session ProviderContainer reference
   10. run every cleanup callback independently
       catch without exposing sensitive exception contents
   11. dispose session ProviderContainer
   12. remove/replace protected root
   13. notify listeners independently
```

A cleanup callback failure must never prevent:

* key destruction
* epoch invalidation
* other cleanup callbacks
* ProviderContainer disposal
* final locked state

Do not log raw cleanup exceptions.

---

# 9. Generic crypto must be denied BEFORE work starts while locked

These APIs must synchronously reject while:

```text
LOCKED
```

and also reject for ordinary callers while:

```text
ACTIVATING
```

before any:

* sensitive key read
* crypto preprocessing
* isolate dispatch
* native Keystore invocation

At minimum audit:

```text
encryptProcess
encryptProcessWithParams
decryptProcess
decryptProcessWithParams
hardwareUnwrap
unwrapDeviceKey
future MK/NEK/TEK operations
```

Required pattern:

```text
obtain valid ordinary session authorization
↓
reject immediately if not UNLOCKED
↓
capture authorization
↓
start async work
↓
await
↓
validate authorization
↓
accept result or securely reject it
```

---

# 10. Narrow authentication exception

Authentication/unlock is the only intentional exception to the locked-state generic crypto denial.

Do NOT simply exempt a broad method like:

```text
hardwareUnwrap()
```

from the lock.

Instead provide a narrow internal authentication path.

For example conceptually:

```text
SessionSecurityManager
    ↓
private unlock authentication path
    ↓
verification
    ↓
epoch validation
    ↓
authentication result / prepared session material
```

The existing hardware-bound authentication behavior must be preserved through a narrow privileged path rather than by weakening the generic crypto gate.

Ordinary callers cannot obtain the privileged capability.

---

# 11. Every sensitive async operation gets epoch/capability fencing

The basic rule is:

```text
check
↓
await
↓
check
↓
await
↓
check immediately before protected side effect
↓
perform side effect
```

This applies to:

```text
decrypt → provider state
decrypt → UI
decrypt → Hive/local persistence
decrypt → GitHub upload
GitHub read → plaintext state
password change → local commit
password change → remote write
database load → provider state
todo load → provider state
backup restore/import → protected state
hardware unwrap → caller
```

Do not rely solely on a check at the beginning.

A check at the beginning followed by an `await` is insufficient.

---

# 12. Stale-result handling

If authorization becomes stale:

```text
destroy mutable returned secret material where possible
↓
reject
↓
never install
↓
never persist
↓
never sync
↓
never update protected UI/state
```

Do not convert temporary decrypted bytes into immutable `String` plaintext until the epoch/capability validity has been checked.

Preferred:

```text
Uint8List plaintext
        ↓
authorization check
       ↙ ↘
   stale   current
     ↓        ↓
   zero    process
   reject
```

Immutable strings cannot be reliably zeroed, so minimize their lifetime.

---

# 13. MasterKeyManager migration

Refactor the current:

```text
MasterKeyManager._masterKeyBytes
```

so it no longer maintains a second persistent authoritative live MK.

It can remain responsible for:

* authority/state rules
* provisional generation
* initialization
* promotion
* recovery orchestration

but actual live key ownership belongs to:

```text
SessionKeyMaterial
```

Protect all async initialization with session authorization.

The current flow involving:

```text
fetch
→ provisional MK
→ async publish
→ promotion
```

must become authorization/epoch-aware.

The promotion API itself must require valid authorization.

---

# 14. Initialization race

Test and implement:

```text
initialization starts
↓
provisional MK exists
↓
await publish/remote operation
↓
LOCK
↓
epoch invalidated
↓
provisional MK destroyed
↓
old operation completes
↓
promotion MUST fail
```

A stale initialization Future must never promote or install a key.

Also ensure a new session does not accidentally join an invalidated initialization Future from the previous session.

The in-flight handle should be associated with the specific operation/session generation.

---

# 15. Recovery race

Test:

```text
recovery starts
↓
await unwrap
↓
LOCK
↓
epoch changes
↓
unwrap completes
↓
returned MK zeroed/rejected
↓
MK NOT installed
```

Recovery installation itself must require valid current authorization.

---

# 16. DomainKeyDerivation

Make HKDF/session derivation authorization-aware:

```text
capture authorization
↓
obtain authoritative MK
↓
await HKDF
↓
validate authorization
↓
install authoritative NEK/TEK
↓
return only transient defensive copy if required
```

No persistent second NEK/TEK owner may remain in `DomainKeyDerivation`.

---

# 17. PasswordKeyDerivation

Add epoch/capability protection around:

```text
password unwrap
recovery unwrap
password change
```

Do not change the existing cryptographic protocol or parameters as part of Stage 5.

Do not redesign Stage 3 reconciliation.

Password-change operations must validate authorization before accepting secret results and before new protected persistence/remote side effects.

Do not claim epochs provide transaction rollback for already-started remote requests.

---

# 18. Actual legacy production CryptoEngine path

The Stage 4 production app still uses the legacy:

```text
system_crypto_pin
    ↓
CryptoEngine
```

path for current note/token operations.

Do NOT silently migrate the encryption format in Stage 5.

But DO enforce the Stage 5 session boundary around this legacy path.

While LOCKED:

```text
legacy encrypt/decrypt/unwrap
→ reject before async work begins
```

While UNLOCKED:

```text
capture authorization
→ perform operation
→ validate authorization after await
```

This is session hardening, not a ciphertext-format migration.

Do not claim Stage 5 has converted existing note/token storage to MK/NEK/TEK encryption.

---

# 19. Sensitive plaintext before String conversion

For decrypt operations, do not do:

```text
decrypt bytes
↓
String
↓
epoch check
```

Do:

```text
decrypt bytes
↓
epoch/capability validation
↓
only then decode/process plaintext
```

If stale, zero returned mutable bytes before rejection where possible.

Apply the same principle to native/hardware unwrap results.

---

# 20. Provider architecture

The final application structure must be:

```text
OUTER ProviderScope
    │
    └── RocenShell
          │
          └── SessionGate
                │
                ├── BOOTSTRAP
                │     └── credential-sensitive shell
                │
                ├── LOCKED
                │     └── credential-sensitive LockScreen
                │
                ├── UNLOCKING
                │     └── credential-sensitive authentication shell
                │
                └── ACTIVATING
                      │
                      └── activation-only protected construction
                                │
                                └── session ProviderContainer

UNLOCKED
    │
    └── session ProviderContainer
          │
          └── UncontrolledProviderScope
                │
                └── protected MaterialApp
```

Important:

```text
LOCKED
→ no protected ProviderContainer
→ no protected MaterialApp
→ no protected Navigator
→ no protected providers
```

`ACTIVATING` may temporarily have the session ProviderContainer and protected root, but ordinary session authorization remains denied.

---

# 21. Outer shell restrictions

The outer shell may only access deliberately non-sensitive state.

At minimum:

```text
themeProvider
```

may remain outside.

These must NOT be accessed by the outer shell:

```text
navigationProvider
localDatabaseProvider
todoProvider
gridColumnsProvider
```

The outer application must not accidentally initialize protected providers during:

* startup
* splash
* bootstrap
* authentication
* lifecycle handling
* lock screen
* error handling

---

# 22. ProviderContainer ownership

Create the session `ProviderContainer` only as part of session establishment.

Expose it with:

```text
UncontrolledProviderScope
```

and explicitly dispose it during rollback/lock.

No other component owns disposal.

Session N's ProviderContainer must never be reused for Session N+1.

---

# 23. Navigation refactor

Change the current navigation state from retaining actual Widget instances to data-only identifiers.

Instead of:

```text
CaptureModule.quickNote → QuickNoteScreen()
```

use:

```text
CaptureModule.quickNote
```

and construct the actual widget only in the protected application.

Do this for all modules.

This prevents globally retained application widgets from existing outside the session.

---

# 24. Theme provider refactor

Because `navbar.dart` currently obtains theme state through `main.dart`, move:

```text
ThemeNotifier
themeProvider
```

to an appropriate independent file such as:

```text
lib/core/app_theme.dart
```

This avoids making feature widgets depend on the application composition root and supports the new session boundary cleanly.

---

# 25. Async provider invalidation

Audit every sensitive async provider.

At minimum:

```text
DatabaseNotifier
TodoNotifier
```

Provider pattern:

```text
provider operation starts
↓
capture session/provider generation
↓
await
↓
verify provider/session still valid
↓
accept result
```

After disposal:

```text
result
↓
discard
```

It must not repopulate provider state.

Test the actual asynchronous race with controlled Futures/Completers.

Do not merely test that the LockScreen is visible.

---

# 26. Feature-level async audit

Provider disposal is NOT sufficient.

Audit feature-level closures and async methods in:

```text
QuickNote
Settings
IdeaInbox
Bookmarks
Clipboard
GitHub synchronization
backup/restore
password operations
```

Any operation holding sensitive state across an `await` must prevent stale post-lock use.

No stale operation may:

```text
update UI
update provider state
persist protected data
enqueue protected work
initiate a new protected remote side effect
```

For an already-started remote request, do not claim Stage 5 can roll it back.

---

# 27. Credential-sensitive shell

`BOOTSTRAP` and `UNLOCKING` are credential-sensitive.

Treat them as security-sensitive for:

* screenshot protection
* lifecycle interruption
* timer cleanup
* controller cleanup
* logging
* stale-result rejection

An interrupted credential transaction must not automatically resume after `resumed`.

---

# 28. Lifecycle

Use `AppLifecycleListener` at the outer session-security boundary.

Lock on:

```text
inactive
hidden
paused
detached
```

`resumed`:

```text
do nothing
```

Never automatically recreate:

```text
MK
NEK
TEK
ProviderContainer
Navigator
decrypted application state
```

after resume.

Flutter lifecycle delivery limitations must be documented honestly. Do not claim that every abnormal termination will always trigger a lifecycle callback.

---

# 29. Sensitive cleanup registry

Implement a synchronous registry for sensitive resources that are not reliably covered by normal widget disposal.

Examples:

```text
PIN controllers
mnemonic controllers
token controllers
temporary timers
temporary credential resources
```

Normal StatefulWidget `dispose()` must remain intact.

The registry is additional emergency lock-time cleanup, not the key-storage system.

---

# 30. Sensitive logging audit

Perform a repository-wide logging audit.

Remove or redact logging of:

```text
plaintext note content
note titles
sensitive filenames
password/PIN
mnemonic/recovery words
tokens
crypto inputs
crypto outputs
secret-bearing exception contents
sensitive response bodies
sensitive stack traces
```

Use structured non-sensitive events instead, e.g.:

```text
SESSION_LOCKED
SESSION_EPOCH_INVALIDATED
CRYPTO_OPERATION_REJECTED_LOCKED
RESTORE_DECRYPT_FAILED
SYNC_OPERATION_FAILED
PROVIDER_SESSION_DISPOSED
```

Do not interpolate arbitrary exceptions or protected objects.

This applies to security-sensitive logging in debug builds too.

---

# 31. Android screen capture

The real Android source must be inspected before making native changes.

When the actual Android project exists, implement global window-level:

```text
FLAG_SECURE
```

in the real Activity.

Remove the existing Settings-only screenshot protection path.

Do not invent:

```text
MainActivity.kt
AndroidManifest.xml
```

if they are absent.

Do not claim native protection has been implemented until the real files are available and verified.

Do not treat screenshot detection as a substitute for `FLAG_SECURE`.

Do not claim `FLAG_SECURE` defeats every possible capture method.

---

# 32. Clipboard

Clipboard remains OUT OF SCOPE for Stage 5.

Do not add:

```text
global clipboard manager
global clipboard clearing
arbitrary clipboard deletion
```

The current media-oriented clipboard feature should remain unchanged unless required for an unrelated Stage 5 regression.

Future sensitive text-copy functionality gets its own security treatment.

---

# 33. Credential semantics

Do NOT silently redefine:

```text
system_crypto_pin
```

as the application's mandatory login credential unless that policy has been explicitly approved.

The current Stage 4 semantics identify it as the cryptography password.

Before implementing the production first-run/authentication UX that depends on its meaning, verify the intended credential policy.

Do not silently invent a second application credential either.

If this policy is still unresolved in the implementation environment, implement the session-security framework so the authentication mechanism is abstracted cleanly, but do not silently make the product decision yourself.

Fresh installations must never dead-end.

---

# 34. Scope restrictions

Stage 5 must NOT introduce:

```text
AES-GCM migration
AAD redesign
envelope v2
ciphertext format migration
key rotation protocol
hardware-backed MK wrapping redesign
Recovery-KEK redesign
Stage 3 reconciliation redesign
GitHub sync protocol redesign
```

Those belong to their designated stages.

Stage 5 is:

> session security, lifecycle, authorization, secret lifetime, UI/provider lifetime, capture protection, and associated defensive testing.

---

# 35. Mandatory tests

Implement the complete Stage 5 test matrix.

### Session destruction

```text
lockZeroesMasterKey
lockInvalidatesSessionEpoch
lockZeroesDerivedKeys
doubleLockIsIdempotent
```

### Locked-state denial

```text
cryptoDeniedWhileLocked
legacyDecryptDeniedWhileLocked
legacyEncryptDeniedWhileLocked
hardwareUnwrapDeniedWhileLocked
deviceKeyUnwrapDeniedWhileLocked
```

These must verify the underlying isolate/native backend was NOT started.

### Activation denial

```text
activationStateDoesNotAuthorizeGenericCrypto
```

### Stale results

```text
staleDecryptResultRejected
staleEncryptResultRejected
staleHkdfResultRejected
staleUnlockResultRejected
staleHardwareUnwrapRejected
```

### Races

```text
lockDuringAsyncLegacyDecrypt
lockDuringAsyncLegacyEncrypt
lockDuringAsyncHardwareUnwrap

lockDuringMasterKeyInitializationCannotPromote
lockDuringRecoveryCannotInstallMasterKey
lockDuringPasswordChangeDoesNotAcceptStaleSecrets

lockDuringActivationRollsBackKeysContainerAndRoot
```

### Transaction rollback

```text
unlockRollbackOnProviderContainerFailure
unlockRollbackOnProtectedRootFailure
```

### Cleanup failure

```text
cleanupCallbackFailureDoesNotAbortLock
allCleanupCallbacksRunAfterOneFails
```

### Ownership

```text
sessionKeyInstallationCopiesAndZeroesCallerBuffer
noSecondPersistentMasterKeyInMasterKeyManager
```

### Providers

```text
sessionProviderContainerDisposed
noProtectedProviderInstantiatedBeforeUnlock
protectedProviderStateDestroyedWithSession
staleProviderLoadCannotRestoreState
```

### UI/navigation

```text
protectedUiRemoved
navigationStateDoesNotRetainWidgetInstances
sensitiveControllersCleaned
dialogsRemovedOnLock
navigationStateDiscardedOnLock
```

### Credentials

```text
credentialTransactionInterrupted
staleCredentialResultCannotUnlock
```

### Lifecycle

```text
resumeDoesNotUnlock
inactiveLocks
hiddenLocks
pausedLocks
detachedLocks
```

### Sensitive feature operations

```text
staleFeatureAsyncResultCannotUpdateProvider
staleFeatureAsyncResultCannotUpdateUi
staleFeatureAsyncResultCannotPersist
staleFeatureAsyncResultCannotStartProtectedRemoteSideEffect
```

### Logging

```text
sensitiveLoggingDoesNotExposeSecrets
```

### Activation

```text
activationStateDoesNotAuthorizeGenericCrypto
lockDuringActivationRollsBackKeysContainerAndRoot
```

---

# 36. Repository-wide verification after implementation

After coding, perform an actual repository-wide audit.

Search for:

```text
_masterKeyBytes
SecureBytes
Uint8List.fromList
requireAuthoritativeMasterKeyBytes
master-key installation
derived-key installation
navigationProvider
CaptureModule
ProviderScope
ProviderContainer
CryptoEngine
hardwareUnwrap
unwrapDeviceKey
system_crypto_pin
logger / debugPrint / print
```

Produce a final ownership/security report.

Expected key ownership:

```text
SessionKeyMaterial
    → sole authoritative MK owner

SessionKeyMaterial
    → sole authoritative NEK owner

SessionKeyMaterial
    → sole authoritative TEK owner

MasterKeyManager
    → no second persistent MK owner

DomainKeyDerivation
    → no second persistent NEK/TEK owner

UnlockTransaction
    → temporary candidate ownership only

providers
    → never own MK/NEK/TEK
```

Expected provider boundary:

```text
LOCKED
    → protected providers absent

UNLOCKED
    → protected providers exist only in session container

LOCK
    → session container disposed
```

Expected navigation boundary:

```text
navigation state
    → data only
    → no retained Widget instances
```

---

# 37. Validation commands

Run the project's actual validation commands after implementation.

At minimum, where supported by the actual environment:

```text
flutter analyze
flutter test
flutter test --coverage
```

Also run any project-specific:

```text
dart format
lint/static-analysis commands
Android tests
integration tests
```

Do not claim a command passed unless it was actually run.

If Flutter/Dart is unavailable in the environment, report that clearly rather than claiming validation.

---

# 38. Final implementation report

After implementation, report:

### Files changed

Exact files.

### Security changes

What each change enforces.

### Tests

Exact commands actually executed and results.

### Remaining blockers

Anything genuinely unresolved.

### Security exceptions

Any place where the current platform/runtime prevents a stronger guarantee.

### Repository ownership audit

Confirm whether the single-owner invariant was actually demonstrated.

### Stage 5 completion status

Use exactly one:

```text
STAGE 5 COMPLETE
```

or:

```text
STAGE 5 BLOCKED
```

Do not declare completion if any mandatory security invariant or mandatory test remains unresolved.

Most importantly:

**Do not optimize for minimal code changes. Optimize for preserving the frozen security invariants in the real implementation.**

# IMPLEMENTOR:

I started the Stage 5 implementation audit against the actual Stage 4 snapshot, and I have to stop before changing production behavior. There are **two implementation-blocking dependencies** that make the frozen Stage 5 invariants impossible to satisfy cleanly with the current code.

### Blocker 1 — the actual production app has no persisted MK unwrap path

The repository-wide search shows:

```text
PasswordKeyDerivation
    → only referenced by its own implementation/tests

DomainKeyDerivation
    → only referenced by its own implementation/tests

MasterKeyManager
    → only its own implementation/tests

production note/token flows
    → still read system_crypto_pin
    → call CryptoEngine
```

The current production code therefore has no path equivalent to:

```text
stored Password-KEK/recovery wrapper
    ↓
unwrap authoritative MK
    ↓
derive NEK/TEK
    ↓
install SessionKeyMaterial
```

The Stage 4 key hierarchy exists as isolated infrastructure, but it has **not been integrated into the actual data/authentication flows**.

That creates a direct contradiction with the new mandatory unlock transaction:

```text
UNLOCKING
    ↓
authenticate
    ↓
prepare MK/NEK/TEK
```

For an existing installation, the current application has `system_crypto_pin`, but that is the legacy cryptographic credential/hash. It does not give Stage 5 a legitimate way to recover the authoritative dataset MK.

I cannot solve this by:

```text
generate a new MK
```

because it would not be the dataset's authoritative MK.

I cannot solve it by:

```text
persist/recover the MK using a new format
```

because that would be Stage 6/earlier protocol integration.

I cannot solve it by:

```text
leave SessionKeyMaterial empty
```

because that violates your mandatory transactional-unlock requirement.

I also cannot solve it by:

```text
use a synthetic/session-only MK
```

because that would falsely represent the session hierarchy and create two different cryptographic authorities.

So this is a genuine architectural dependency:

> **The actual Stage 4 codebase cannot currently perform the required production unlock transaction that prepares the authoritative MK/NEK/TEK without introducing the later cryptographic integration that Stage 5 is explicitly forbidden to smuggle in.**

### Blocker 2 — the real Android source is absent

The supplied Stage 4 archive contains only a partial Android project and no:

```text
android/app/src/.../MainActivity.kt
android/app/src/main/AndroidManifest.xml
```

so I cannot implement or verify the global `FLAG_SECURE` requirement without inventing native source files. That remains explicitly prohibited.

---

## There is also a credential-semantics dependency

The actual application currently treats:

```text
system_crypto_pin
```

as the **cryptographic access password**, including optional setup and change flows. It is not currently implemented as a mandatory application-session authentication credential.

The frozen Stage 5 design requires a real:

```text
BOOTSTRAP
→ LOCKED
→ UNLOCKING
→ ACTIVATING
→ UNLOCKED
```

session-authentication flow.

Making the existing optional cryptography password the mandatory application unlock credential would therefore be a product/security semantic decision, not merely an implementation detail.

I will not silently make that decision.

---

## What I did **not** do

I did **not** add a weaker `SessionSecurityManager` that merely hides the UI.

I did **not** gate legacy `CryptoEngine` calls in a way that would leave the application permanently unusable because no valid session could ever be established.

I did **not** generate a fake/session-only MK.

I did **not** migrate the legacy ciphertext format.

I did **not** invent Android files.

Those would make the code look like Stage 5 was implemented while violating the actual frozen invariants.

## Current status

```text
STAGE 5 BLOCKED
```

The blockers are concrete and codebase-specific:

```text
1. Production has no authoritative MK recovery/load path,
   so the required transactional unlock cannot prepare MK/NEK/TEK
   without pulling later cryptographic integration into Stage 5.

2. Real Android Activity/manifest sources are absent,
   so FLAG_SECURE cannot be implemented honestly.

3. The mandatory application-session credential semantics
   have not been explicitly established for the current
   optional system_crypto_pin.
```

I have **not modified production code** because doing so before resolving the first blocker would require violating at least one of your mandatory Stage 5 constraints.

# AUDITOR: PROBLEM FOUND

Stop Stage 5 production implementation for now.

The decision to block is correct. The actual Stage 4 implementation snapshot does not contain a production path that can recover the authoritative Master Key required by the frozen Stage 5 unlock transaction.

Do NOT weaken Stage 5 and do NOT invent a workaround.

Instead, perform a **Stage Dependency Integrity Audit** before any production code is changed.

# 1. Objective

Determine exactly which previously designed stage is incomplete in the actual implementation and what minimum prerequisite work must be completed before Stage 5 can begin.

The question is:

> What exact already-approved cryptographic integration is missing between the existing Master-Key/KEK/HKDF infrastructure and the real production note/token authentication/data flows?

Do not redesign the cryptographic architecture.

# 2. Confirm the current implementation gap

Document the actual current chain:

```text
system_crypto_pin
    ↓
legacy CryptoEngine
    ↓
notes/tokens
```

and compare it with the intended architecture:

```text
application password
    ↓
Password-KEK
    ↓
wrapped authoritative MK
    ↓
MK
    ↓
NEK / TEK
    ↓
application data
```

Also document recovery:

```text
password + mnemonic
    ↓
Recovery-KEK
    ↓
wrapped same authoritative MK
    ↓
MK
```

Confirm exactly which links exist in production and which exist only as unused infrastructure/tests.

# 3. Explicitly verify device_key.json semantics

Inspect the actual code and confirm exactly what the current `device_key.json` contains.

Do not assume it contains an MK.

The current implementation appears to use:

```text
device_key.json
    ↓
wrapped authSalt
```

rather than:

```text
device_key.json
    ↓
wrapped MK
```

Document the exact fields, inputs, and outputs.

Do not change its meaning during this audit.

# 4. Inventory production callers

Perform a repository-wide inventory of actual production callers for:

```text
MasterKeyManager
PasswordKeyDerivation
DomainKeyDerivation
CryptoEngine
system_crypto_pin
wrapDeviceKey
unwrapDeviceKey
wrapMasterKeyWithPassword
unwrapMasterKeyWithPassword
wrapMasterKeyWithRecovery
unwrapMasterKeyWithRecovery
```

Separate the results into:

```text
production callers
test-only callers
dead/unused infrastructure
```

Do not treat a class existing as proof that the stage is implemented.

# 5. Determine the missing prerequisite stage

Using the existing security architecture and stage definitions, identify which stage owns the missing production integration.

Do NOT create a new cryptographic protocol merely to make Stage 5 possible.

Prefer:

```text
existing stage was architecturally designed
but production wiring is incomplete
```

over:

```text
invent a new Stage 5 mechanism
```

If the correct conclusion is that the Master-Key production integration belongs to an earlier stage, explicitly state:

```text
CURRENT IMPLEMENTATION STATUS:
Stage X architecture = designed
Stage X production wiring = incomplete
Stage 5 dependency = therefore unsatisfied
```

# 6. Determine the minimum required prerequisite work

Produce an exact list of the smallest required prerequisite components.

For example, investigate whether the existing architecture already specifies:

```text
password-wrapped MK artifact
recovery-wrapped MK artifact
local/remote storage location
password setup integration
recovery integration
first-device initialization
joining-device recovery
password-change rewrap
```

For each, state:

```text
already implemented
partially implemented
missing
incorrectly implemented
```

Do not implement any of them yet.

# 7. Do NOT pull Stage 6 into this

Do not solve the dependency by introducing:

```text
envelope v2
AAD changes
ciphertext migration
note re-encryption
new data format
new key version protocol
```

unless the existing stage architecture explicitly says a prerequisite belongs there.

Stage 5 must remain:

```text
session lifecycle
session authorization
key lifetime
UI/provider lifetime
lifecycle locking
capture protection
```

The purpose of this audit is to determine whether the earlier MK integration is incomplete—not to move Stage 6 forward.

# 8. Do NOT fake a Stage 5 unlock

Do NOT implement:

```text
synthetic MK
session-only MK
new random MK at unlock
pin-derived fake MK
new temporary device key
```

Those are explicitly prohibited because they would not represent the authoritative dataset Master Key.

# 9. Do NOT migrate the legacy production ciphertext yet

The current production path:

```text
system_crypto_pin
    ↓
CryptoEngine
```

must remain unchanged during this dependency audit.

Do not silently convert existing notes/tokens to a different encryption hierarchy.

# 10. Credential semantics

Also document the current meaning of:

```text
system_crypto_pin
```

and separate:

```text
cryptography credential
```

from:

```text
application-session authentication credential
```

Do not silently redefine it.

The purpose of this audit is to identify the dependency, not make the product decision.

# 11. State exact blockers

Return a precise blocker table:

| Dependency                       | Current status | Owning stage | Required before Stage 5? | Reason |
| -------------------------------- | -------------- | ------------ | ------------------------ | ------ |
| Authoritative MK production load | ...            | ...          | Yes/No                   | ...    |
| Password-wrapped MK              | ...            | ...          | ...                      | ...    |
| Recovery-wrapped MK              | ...            | ...          | ...                      | ...    |
| First-device MK establishment    | ...            | ...          | ...                      | ...    |
| Cross-device MK recovery         | ...            | ...          | ...                      | ...    |
| Session credential semantics     | ...            | policy       | ...                      | ...    |
| Android Activity/Manifest        | missing        | Stage 5      | yes for native portion   | ...    |

# 12. Android dependency

Separately confirm:

```text
android/app/src/.../MainActivity.kt
android/app/src/main/AndroidManifest.xml
```

are absent from the supplied implementation snapshot.

Do not fabricate them.

Treat this independently from the cryptographic dependency.

# 13. Deliverables

Return:

### A. Current implementation map

```text
ARCHITECTURE
vs
ACTUAL CODE
```

### B. Exact missing Master-Key production path

Show the intended path and where the current implementation stops.

### C. Owning stage

Identify which already-designed stage should be completed before Stage 5.

### D. Minimum prerequisite implementation plan

List the exact files/components that would need to change later.

Do not implement them now.

### E. Stage 5 readiness condition

State exactly what must become true before Stage 5 can begin.

The readiness condition should be something equivalent to:

```text
authoritative dataset MK can be legitimately established/recovered
without generating a replacement key
and without introducing a new unapproved protocol
```

plus the existing Android source requirement.

# 14. Final status

Use:

```text
STAGE 5 BLOCKED — PREREQUISITE IMPLEMENTATION GAP
```

Do not declare Stage 5 implementation started.

Do not modify production code during this audit.

The goal is to restore the intended stage dependency order before implementation, not to weaken the frozen Stage 5 security model.

# IMPLEMENTOR

I performed the Stage Dependency Integrity Audit against the materialized Stage 4 snapshot and the previously approved architecture artifacts. **No production code was modified.**

# STAGE 5 BLOCKED — PREREQUISITE IMPLEMENTATION GAP

The audit confirms that the blocking dependency is **the production wiring of the already-designed Stage 3 Master-Key/KEK system**. Stage 4's HKDF infrastructure exists, but its production use is intentionally deferred until the later data cutover.

There is also a separate Stage 5 native-source blocker: the supplied Android tree still lacks the real Activity/manifest.

---

# A. Current implementation map

## Architecture vs actual code

### Intended architecture

The approved architecture specifies:

```text
application password
    ↓
Password Verifier          ← authentication only
    +
Password-KEK
    ↓
wrapped authoritative MK
    ↓
MK
    ↓
HKDF
 ┌──┴──┐
NEK   TEK
 ↓     ↓
notes GitHub token
```

and recovery:

```text
password + mnemonic
    ↓
Recovery-KEK
    ↓
Recovery-wrapped same MK
    ↓
MK
```

The architecture explicitly says MK is generated once, never derived from the password, and survives password changes/device additions. It specifies Password-KEK and Recovery-KEK wraps as the persisted forms of the MK.

The detailed storage model specifies the Password-KEK-wrapped MK in `rocen_settings_box` and the Recovery-KEK-wrapped MK in `device_key.json` on GitHub.

### Actual production path

The real application remains:

```text
system_crypto_pin
    ↓
CryptoEngine.encryptProcess/decryptProcess
    ↓
encrypted notes / GitHub credentials
```

The approved architecture's own earlier audit description confirms that the current implementation passes the stored `system_crypto_pin`-derived value directly into the legacy crypto path. It also identifies the current recovery path as wrapping the `authSalt` extracted from `system_crypto_pin`, not an MK.

The actual snapshot confirms this in code: the current password-setup flow hashes the entered password with `CryptoEngine.hashPin()` and stores the result as `system_crypto_pin`; no Master-Key creation or Password-KEK wrapping occurs there.

---

# B. Exact missing Master-Key production path

The current code has the **pieces**, but they are disconnected.

## 1. MasterKeyManager

`MasterKeyManager` really does generate and hold a 32-byte provisional/authoritative MK and has the initialization race machinery. It also has the state-gated authoritative accessor.

It also has:

```text
initializeOrRecoverMasterKey()
generateProvisionalMasterKey()
promoteProvisionalToAuthoritative()
setAuthoritativeMasterKeyFromRecovery()
```

but those are **not called by the real application flows**.

The production repository search found `MasterKeyManager` only in its own implementation and `DomainKeyDerivation`; there is no production feature/root caller that establishes the actual dataset key.

So this exists:

```text
MasterKeyManager
    ↓
authoritative MK capability
```

but not:

```text
real user setup/recovery
    ↓
MasterKeyManager
```

That is a production integration gap.

---

## 2. PasswordKeyDerivation

Stage 3's cryptographic primitive is implemented.

It contains:

```text
createPasswordVerifier()
verifyPassword()

wrapMasterKeyWithPassword()
unwrapMasterKeyWithPassword()

wrapMasterKeyWithRecovery()
unwrapMasterKeyWithRecovery()
```

and the implementation explicitly describes these as wrapping/unwrapping an existing MK rather than deriving one from a password.

But production callers are absent.

The repository inventory shows:

```text
PasswordKeyDerivation
    → core/password_key_derivation.dart
    → tests
    → NO production feature caller
```

So this is not a missing cryptographic primitive. It is **unwired Stage 3 production infrastructure**.

---

## 3. DomainKeyDerivation

Stage 4 HKDF is implemented and tested.

It currently obtains the authoritative MK through `MasterKeyManager`.

But the repository inventory shows:

```text
DomainKeyDerivation
    → implementation
    → tests
    → NO production note/token caller
```

This is not itself the blocking earlier-stage defect.

The approved stage order intentionally leaves actual note/token format/key migration for the later production cutover. Stage 5 does not need to migrate those ciphertexts.

Once Stage 3 production MK establishment exists, Stage 5 can use the already-built Stage 4 HKDF primitive to populate session NEK/TEK without introducing new cryptography.

---

# C. `device_key.json` reality check

This is the most important concrete mismatch.

## Actual current `device_key.json`

The current implementation writes:

```json
{
  "wrapSalt": "...",
  "wrapNonce": "...",
  "wrappedAuthSalt": "..."
}
```

The legacy `CryptoEngine.wrapDeviceKeyWithParams()` encrypts the **authentication salt**, not an MK. The corresponding `unwrapDeviceKey()` returns that authentication salt.

The production recovery flow then does:

```text
device_key.json
    ↓
unwrapDeviceKey(...)
    ↓
authSalt
    ↓
hashPinWithSalt(rawPassword, authSalt)
    ↓
system_crypto_pin
```

The actual recovery code shows that sequence: `unwrapDeviceKey()` returns a value, which is then used as the salt for `hashPinWithSalt()`, and the resulting hash is stored as `system_crypto_pin`. It does **not** install an authoritative MK.

So the actual current chain is:

```text
password + mnemonic
    ↓
Recovery-like legacy wrapper
    ↓
authSalt
    ↓
reconstruct system_crypto_pin
```

not:

```text
password + mnemonic
    ↓
Recovery-KEK
    ↓
wrapped MK
    ↓
MK
```

This is exactly why Stage 5 cannot currently perform the frozen transactional unlock.

---

# D. Production-caller inventory

| Component/APIProduction callersTest-only callersStatus |                                                            |                                     |                                                  |
| ------------------------------------------------------ | ---------------------------------------------------------- | ----------------------------------- | ------------------------------------------------ |
| `MasterKeyManager`                                     | `DomainKeyDerivation` only                                 | `master_key_manager_test.dart`      | **Not wired into user flows**                    |
| `PasswordKeyDerivation`                                | None                                                       | `password_key_derivation_test.dart` | **Infrastructure only**                          |
| `DomainKeyDerivation`                                  | None                                                       | `domain_key_derivation_test.dart`   | **Infrastructure only**                          |
| `CryptoEngine`                                         | settings, QuickNote, database, password-state/backup paths | crypto tests                        | **Actual production crypto path**                |
| `system_crypto_pin`                                    | Settings + QuickNote and related production flows          | tests                               | **Still authoritative legacy crypto credential** |
| `wrapDeviceKey`                                        | Settings/password-state recovery flows                     | tests                               | **Production, but wraps authSalt**               |
| `unwrapDeviceKey`                                      | Settings recovery flow                                     | tests                               | **Production, but recovers authSalt**            |
| `wrapMasterKeyWithPassword`                            | None                                                       | password-KDF tests                  | **Unused production infrastructure**             |
| `unwrapMasterKeyWithPassword`                          | None                                                       | password-KDF tests                  | **Unused production infrastructure**             |
| `wrapMasterKeyWithRecovery`                            | None                                                       | password-KDF tests                  | **Unused production infrastructure**             |
| `unwrapMasterKeyWithRecovery`                          | None                                                       | password-KDF tests                  | **Unused production infrastructure**             |

The Stage 3 change diff is particularly revealing: it added `password_key_derivation.dart` and its tests, but did not touch `settings.dart`, `database.dart`, or `password_state_manager.dart` to connect the new MK wrapping system to production.

So the correct interpretation is:

> **Stage 3 cryptographic infrastructure was implemented, but Stage 3 production integration was not completed.**

---

# E. Stage 3 password-change implementation is also incomplete

There is another important finding.

The intended architecture says password change must:

```text
same MK
    ↓
new Password-KEK wrap
    +
new Recovery-KEK wrap
    +
new verifier
```

and explicitly says existing notes should not be re-encrypted.

But the current `PasswordKeyDerivation.changePassword()` implementation only accepts the existing Password-KEK wrapper and returns a new Password-KEK wrapper plus verifier. It does not accept or refresh the Recovery-KEK wrapper.

Meanwhile the real production Settings password-change flow still:

```text
old system_crypto_pin
    ↓
derive new system_crypto_pin
    ↓
migrateEncryptedNotes(...)
    ↓
re-encrypt every encrypted note
```

and separately rewraps the legacy `device_key.json` auth-salt artifact. That is legacy behavior, not the approved MK architecture.

Therefore Stage 3 is not merely “not wired.” **Its production integration is missing, and one part of the Stage 3 helper API itself is incomplete relative to the approved recovery-wrapper refresh design.**

---

# F. Exact missing prerequisite components

The minimum prerequisite is **not a new stage** and not a new cryptographic protocol.

It is completion of the already-designed **Stage 3 production integration**.

| ComponentCurrent statusOwning stageRequired before Stage 5?Why |                                                                                                         |                          |                             |                                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------ | --------------------------- | ------------------------------------------------------------- |
| Authoritative MK production load                               | **Missing**                                                                                             | Stage 3                  | **Yes**                     | Stage 5 unlock needs the real dataset MK                      |
| Password-wrapped MK                                            | **Implemented/tested, not persisted in production**                                                     | Stage 3                  | **Yes**                     | Existing device unlock needs legitimate MK recovery           |
| Recovery-wrapped MK                                            | **Implemented/tested, not used by production**                                                          | Stage 3                  | **Yes**                     | New-device recovery must recover the same MK                  |
| First-device MK establishment                                  | **Manager helper exists; no production caller**                                                         | Stage 3                  | **Yes**                     | First device must establish the one authoritative MK          |
| Cross-device MK recovery                                       | **Library exists; production recovers authSalt instead**                                                | Stage 3                  | **Yes**                     | Joining device currently cannot obtain MK                     |
| Local Password-KEK wrapper storage                             | **Missing**                                                                                             | Stage 3                  | **Yes**                     | Need a legitimate persistent local unlock artifact            |
| Remote Recovery-KEK wrapper storage                            | **Missing in approved format**                                                                          | Stage 3                  | **Yes**                     | `device_key.json` currently has the wrong payload             |
| Password verifier separation                                   | **Partially implemented as library; legacy production still uses** **`system_crypto_pin`** **directly** | Stage 3                  | **Yes**                     | Verifier must not be data-key material                        |
| Password-change MK rewrap                                      | **Library partial; production still re-encrypts notes**                                                 | Stage 3                  | **Yes**                     | Must preserve same MK and avoid ciphertext migration          |
| Recovery-wrapper refresh during password change                | **Missing**                                                                                             | Stage 3                  | **Yes**                     | Required by approved password-change architecture             |
| HKDF primitive                                                 | **Implemented/tested**                                                                                  | Stage 4                  | No additional prerequisite  | Stage 5 can use it once MK exists                             |
| Production note/token cutover to MK/NEK/TEK                    | **Missing by design**                                                                                   | Stage 6                  | **No**                      | Must not be pulled into Stage 5                               |
| Session credential semantics                                   | **Policy unresolved**                                                                                   | Stage 5/product decision | **Yes for final unlock UX** | `system_crypto_pin` must not silently gain new global meaning |
| Real Android Activity/Manifest                                 | **Missing from supplied snapshot**                                                                      | Stage 5                  | **Yes for native portion**  | Cannot honestly implement `FLAG_SECURE`                       |

---

# G. Minimum prerequisite implementation plan

This is the smallest already-designed Stage 3 production work I would expect.

### 1. Establish the first-device authoritative MK

During the existing first-time setup:

```text
secure password
    ↓
generate MK once
    ↓
Password-KEK-wrap MK
    ↓
Recovery-KEK-wrap same MK using password + mnemonic
    ↓
persist local Password-KEK wrapper
    ↓
publish Recovery-KEK wrapper as device_key.json
    ↓
only then mark MK authoritative
```

The existing `MasterKeyManager` should remain the authority state machine. Its current production abstraction around conditional initialization is already present.

The production adapter must build the **Recovery-wrapped MK**, not the old auth-salt structure.

### 2. Define the production local wrapper location

The approved detailed storage model specifies:

```text
rocen_settings_box
    → Password-KEK-wrapped MK
```

and

```text
GitHub device_key.json
    → Recovery-KEK-wrapped MK
```

The wrap envelope already contains its salt/KDF metadata, so this does not require a new crypto format.

### 3. Change `device_key.json` payload meaning

The existing legacy fields:

```text
wrapSalt
wrapNonce
wrappedAuthSalt
```

must eventually be replaced by the already-existing Stage 3 wrap envelope produced by `PasswordKeyDerivation.wrapMasterKeyWithRecovery()`.

This is **Stage 3 production integration**, not Stage 6 note-envelope migration.

### 4. Implement joining-device recovery

Production recovery becomes:

```text
fetch device_key.json
    ↓
parse Recovery-KEK wrapper
    ↓
password + mnemonic
    ↓
unwrap same MK
    ↓
install authoritative MK
    ↓
create local Password-KEK wrapper
```

The current flow that reconstructs `system_crypto_pin` from a recovered authSalt is then replaced by this Stage 3 path.

### 5. Complete password-change rewrap

Production password change should eventually become:

```text
old Password-KEK wrapper
    ↓
unwrap same MK
    ↓
new Password-KEK wrapper
    +
new Recovery-KEK wrapper
    +
new verifier
```

without calling:

```text
migrateEncryptedNotes()
```

The existing Stage 3 architecture explicitly assigns this responsibility to the password-wrapper layer rather than note migration.

The existing `PendingReason` / reconciliation system can continue handling the remote device-key/password-state consistency; that is not something I would redesign in this audit.

### 6. Keep Stage 4 as-is

Once production MK establishment exists:

```text
authoritative MK
    ↓
existing DomainKeyDerivation
    ↓
NEK / TEK
```

No new HKDF design is needed.

The actual encrypted note/token format remains untouched until its designated later stage.

---

# H. What does **not** belong in this prerequisite

These should remain untouched:

```text
AES-GCM envelope v2
AAD changes
keyVersion migration
note ciphertext migration
note-title encryption
actual note/token cutover
hardware MK wrapping
StrongBox/TEE architecture
session lifecycle
session ProviderContainer
FLAG_SECURE
```

In particular, **do not use Stage 6 as a reason to change the current ciphertext format now**.

The dependency is much narrower:

> Stage 3 must make the authoritative MK legitimately recoverable in production using the already-designed Password-KEK and Recovery-KEK wrappers.

---

# I. Credential semantics

The current `system_crypto_pin` has two roles in the real application:

```text
password verification representation
+
effective cryptographic input for legacy note/token encryption
```

That is exactly the coupling the approved architecture was designed to eliminate.

The approved architecture instead separates:

```text
Password Verifier
    → authentication only

Password-KEK
    → unwraps MK

Recovery-KEK
    → unwraps same MK
```

The architecture document explicitly describes the verifier as comparison-only and says the new verifier may reuse the `system_crypto_pin` name or use a successor key, but that naming is a deliberate decision.

So the audit result is:

```text
system_crypto_pin
    current meaning:
        legacy cryptography credential / verifier

application-session credential
    current status:
        NOT yet formally defined
```

I am not redefining it.

That remains a **separate Stage 5 product/security-policy dependency**, not something to solve by guessing.

---

# J. Android dependency

I separately inspected the supplied Stage 4 archive.

It contains the Flutter/Dart project files but **does not contain the real Android Activity/manifest source tree needed to implement the native window protection**.

Therefore these remain unavailable in the supplied implementation snapshot:

```text
android/app/src/.../MainActivity.kt
android/app/src/main/AndroidManifest.xml
```

No native file should be fabricated.

This does not change the cryptographic dependency; it is an independent Stage 5 blocker.

---

# K. Stage 5 readiness condition

Stage 5 becomes legitimately startable when all of the following are true:

```text
[ ] First-device setup generates exactly one authoritative MK
[ ] MK is never derived from the password
[ ] local Password-KEK-wrapped MK exists in production
[ ] Recovery-KEK-wrapped same MK exists in production
[ ] production device_key.json contains the Recovery-wrapped MK,
    not an authSalt wrapper
[ ] joining/new-device recovery returns the same authoritative MK
[ ] password verifier is not used as data-key material
[ ] password change re-wraps the same MK
[ ] recovery wrapper refresh is part of that Stage 3 flow
[ ] existing Stage 3 pending/reconciliation behavior remains intact
[ ] no replacement/synthetic/session-only MK is introduced
[ ] Stage 4 HKDF implementation remains available for session derivation
[ ] no Stage 6 ciphertext migration is required to establish the session MK
[ ] application-session credential semantics are explicitly defined
[ ] real Android Activity + manifest are available for FLAG_SECURE
```

The key condition is:

```text
authoritative dataset MK
    can be legitimately established/recovered
    using the already-approved Password-KEK/Recovery-KEK design
    without generating a replacement key
    and without inventing a new protocol
```

Once that is true, the frozen Stage 5 transaction:

```text
authentication
→ prepare MK/NEK/TEK
→ ACTIVATING
→ protected container/root
→ commit
```

has a legitimate cryptographic foundation.

---

## Final dependency conclusion

```text
CURRENT IMPLEMENTATION STATUS

Stage 3 architecture
    = designed

Stage 3 cryptographic primitives
    = implemented and tested

Stage 3 production wiring
    = INCOMPLETE

Actual production device_key.json
    = legacy authSalt wrapper
    ≠ Recovery-KEK-wrapped MK

Production authoritative MK load
    = MISSING

Stage 4 HKDF infrastructure
    = implemented and tested
    = correctly not yet used by legacy note/token flows

Stage 6 production cutover
    = intentionally not done
    = must remain out of this prerequisite work

Stage 5 dependency
    = UNSATISFIED
```

The Stage 3 diff itself supports this diagnosis: the production integration files were not part of that Stage 3 change set; the change consisted of the new password-KDF implementation and its tests.

Therefore the correct dependency order is:

```text
COMPLETE STAGE 3 PRODUCTION MK INTEGRATION
        ↓
verify first-device + recovery + password-rewrap flows
        ↓
retain Stage 4 HKDF as the existing primitive
        ↓
BEGIN STAGE 5
        ↓
later Stage 6 production crypto cutover
```

**No Stage 5 production implementation was started or modified during this audit.**

### Status

```text
STAGE 5 BLOCKED — PREREQUISITE IMPLEMENTATION GAP
```

The missing prerequisite is **Stage 3 production integration of the authoritative MK and its Password-KEK/Recovery-KEK wrappers**, plus the separately required real Android source for the native Stage 5 portion. 

Admin: I also send you the latest zip of all files and folders.

# AUDITOR

Before any production code is changed, produce a **FINAL Stage 3 Production Integration Design** based on:

1. the actual latest project snapshot (`files.zip`) as the source of truth for implementation,
2. the previously approved security architecture/stage documentation,
3. the Stage 3 cryptographic primitives that already exist in the repository.

**Do not modify any production code.**

Do not implement Stage 3 yet.

Do not implement Stage 5.

Do not redesign the cryptographic primitives unless you discover an actual contradiction that makes the approved architecture impossible.

The purpose of this task is to produce the final security-reviewed design for wiring the existing Stage 3 MK/KEK infrastructure into the real production application.

---

# Core objective

The design must establish one authoritative dataset Master Key:

```text
MK
```

with the approved model:

```text
Password Verifier
    → authentication only

Password-KEK
    → wraps the authoritative MK

Recovery-KEK
    → wraps the same authoritative MK

MK
    ↓
existing Stage 4 HKDF
    ├── NEK
    └── TEK
```

The design must NOT derive MK from the password.

The design must NOT create a replacement MK during recovery.

The design must NOT introduce a synthetic/session-only MK.

The design must NOT migrate note/token ciphertext formats.

The design must NOT pull Stage 5 session-lifecycle implementation into Stage 3.

---

# 1. First-device MK establishment

Define the exact first-device sequence.

Answer precisely:

```text
fresh installation
    ↓
user establishes cryptography credential
    ↓
generate random MK
    ↓
generate required password/recovery parameters
    ↓
create Password-KEK wrapper
    ↓
create Recovery-KEK wrapper
    ↓
persist required local state
    ↓
publish required remote recovery state
    ↓
when/how does MK become authoritative?
```

Specify:

* what random material is generated,
* where it is held temporarily,
* who owns each buffer,
* how it is zeroed,
* what state machine controls provisional vs authoritative state,
* what exact condition permits promotion to authoritative,
* whether the current `MasterKeyManager` is reused directly,
* which existing APIs are used,
* what new production adapters would be required.

Do not invent new cryptographic primitives if existing Stage 3 primitives already provide the required operation.

---

# 2. Local Password-KEK wrapper persistence

Define exactly how the Password-KEK-wrapped MK is stored locally.

The approved architecture currently describes:

```text
rocen_settings_box
    ↓
Password-KEK-wrapped MK
```

Determine from the actual codebase:

* exact Hive box,
* exact key/name,
* serialization format,
* versioning requirements,
* whether the existing wrapper envelope is sufficient,
* how corruption is detected,
* how absence is distinguished from corruption,
* how successful load recovers the authoritative MK.

Do NOT silently invent another persistence location or another cryptographic format.

Describe:

```text
missing
valid
corrupt
tampered
unsupported-version
```

as distinct states.

---

# 3. Remote Recovery-KEK wrapper persistence

Define exactly how the Recovery-KEK-wrapped MK is represented remotely.

The approved architecture currently expects:

```text
GitHub
    ↓
device_key.json
    ↓
Recovery-KEK-wrapped same MK
```

Determine:

* exact JSON structure,
* exact use of the existing `PasswordKeyDerivation.wrapMasterKeyWithRecovery()` output,
* whether an explicit format/version field already exists,
* what metadata is required,
* whether the existing `device_key.json` location remains unchanged,
* how integrity/authenticity is validated,
* what is considered malformed vs unsupported vs tampered.

Important:

The current implementation's `device_key.json` wraps `authSalt`, not MK.

Document the old schema and the new approved schema separately.

Do not overwrite the meaning of the old schema implicitly.

---

# 4. Joining-device recovery

Define the complete new-device/repository-join flow.

Desired conceptual path:

```text
download remote Recovery wrapper
        ↓
validate structure/version/integrity
        ↓
user supplies password + recovery mnemonic
        ↓
derive Recovery-KEK
        ↓
unwrap SAME authoritative MK
        ↓
validate recovered MK
        ↓
install as authoritative local MK
        ↓
create local Password-KEK wrapper
        ↓
establish required local state
```

Answer:

* what happens if the password is wrong,
* what happens if the mnemonic is wrong,
* what happens if both are wrong,
* how wrapper tampering is detected,
* how malformed JSON is handled,
* how an old legacy `device_key.json` is recognized,
* whether legacy recovery remains supported,
* whether legacy recovery is migration-assisted or explicitly unsupported,
* exactly when recovered MK becomes authoritative locally.

Never generate a replacement MK if the recovery wrapper decrypts incorrectly.

Recovery must recover the same dataset MK.

---

# 5. Password-change rewrap

Design the production password-change flow using the same MK.

Required conceptual behavior:

```text
old password
    ↓
unwrap existing MK with old Password-KEK
    ↓
new Password-KEK wrapper over SAME MK
    +
new Recovery-KEK wrapper over SAME MK
    +
new password verifier
```

The design must explicitly confirm:

```text
MK_before == MK_after
```

The password change must NOT:

```text
generate new MK
re-encrypt every existing note
change existing note ciphertext
change NEK/TEK because password changed
```

unless a previously approved architecture explicitly requires it.

The current production code reportedly calls note migration/re-encryption during password changes.

Identify exactly where that behavior must be removed/replaced when Stage 3 production integration is implemented.

Do not modify it yet.

---

# 6. Crash-safe local/remote commit choreography

This section is mandatory and must be detailed.

Local Hive and GitHub cannot be one atomic transaction.

Design the crash-safe state machine for cases such as:

### Case A

```text
MK generated
↓
local wrapper write succeeds
↓
app crashes
↓
remote wrapper was never published
```

### Case B

```text
remote wrapper published
↓
local wrapper write fails
```

### Case C

```text
remote wrapper published
↓
app crashes
↓
local finalization state not recorded
```

### Case D

```text
local wrapper committed
↓
remote publish partially succeeds/fails
```

### Case E

```text
password change
↓
new local wrapper created
↓
remote update fails
```

### Case F

```text
remote update succeeds
↓
local queue/state update fails
```

For every case define:

```text
current durable state
↓
what the app knows after restart
↓
what MUST happen next
↓
what state is provisional
↓
what state is authoritative
↓
whether retry is safe
↓
whether operation is idempotent
↓
whether existing Stage 3 pending/reconciliation mechanisms are reused
```

Do not claim local+remote atomicity.

Explicitly distinguish:

```text
cryptographic correctness
```

from:

```text
distributed persistence consistency
```

---

# 7. Existing legacy `device_key.json` compatibility

Perform a concrete compatibility analysis.

Current legacy structure is approximately:

```text
device_key.json
    ↓
wrapSalt
wrapNonce
wrappedAuthSalt
```

and its production meaning is:

```text
wrapped authentication salt
    ↓
recover authSalt
    ↓
reconstruct system_crypto_pin
```

The new architecture requires:

```text
device_key.json
    ↓
Recovery-KEK-wrapped SAME MK
```

Design explicit behavior for:

```text
legacy file
new file
missing file
malformed file
unsupported version
tampered file
valid new file
```

Do NOT silently interpret an old authSalt wrapper as an MK wrapper.

Do NOT silently replace the legacy file without defining migration semantics.

Answer whether the production system will:

```text
support legacy recovery
```

or:

```text
require an explicit one-time migration
```

or:

```text
declare legacy repositories unsupported and require controlled upgrade
```

and explain why.

The decision must be explicit before implementation.

---

# 8. Tampered / malformed wrapper handling

Define exact validation stages for both local and remote wrappers.

Separate:

```text
missing
malformed
unsupported-version
invalid encoding
invalid KDF parameters
authentication/tag failure
wrong password
wrong mnemonic
truncated ciphertext
unexpected fields
duplicate/conflicting fields
```

Where appropriate, normalize externally visible failure behavior so attackers cannot use error details to distinguish sensitive states unnecessarily.

Do not log:

* raw wrapper contents,
* passwords,
* mnemonic words,
* keys,
* decrypted MK,
* raw sensitive exception contents.

Define whether failures are:

```text
recoverable
retryable
fatal for the current device/session
```

---

# 9. Exact point where MK becomes authoritative

This must be unambiguous.

Define:

### Provisional

```text
candidate MK exists
```

but:

```text
not yet authoritative
```

### Authoritative

Specify the exact event/transaction boundary where the system commits:

```text
this MK is THE dataset MK
```

Also define:

```text
what persisted artifacts must exist first?
what remote artifacts must exist first?
what local state marker proves authority?
what happens if the process crashes before promotion?
what happens if the process crashes immediately after promotion?
```

The existing `MasterKeyManager` provisional/promote behavior must be incorporated rather than bypassed.

There must be no state in which two different MKs can both plausibly be treated as the dataset's authoritative key.

---

# 10. What happens after EVERY partial failure

Produce a failure-state matrix.

At minimum cover:

```text
MK generation failure
Password-KEK derivation failure
Recovery-KEK derivation failure
local serialization failure
local Hive write failure
remote JSON serialization failure
GitHub upload failure
GitHub timeout
GitHub authentication failure
GitHub conflict
GitHub repository already contains legacy device_key.json
GitHub repository contains new device_key.json for a different MK
process crash before local commit
process crash after local commit
process crash before remote commit
process crash after remote commit
password-change local failure
password-change remote failure
device recovery failure
malformed recovery wrapper
tampered recovery wrapper
wrong password
wrong mnemonic
```

For every state answer:

```text
Does the MK remain provisional?
Does the MK remain authoritative?
Is retry safe?
What gets deleted/retained?
What gets zeroed?
What gets re-read from durable storage?
What does the next app startup do?
```

Do not leave any “implementation detail” here that could change the security semantics.

---

# 11. Current legacy `system_crypto_pin`

Document the exact current production role of:

```text
system_crypto_pin
```

Separate its current roles:

```text
authentication/verifier
+
legacy cryptographic input
```

from the intended architecture:

```text
Password Verifier
+
Password-KEK
+
authoritative MK
```

Do not silently redefine `system_crypto_pin`.

Identify the exact production code that currently:

```text
sets it
reads it
changes it
uses it for encryption
uses it for decryption
uses it during recovery
```

Then state which calls belong to:

```text
Stage 3 prerequisite integration
```

and which must remain until the later production crypto cutover stage.

---

# 12. Exact boundary with Stage 4

Stage 4 already provides HKDF/domain derivation infrastructure.

Define exactly how the Stage 3 production MK becomes input to that existing Stage 4 infrastructure.

The intended dependency is:

```text
authoritative MK
    ↓
existing DomainKeyDerivation
    ↓
NEK
TEK
```

Do not redesign HKDF.

Do not change derivation parameters.

Do not migrate note/token ciphertext.

Simply identify the integration point.

---

# 13. Exact boundary with Stage 5

Stage 5 must be able to consume the prerequisite result:

```text
legitimately established/recovered authoritative MK
```

but Stage 3 must NOT implement Stage 5 session lifecycle.

Therefore Stage 3 must NOT introduce:

```text
SessionSecurityManager
Session ProviderContainer
lifecycle locking
FLAG_SECURE
ACTIVATING
session epochs
```

Instead document the interface that Stage 5 will consume.

For example conceptually:

```text
load/establish authoritative MK
    ↓
Stage 5 session manager
    ↓
session-owned MK
```

Do not implement that session manager now.

---

# 14. Production file impact

Based on the actual latest repository, identify the exact files that would eventually need modification for Stage 3 production integration.

For each file provide:

```text
file
current responsibility
planned responsibility
reason it must change
security risk if unchanged
```

Likely areas include:

```text
lib/core/master_key_manager.dart
lib/core/password_key_derivation.dart
lib/core/password_state_manager.dart
lib/core/crypto_engine.dart
lib/core/database.dart
lib/features/settings.dart
```

but do NOT assume this list is complete.

Use the actual repository.

Also identify any files that MUST NOT be modified by Stage 3 integration.

---

# 15. Data migration boundary

Explicitly define what is and is not migrated.

Stage 3 prerequisite may migrate:

```text
legacy cryptography credential state
legacy device recovery metadata
```

only if required to establish the approved MK architecture.

It must NOT migrate:

```text
note ciphertext
token ciphertext
encrypted database payloads
```

unless another already-approved stage explicitly owns that migration.

Clearly distinguish:

```text
key-management/recovery migration
```

from:

```text
application ciphertext migration
```

---

# 16. Security invariants

The final design must guarantee:

```text
[ ] exactly one dataset-authoritative MK
[ ] MK is generated randomly, never derived from password
[ ] password verifier cannot reconstruct MK
[ ] Password-KEK unwrap returns the dataset's same MK
[ ] Recovery-KEK unwrap returns the dataset's same MK
[ ] password changes preserve the same MK
[ ] device additions preserve the same MK
[ ] malformed wrappers cannot install an MK
[ ] tampered wrappers cannot install an MK
[ ] failed recovery cannot generate a replacement MK
[ ] legacy authSalt wrapper cannot be mistaken for MK
[ ] provisional MK cannot become authoritative after a failed commit
[ ] local/remote inconsistency cannot create two authoritative MKs
[ ] temporary MK buffers are zeroed when no longer needed
[ ] no plaintext MK is persisted
[ ] no MK is logged
[ ] no password/mnemonic is logged
[ ] Stage 4 HKDF remains the existing derivation primitive
[ ] Stage 5 consumes the established MK rather than creating another one
[ ] Stage 6 ciphertext migration remains out of scope
```

---

# 17. Required design tables

Your response must include at least these tables.

## Table A — Artifact ownership

| Artifact                | Owner | Persistent? | Authoritative? | Recovery source |
| ----------------------- | ----- | ----------: | -------------: | --------------- |
| MK                      | ...   |         ... |            ... | ...             |
| Password verifier       | ...   |         ... |            ... | ...             |
| Password-KEK wrapper    | ...   |         ... |            ... | ...             |
| Recovery-KEK wrapper    | ...   |         ... |            ... | ...             |
| legacy authSalt wrapper | ...   |         ... |            ... | ...             |
| NEK                     | ...   |         ... |            ... | ...             |
| TEK                     | ...   |         ... |            ... | ...             |

## Table B — State machine

| State           | MK status | Local wrapper | Remote wrapper | Next valid transitions |
| --------------- | --------- | ------------- | -------------- | ---------------------- |
| Fresh           | ...       | ...           | ...            | ...                    |
| Provisional     | ...       | ...           | ...            | ...                    |
| Authoritative   | ...       | ...           | ...            | ...                    |
| Recovery        | ...       | ...           | ...            | ...                    |
| Password change | ...       | ...           | ...            | ...                    |
| Failed          | ...       | ...           | ...            | ...                    |

## Table C — Failure matrix

| Failure point | MK status | Durable state | Retry? | Recovery action |
| ------------- | --------- | ------------- | ------ | --------------- |
| ...           | ...       | ...           | ...    | ...             |

## Table D — Legacy compatibility

| Existing repository state | Detection | Behavior | Security consequence |
| ------------------------- | --------- | -------- | -------------------- |
| legacy authSalt file      | ...       | ...      | ...                  |
| new MK wrapper            | ...       | ...      | ...                  |
| malformed                 | ...       | ...      | ...                  |
| tampered                  | ...       | ...      | ...                  |

---

# 18. Final readiness gate

At the end, provide an explicit checklist:

```text
STAGE 3 PRODUCTION INTEGRATION DESIGN READY?

[ ] One authoritative MK lifecycle fully defined
[ ] First-device establishment fully defined
[ ] Local Password-KEK wrapper persistence fully defined
[ ] Remote Recovery-KEK wrapper persistence fully defined
[ ] Joining-device recovery fully defined
[ ] Password-change rewrap fully defined
[ ] Local/remote crash consistency fully defined
[ ] Legacy device_key.json compatibility fully defined
[ ] Tampered/malformed wrapper handling fully defined
[ ] Exact authority/promotion boundary fully defined
[ ] Every partial failure has an explicit outcome
[ ] system_crypto_pin role is explicitly separated
[ ] Stage 4 HKDF boundary is explicit
[ ] Stage 5 consumption boundary is explicit
[ ] No Stage 5 implementation included
[ ] No Stage 6 ciphertext migration included
[ ] No new cryptographic protocol invented
[ ] Production file impact is fully identified
[ ] Security invariants are testable
```

Finish with exactly one status:

```text
STAGE 3 PRODUCTION INTEGRATION DESIGN — READY FOR IMPLEMENTATION
```

or:

```text
STAGE 3 PRODUCTION INTEGRATION DESIGN — BLOCKED
```

If blocked, identify the exact unresolved architectural decision/dependency.

**Do not modify production code in this task.**

This is a design review only. The next action after this document is approved will be implementation of the already-designed Stage 3 production integration, followed by a separate adversarial security audit before Stage 5 resumes.
