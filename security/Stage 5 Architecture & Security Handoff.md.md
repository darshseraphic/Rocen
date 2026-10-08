# ROCEN — Stage 5 Architecture & Security Handoff

**Document type:** Developer / AI handoff and living Stage 5 security status record  
**Current baseline:** `Rocen-P5.zip`  
**Last audited baseline:** 2026-10-08  
**Status:** **Stage 5 architecture repair in progress — NOT COMPLETE**

---

## 1. Purpose of this document

This document records where Rocen Stage 5 development currently stands, what has already been implemented, what was found during the security review, what is being repaired now, and how the development/review workflow is being run.

It is intended to give future developers, reviewers, and AI agents a shared understanding of:

- the current architecture,
- the security assumptions,
- the verified problems,
- the files involved,
- the work already completed,
- the work currently being repaired,
- and the evidence required before Stage 5 can be declared complete.

**Important:** this document is a handoff/status record, not the source of truth for implementation correctness. The actual source tree is authoritative. The latest ZIP must always be independently audited when a new implementation claim is made.

---

## 2. Source/evidence hierarchy

When different artifacts disagree, use this order of authority:

1. **Current Rocen source tree / latest ZIP** — implementation truth.
2. **Current test tree** — evidence of intended assertions and test coverage, but not proof of execution unless runtime output exists.
3. **Security architecture/design documents** — intended architecture and security reasoning.
4. **Implementor AI reports** — implementation claims that must be checked against source.
5. **Auditor AI reports** — security findings and recommendations that must also be checked against source.
6. **This handoff document** — project/status memory and workflow record.

An AI report never overrides the actual source.

---

# 3. Development workflow being used

The Rocen security-development workflow is intentionally adversarial and iterative.

```text
Developer
   ↓
AI examines project/security files
   ↓
AI security review
   ↓
Auditor AI #1
   ↔
Auditor AI #2
   ↓
Auditors challenge findings/assumptions
   ↓
Consensus on concrete security problem(s)
   ↓
AI reviews/strengthens the implementation prompt
   ↓
Implementor AI
   ↓
Implementation
   ↓
Latest ZIP/source returned
   ↓
Independent source audit
   ↓
If defects remain → repeat repair cycle
```

### Why the workflow is structured this way

The goal is not to ask one AI to “implement security” and trust the result.

Instead:

- the **developer** defines the product boundary and non-goals;
- one AI examines the actual files and architecture;
- **two auditor AIs challenge each other**, looking for inconsistencies, bypasses, race conditions, ownership mistakes, and false evidence;
- another AI **improves the implementation prompt** based on the findings;
- the **implementor AI changes the code**;
- the resulting ZIP is then inspected independently instead of accepting the implementor's report at face value.

This is an adversarial review loop rather than a single-pass implementation.

---

# 4. Stage 5 security goal

Stage 5 is establishing a real session-security boundary around the application's live cryptographic material and authenticated UI/provider lifetime.

The target state is:

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

The intended ownership model is:

```text
MasterKeyLocalStore
    = durable encrypted authority record
    = no live session-key ownership

MasterKeyManager
    = control/state/serialization/authority decisions
    = no long-lived live MK/NEK/TEK ownership

ActivationTransaction
    = exactly one unlock attempt
    = temporary activation-secret owner
    = synchronously reachable by lockSync()

SessionKeyMaterial
    = sole authoritative live owner of MK/NEK/TEK
      after installation

SessionAuthorizationToken
    = real current-session authorization capability
    = epoch/session bound
    = non-forgeable by ordinary feature code

Providers / widgets / navigation
    = never authoritative cryptographic-key owners
```

The cryptographic meaning of Stage 3 and Stage 4 must remain unchanged during Stage 5 hardening.

No Stage 6 envelope/data-migration redesign is part of this repair pass.

---

# 5. What has already been implemented in the current Stage 5 work

The current `Rocen-P5.zip` manifest records:

- **14 new files**
- **10 modified files**
- **29 unchanged files**
- **1 project/configuration change entry**

The current tree contains 55 files in the ZIP.

## 5.1 Session state/security layer

The current implementation includes a Stage 5 session state machine in:

`lib/core/session_security_manager.dart`

with the intended states:

- `bootstrap`
- `locked`
- `unlocking`
- `activating`
- `unlocked`

The source comments describe lifecycle interruption as returning to `LOCKED` and explicitly state that resume does not silently recreate an authenticated session.

## 5.2 Session authorization capability

`SessionAuthorizationToken` exists in `session_security_manager.dart`.

Its current source shape has:

- private constructor,
- epoch-bound state,
- creation controlled by `SessionSecurityManager`.

The intended purpose is authorization of ordinary authenticated-session operations, separate from key ownership.

## 5.3 Activation transaction

The current ZIP adds:

`lib/core/activation_transaction.dart`

The transaction currently stores:

- unlock epoch,
- stale state,
- candidate MK buffer.

It also provides lifecycle operations such as:

- adopting candidate MK,
- relinquishing candidate MK,
- invalidation,
- clearing,
- freshness checks.

The transaction is intended to be synchronously invalidatable by `lockSync()`.

**Current status:** conceptually correct, but **visibility and some lifetime invariants still need repair**. See Section 8.

## 5.4 Deterministic checkpoint system

The current ZIP adds:

`lib/core/security_checkpoints.dart`

The seven required checkpoints exist:

1. `AFTER_PASSWORD_AUTH`
2. `AFTER_MK_UNWRAP`
3. `AFTER_NEK_DERIVATION`
4. `AFTER_TEK_DERIVATION`
5. `BEFORE_SESSION_INSTALL`
6. `AFTER_SESSION_INSTALL`
7. `BEFORE_ACTIVATION_COMMIT`

The checkpoints are intended to be deterministic pause/resume synchronization points for security-race tests, not authorization mechanisms and not secret containers.

## 5.5 Session key material

The current ZIP adds:

`lib/core/session_key_material.dart`

This component is intended to own live MK/NEK/TEK material during the live session.

Its `install()` path includes generation-based stale checks and the `AFTER_SESSION_INSTALL` boundary.

**Current status:** important stale-result fencing exists, but the lifetime of temporary key objects across suspended async derivation still requires architectural repair. See Section 8.

## 5.6 Session unlock path

The current ZIP adds:

`lib/core/session_unlock_service.dart`

The production password unlock path now uses the real password → local authority → authentication → MK unwrap sequence rather than relying on a fabricated authentication seam for the Stage 5 race path.

The source contains the required password/MK checkpoint locations.

## 5.7 MasterKeyManager custody refactor

`lib/core/master_key_manager.dart` was modified to move away from long-lived live MK custody.

The target responsibility is now control/state/serialization/authority decisions rather than acting as a persistent live-key cache.

This is a major architectural improvement over the earlier design.

## 5.8 Domain-key derivation

`lib/core/domain_key_derivation.dart` was modified in the Stage 5 branch while preserving the Stage 4 domain-key derivation model.

Stage 5 must continue to preserve the established derivation semantics and frozen vectors.

## 5.9 UI/session entry points

The current ZIP adds:

`lib/features/lock_screen.dart`

and modifies:

`lib/main.dart`
`lib/navbar.dart`
`lib/features/settings.dart`

The navigation representation has been moved toward a data-only model rather than retaining long-lived Widget instances inside navigation state.

## 5.10 Session/security tests

The current ZIP adds tests for:

- activation transaction lifecycle,
- key ownership audits,
- lock screen behavior,
- session authorization,
- session key material,
- session security manager,
- session unlock service,
- settings-sensitive cleanup.

Several pre-existing Stage 3 tests were also modified to match the Stage 5 ownership refactor.

---

# 6. Files changed in the current `Rocen-P5.zip`

## 6.1 New production files

```text
lib/core/activation_transaction.dart
lib/core/security_checkpoints.dart
lib/core/session_key_material.dart
lib/core/session_security_manager.dart
lib/core/session_unlock_service.dart
lib/features/lock_screen.dart
```

## 6.2 Modified production files

```text
lib/core/domain_key_derivation.dart
lib/core/master_key_manager.dart
lib/core/master_key_production_service.dart
lib/features/settings.dart
lib/main.dart
lib/navbar.dart
```

## 6.3 New test files

```text
test/activation_transaction_test.dart
test/key_ownership_audit_test.dart
test/lock_screen_test.dart
test/session_authorization_gate_test.dart
test/session_key_material_test.dart
test/session_security_manager_test.dart
test/session_unlock_service_test.dart
test/settings_sensitive_cleanup_test.dart
```

## 6.4 Modified test files

```text
test/domain_key_derivation_test.dart
test/master_key_manager_test.dart
test/master_key_production_service_test.dart
test/widget_test.dart
```

## 6.5 Unchanged but relevant production files

The following remain part of the security surface and were not changed in the current ZIP, but must continue to be audited when the architecture changes:

```text
lib/core/master_key_local_store.dart
lib/core/password_key_derivation.dart
lib/core/secure_bytes.dart
lib/core/ram_lock.dart
lib/core/cert_pinning.dart
lib/core/github_backup_service.dart
lib/core/database.dart
lib/core/crypto_engine.dart
lib/core/crypto_isolate.dart
```

---

# 7. What the implementor AI reported vs. what the latest ZIP actually proves

The implementor reported substantial progress, including:

- an explicit ActivationTransaction,
- synchronously reachable invalidation from `lockSync()`,
- immediate checkpoint freshness checks,
- local `SessionKeyMaterial.install()` stale detection,
- removal of the arbitrary `SessionAuthorizationPolicy` callback design,
- use of the real `SessionAuthorizationToken`.

Some of those claims are reflected in the current ZIP.

However, the latest ZIP also proves that the implementation is **not yet at the final architecture described by the later prompts**.

The ZIP still contains:

- public `associateRemoteForTesting()`;
- public `changePasswordForTesting()`;
- a public `ActivationTransaction` constructor;
- unwrap-to-adoption lifetime gaps;
- persistent outer `MaterialApp`/Navigator structure rather than a genuinely session-scoped application/navigation boundary;
- ProviderContainer destruction tied to Flutter widget disposal;
- incomplete bootstrap/session transition behavior;
- no native Android/iOS screenshot-control implementation in the archive.

Therefore the implementor report must be treated as a progress report, not completion evidence.

---

# 8. Verified security blockers discovered in the latest ZIP

These are the main problems the current repair pass is intended to solve.

## 8.1 Public authorization-free security mutations

Current source still exposes:

```text
associateRemoteForTesting()
changePasswordForTesting()
```

They are publicly reachable.

A name such as `ForTesting` is not an access-control boundary.

### Required fix

Remove these public production security-mutation methods entirely.

Stage 3 tests must instead target genuinely lower-level cryptographic/mechanical primitives that do not themselves constitute an unauthorized Stage 5 security mutation.

No public replacement may be introduced.

---

## 8.2 ActivationTransaction is still public

Current source defines a publicly constructible:

```dart
class ActivationTransaction {
  ActivationTransaction(...)
}
```

### Required fix

Make it an internal implementation detail.

Ordinary application/feature code must not be able to construct the real production activation transaction.

Do not widen production visibility merely to make unit tests easier.

---

## 8.3 Unwrap → adopt stale race

Current source contains the important sequence:

```text
await MK unwrap
    ↓
returned candidate
    ↓
adoptCandidateMk(candidate)
    ↓
AFTER_MK_UNWRAP
```

There is a possible lock during the unwrap await.

The required invariant is:

```text
lockSync()
    ↓
transaction becomes stale
    ↓
unwrap completes
    ↓
stale candidate must NOT be adopted
```

### Required fix

1. Check transaction freshness immediately after unwrap returns.
2. Make `adoptCandidateMk()` itself defensive and reject an already-stale transaction.
3. Clear/dispose the rejected incoming candidate rather than retaining it.

---

## 8.4 Suspendable activation secrets are not all synchronously controllable

Temporary `SecureBytes` objects can exist as async locals during NEK/TEK derivation.

Generation checks can reject stale completion, but generation fencing is not the same as synchronous secret-lifetime control.

### Required fix

All suspendable activation material that must survive an await must have an explicit owner that `lockSync()` can reach.

Target model:

```text
ActivationTransaction
    = temporary activation secrets

SessionKeyMaterial
    = authoritative live session secrets after transfer
```

Do not claim impossible physical memory guarantees.

---

## 8.5 changePassword durable-write fencing

Entry-time and queue-time authorization checks are not sufficient when an operation has additional awaits before durable mutation.

A lock can occur during KDF/read/other asynchronous work.

### Required fix

Use:

```text
authorize
→ prepare
→ await / KDF / read
→ FINAL authorization + epoch validation
→ protected durable write
```

The final revalidation must occur immediately before protected durable security-state mutation.

Where a sequence contains multiple durable writes separated by awaits, each protected write needs appropriate final fencing.

---

## 8.6 associateRemote durable-write / remote-start fencing

The same issue exists for `associateRemote()`.

### Required fix

```text
authorize
→ prepare
→ await / remote operation / KDF
→ FINAL authorization + epoch validation
→ protected local mutation or remote-side-effect start
```

A network operation already in progress cannot be described as canceled unless it is actually canceled.

Stale results must be rejected locally before protected state mutation.

---

## 8.7 Protected application / Navigator is not genuinely session-scoped

The current ZIP still has a persistent outer `MaterialApp` with its Navigator.

`ProtectedAppRoot` is a subtree rather than the actual session-owned application/navigation boundary.

That means protected `Navigator.push/pop` operations resolve through the permanent app-level navigation context unless explicitly redesigned.

### Required fix

Target structure:

```text
Outer non-sensitive shell
    ↓
LOCKED
    → no protected application tree
    → no protected Navigator
    → no privileged provider graph

Session-active
    → session-scoped MaterialApp
    → session-scoped Navigator
    → session-scoped providers
    → protected screens
```

The repair must be validated against the actual widget tree, not merely through comments.

---

## 8.8 ProviderContainer is not synchronously destroyed by lockSync()

The current source places the actual `ProviderContainer.dispose()` inside widget `dispose()`.

The current flow is effectively:

```text
lockSync()
    ↓
setState()
    ↓
Flutter rebuild
    ↓
widget disposal
    ↓
ProviderContainer.dispose()
```

This does not satisfy the requirement that security-critical session resource destruction be independent of a future Flutter frame.

### Required fix

Create explicit session-resource ownership reachable from `lockSync()`.

`lockSync()` must be able to synchronously invalidate/destroy/detach the privileged session ProviderContainer and associated security resources.

Flutter's later widget rebuild is only visual cleanup.

---

## 8.9 ACTIVATING resources must also be synchronously destructible

The current architecture can create session resources during activation before the normal unlocked-session teardown registration is fully established.

### Required fix

As soon as protected resources are created during activation, register them with an explicit cleanup owner reachable by `lockSync()`.

The activation state must never contain a protected resource whose destruction depends solely on later widget disposal.

---

## 8.10 Bootstrap/first-run flow remains incomplete

The current architecture can leave first-run setup in a bare Settings screen instead of cleanly entering the standard session lifecycle.

### Required fix

Preserve the approved credential model:

```text
existing cryptography password
    =
Stage 5 session-unlock credential
```

After first-device establishment, the application must enter the normal Stage 5 security lifecycle without requiring a restart simply to enter the protected session model.

---

## 8.11 recoverFromRemote() requires complete scope analysis

The current call graph suggests it is used for pre-session initialization/recovery.

That may be valid.

But the public API should be narrowed if the actual architecture is bootstrap-only, and the full race/await/durable mutation path must still be traced.

Do not add a session token solely to satisfy a checklist if doing so would make legitimate pre-session recovery impossible.

---

## 8.12 Native screenshot protection is not verified in the current archive

The ZIP contains Dart MethodChannel integration but no native Android/iOS implementation that can be independently verified in this archive.

Therefore the project must not claim OS-level screen capture protection as implemented.

The final report must accurately distinguish:

```text
Dart hook present
native implementation unavailable/unverified
```

from actual verified native enforcement.

---

# 9. Current architecture: intended repaired direction

The next architecture target is:

```text
                    ┌────────────────────────────┐
                    │ SessionSecurityManager     │
                    │ lifecycle + authorization  │
                    └─────────────┬──────────────┘
                                  │
                           one unlock attempt
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │ ActivationTransaction      │
                    │ temporary activation      │
                    │ secret ownership           │
                    │ epoch/stale state          │
                    └─────────────┬──────────────┘
                                  │
                       one-way synchronous transfer
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │ SessionKeyMaterial         │
                    │ live MK/NEK/TEK owner      │
                    └────────────────────────────┘

                    SessionAuthorizationToken
                    = session capability only

MasterKeyManager
    = control/authority/serialization
    ≠ live key cache

MasterKeyLocalStore
    = durable encrypted authority only
```

UI/resource side:

```text
Outer non-sensitive shell
        │
        ├── LOCKED
        │      └── no protected MaterialApp/Navigator/provider session
        │
        └── ACTIVATING / UNLOCKED
               └── session-owned application
                      ├── session Navigator
                      ├── session ProviderContainer
                      └── protected feature widgets
```

---

# 10. Planned/current repair files

The exact set may expand if source review reveals a stronger architecture is necessary. The likely files involved are:

## Production files expected to be repaired

```text
lib/core/activation_transaction.dart
lib/core/master_key_production_service.dart
lib/core/session_security_manager.dart
lib/core/session_unlock_service.dart
lib/core/session_key_material.dart
lib/main.dart
lib/features/settings.dart
```

A new internal session-resource owner/controller may be introduced if that is the cleanest way to make ProviderContainer destruction synchronous.

Possible additional files may be touched if imports/exports or test structure require it.

## Tests expected to be rewritten/updated

```text
test/key_ownership_audit_test.dart
test/master_key_production_service_test.dart
test/session_authorization_gate_test.dart
test/activation_transaction_test.dart
test/session_security_manager_test.dart
test/session_unlock_service_test.dart
test/session_key_material_test.dart
test/widget_test.dart
```

Additional focused tests may be added for:

- unwrap/adopt stale race,
- synchronous provider destruction,
- session navigator isolation,
- final durable-write fencing,
- activation-resource cleanup,
- bootstrap transition.

---

# 11. How the current security bugs are being fixed

## 11.1 Public mutation bypass

Before:

```text
Stage 5 production operation
        OR
public *ForTesting* security mutation
```

Target:

```text
Stage 5 authenticated operation
    ↓
required real SessionAuthorizationToken
    ↓
protected mutation
```

Stage 3 mechanics will be tested at a lower layer that has no concept of session authorization.

---

## 11.2 Stale transaction / key ownership

Before:

```text
await unwrap
    ↓
possibly stale
    ↓
adopt candidate
```

Target:

```text
await unwrap
    ↓
transaction freshness check
    ↓
adopt candidate
```

plus an invariant inside `adoptCandidateMk()` that rejects stale adoption regardless of caller discipline.

---

## 11.3 Temporary secret ownership

Before:

```text
async local SecureBytes
    ↓
await
    ↓
lockSync cannot directly reach local
```

Target:

```text
ActivationTransaction / explicit session resource owner
    ↓
all suspendable temporary material
    ↓
lockSync synchronously invalidates/clears owner
```

---

## 11.4 Durable mutation fencing

Before:

```text
authorize
→ await
→ await
→ write
```

Target:

```text
authorize
→ prepare
→ await
→ final authorization/epoch validation
→ write
```

---

## 11.5 UI/provider session destruction

Before:

```text
lockSync
→ setState
→ later Flutter disposal
→ ProviderContainer.dispose
```

Target:

```text
lockSync
→ security state LOCKED
→ invalidate session resources
→ synchronously destroy privileged provider resources
→ visual widget teardown later
```

---

# 12. Deterministic checkpoint test plan

The seven mandatory tests remain the primary race proof.

## A — AFTER_PASSWORD_AUTH

```text
pause
→ lockSync()
→ release
→ immediate freshness failure
→ no MK recovery continuation
→ LOCKED
```

## B — AFTER_MK_UNWRAP

```text
pause
→ lockSync()
→ release
→ freshness failure
→ acknowledgeRecoveredAuthority() does NOT execute
→ no stale authority mutation
→ LOCKED
```

## C — AFTER_NEK_DERIVATION

```text
pause
→ lockSync()
→ release
→ freshness failure
→ TEK derivation does NOT continue
→ LOCKED
```

## D — AFTER_TEK_DERIVATION

```text
pause
→ lockSync()
→ release
→ freshness failure
→ installation does NOT begin
→ LOCKED
```

## E — BEFORE_SESSION_INSTALL

```text
pause
→ lockSync()
→ release
→ freshness failure
→ install() does NOT begin
→ LOCKED
```

## F — AFTER_SESSION_INSTALL

```text
install/publish
→ pause
→ lockSync()
→ session material destroyed
→ release
→ install() itself detects stale generation/transaction
→ install() fails
→ no successful installation reported
→ LOCKED
```

## G — BEFORE_ACTIVATION_COMMIT

```text
pause
→ lockSync()
→ release
→ freshness failure
→ ACTIVATING cannot commit
→ LOCKED
```

Additionally required:

## H — unwrap/adoption race

```text
unwrap awaits
→ lockSync()
→ unwrap returns
→ adoption attempt
→ stale adoption rejected
→ incoming candidate cleared
→ no authority mutation
→ LOCKED
```

---

# 13. Authorization test plan

The final tests must prove:

- production security mutations require `SessionAuthorizationToken`;
- token construction is unavailable to ordinary application code;
- token is immutable;
- token is epoch/session bound;
- lock invalidates the token;
- a stale token cannot authorize a later session;
- no public `none`/always-authorized policy exists;
- no public `ForTesting` security mutation remains;
- no public lower-level durable security mutation bypass remains.

---

# 14. Ownership audit plan

Search the entire repository for:

```text
raw MK fields
MK caches
raw-MK getters
NEK/TEK caches
MasterKeyManager live-key custody
public ActivationTransaction construction
SessionAuthorizationPolicy
.no-op authorization
ForTesting security mutations
authorization callbacks
global privileged providers
session singleton key storage
retained protected Widgets
```

Every match must receive a deliberate disposition.

Search results must distinguish executable code from documentation/comments where appropriate.

---

# 15. Async secret-retention audit plan

Every asynchronous boundary must be evaluated for retention of:

- MK
- NEK
- TEK
- password
- password-derived intermediates
- recovery secrets
- authorization capabilities

Check:

- Futures
- Completers
- callbacks
- timers
- providers
- notifiers
- singleton services
- caches
- streams
- subscriptions
- errors/exceptions
- logging/debug output
- test hooks

The goal is not an impossible “zero bytes anywhere in RAM” guarantee.

The goal is one explicit, controllable security ownership model with no unintended second authoritative owner.

---

# 16. Bootstrap / corrupt authority rules

The approved credential model remains:

```text
existing cryptography password
    =
Stage 5 session-unlock credential
```

There is no second session password.

The implementation must distinguish:

```text
NO AUTHORITY
CORRUPT AUTHORITY
VALID AUTHORITY
```

Corrupt authority must fail closed and must not silently become fresh-install bootstrap.

First-run setup must enter the normal Stage 5 session lifecycle.

---

# 17. Screenshot-control status

Current ZIP status:

```text
Dart MethodChannel integration: present
Native Android/iOS implementation: absent in archive
OS-level screenshot enforcement: unverified
```

Therefore no documentation may claim native screenshot prevention is implemented until the native source exists and is independently verified.

---

# 18. Runtime/evidence policy

Because the current implementor environment has reported Flutter/Dart unavailable, the project must distinguish:

### A. EXECUTED AND PASSED

Flutter/Dart command actually executed and succeeded.

### B. EXECUTED AND FAILED

Flutter/Dart command actually executed and failed.

### C. NOT EXECUTED — runtime unavailable

Test exists but could not be run because the required runtime was unavailable.

### D. SOURCE-REVIEWED ONLY

Correctness supported by source inspection/hand trace but not runtime execution.

Python regex/source-order checks are **not** Flutter/Dart runtime execution.

---

# 19. Current implementation status matrix

| Area | Current status | Notes |
|---|---|---|
| Stage 5 session state machine | ✅ Implemented | Architecture exists; final integration still under repair |
| SessionAuthorizationToken | ✅ Good direction | Needs final capability/API audit |
| ActivationTransaction concept | ✅ Implemented | Public visibility and invariants still need repair |
| Deterministic checkpoints | ✅ Implemented | Seven required checkpoints present |
| Immediate checkpoint freshness | ✅ Substantially implemented | Must be re-audited after repairs |
| MasterKeyManager live-key custody | ✅ Improved | Must remain zero-live-key architecture |
| SessionKeyMaterial | ⚠️ Partially hardened | Async secret lifetime requires repair |
| Public ForTesting mutations | ❌ Blocker | Must be removed |
| Public ActivationTransaction | ❌ Blocker | Must be internal |
| Unwrap → adopt race | ❌ Blocker | Must reject stale adoption |
| changePassword final fencing | ❌ Blocker | Must fence final durable writes |
| associateRemote final fencing | ❌ Blocker | Must fence final protected mutation/start |
| recoverFromRemote scope | ⚠️ Needs full audit | Likely bootstrap-only; must be proven/narrowed |
| Protected MaterialApp boundary | ❌ Incomplete | Current outer MaterialApp persists |
| Protected Navigator boundary | ❌ Incomplete | Current Navigator belongs to permanent app shell |
| ProviderContainer sync destruction | ❌ Blocker | Current disposal depends on widget lifecycle |
| ACTIVATING resource teardown | ❌ Blocker | Must be synchronously reachable by lockSync |
| Bootstrap first-run transition | ⚠️ Incomplete | Must enter normal session lifecycle |
| Corrupt authority | ✅ Good direction | Must retain fail-closed distinction |
| Navigation data-only design | ✅ Improved | Must remain after Navigator repair |
| Native screenshot protection | ❌ Unverified | Native implementation absent in current archive |
| Durable encrypted app-data envelope | ❌ Not Stage 5-complete | Intentionally outside current cutover scope |
| Hardware-backed MK protection | ⚠️ Not verified | No current native platform implementation in archive |
| RAM locking | ⚠️ Best effort | Platform-dependent hardening, not absolute guarantee |
| Runtime Flutter/Dart execution | ❌ Not established | Current implementor environment unavailable |

---

# 20. Completion gate for this phase

Stage 5 architecture repair should not be considered complete until all of the following are true:

```text
[ ] no public security-mutation bypass remains
[ ] no public ForTesting security mutation remains
[ ] no public no-op authorization remains
[ ] no public lower-level durable security mutation bypass remains
[ ] SessionAuthorizationToken is non-forgeable and epoch/session-bound
[ ] ActivationTransaction is not part of the normal public API
[ ] only SessionSecurityManager creates the production activation transaction
[ ] ActivationTransaction rejects adoption after invalidation
[ ] stale unwrap results cannot be adopted
[ ] all suspendable activation secrets have controlled ownership
[ ] lockSync can synchronously invalidate transaction-owned secrets
[ ] candidate MK ownership transfer is one-way
[ ] MasterKeyManager owns no long-lived live key bytes
[ ] SessionKeyMaterial is the sole authoritative live key owner after installation
[ ] all seven checkpoints are genuine stale-transaction boundaries
[ ] AFTER_MK_UNWRAP cannot reach authority acknowledgement after invalidation
[ ] AFTER_NEK_DERIVATION cannot continue to TEK after invalidation
[ ] AFTER_TEK_DERIVATION cannot reach installation after invalidation
[ ] BEFORE_SESSION_INSTALL blocks stale installation
[ ] AFTER_SESSION_INSTALL makes install() itself fail after invalidation
[ ] BEFORE_ACTIVATION_COMMIT blocks stale commit
[ ] changePassword final durable writes are fenced
[ ] associateRemote final mutations/remote starts are fenced
[ ] recoverFromRemote is appropriately bootstrap-scoped or authorized
[ ] stale remote results cannot mutate protected local state
[ ] protected MaterialApp is genuinely session-scoped
[ ] protected Navigator is genuinely session-scoped
[ ] protected navigation cannot survive lock
[ ] session ProviderContainer has explicit security ownership
[ ] lockSync synchronously destroys privileged provider resources
[ ] ACTIVATING resources are synchronously destroyable on lock
[ ] bootstrap enters the normal Stage 5 lifecycle
[ ] corrupt authority fails closed
[ ] lifecycle locking is enforced
[ ] deterministic A-G race tests are present
[ ] unwrap/adoption race test is present
[ ] tests do not depend on public authorization bypasses
[ ] old Stage 3 custody APIs cannot restore persistent MK ownership
[ ] no Stage 6/migration work is introduced
[ ] runtime evidence is truthful
```

---

# 21. Rules for future AI implementors

Future implementor AIs should follow these rules:

### Rule 1 — Source beats report

Never assume a previous AI report is correct. Inspect the current source.

### Rule 2 — Security architecture beats naming

A method named `ForTesting`, `internal`, `core`, or `testOnly` is not automatically safe.

### Rule 3 — Preserve cryptographic meaning

Do not change Stage 3/4 cryptographic semantics to solve Stage 5 lifecycle problems.

### Rule 4 — Do not weaken production security for tests

Make tests reach lower-level primitives or use internal arrangements, rather than shipping public bypasses.

### Rule 5 — A final-state check is not enough

A test that only proves `LOCKED` after a race does not prove where stale work stopped.

### Rule 6 — Epoch fencing is not secret zeroization

Rejecting a stale result is different from synchronously controlling the lifetime of the secret used to produce it.

### Rule 7 — Flutter visual teardown is not a security primitive

Security/resource destruction must not depend on a later frame.

### Rule 8 — Do not overclaim runtime evidence

Source inspection is not the same thing as executing Flutter/Dart tests.

### Rule 9 — Challenge the architecture

If a stronger security architecture is warranted, the implementor should say so and implement it, as long as Stage 3/4 cryptographic meaning, credential semantics, persistent data format, and scope are preserved.

### Rule 10 — Fix before expanding

Do not add unrelated Stage 5 features while security architecture blockers remain open.

---

# 22. Immediate next step

The implementation work is currently in the **targeted architecture-repair phase**.

The next implementor task is not to add unrelated features.

It is to repair the verified blockers in this order:

```text
1. Remove public ForTesting security mutations
2. Separate Stage 3 mechanics from Stage 5 authorization
3. Make ActivationTransaction internal
4. Fix stale unwrap → adoption
5. Control all suspendable activation-secret ownership
6. Fence final changePassword/associateRemote mutations
7. Fully scope/review recoverFromRemote
8. Build a genuinely session-scoped protected MaterialApp/Navigator
9. Give ProviderContainer explicit synchronous security ownership
10. Make ACTIVATING resources synchronously destructible
11. Repair first-run/bootstrap transition
12. Rewrite affected tests
13. Re-audit repository-wide ownership/API surface
14. Re-audit async secret retention
15. Perform final adversarial review
16. Report evidence honestly
```

Only after this repair cycle satisfies the completion gate should the remaining Stage 5 feature work continue.

---

# 23. Change history / review trail

## Stage 5 design baseline

The Stage 5 architecture documents established:

- LOCKED/UNLOCKING/ACTIVATING/UNLOCKED semantics,
- transactional unlock/rollback,
- session-scoped provider/UI lifetime,
- lockSync destruction ordering,
- generic crypto denial while locked,
- lifecycle locking,
- provider/navigation isolation,
- no Stage 6 migration during this stage.

## Ownership correction

Earlier implementation was identified as effectively having more than one live MK holder.

The architecture was changed toward:

```text
MasterKeyManager = authority/control
ActivationTransaction = temporary activation owner
SessionKeyMaterial = live authoritative session owner
```

## Checkpoint correction

The initial checkpoint implementation could only prove the eventual unlock would fail.

The design was strengthened so stale checkpoint resumption is immediately rejected.

## Authorization correction

An earlier authorization policy accepted arbitrary caller-provided logic and exposed a public no-op form.

That was identified as a structural bypass.

The target design now uses the real epoch-bound `SessionAuthorizationToken`.

## Current repair correction

The latest ZIP then showed that public `ForTesting` mutations still existed, and that UI/provider/session resource lifetime was not yet fully isolated.

The project is therefore currently in another targeted architecture-repair cycle.

---

# 24. Final status statement

**Rocen Stage 5 is not complete yet.**

The project has made substantial progress on the cryptographic/session architecture, especially around:

- session state,
- activation transactions,
- deterministic checkpoint testing,
- MK ownership separation,
- session key material,
- and epoch-bound authorization.

The latest source audit nevertheless found important remaining blockers around:

- public security-mutation bypasses,
- transaction visibility,
- async secret lifetime,
- stale durable mutations,
- session-scoped MaterialApp/Navigator ownership,
- synchronous ProviderContainer destruction,
- activation resource lifetime,
- bootstrap transition,
- and native screenshot-control verification.

These are the areas the current implementor is expected to repair before unrelated Stage 5 work continues.

**The next authoritative state should be determined from the next returned source ZIP, not from a progress report alone.**
