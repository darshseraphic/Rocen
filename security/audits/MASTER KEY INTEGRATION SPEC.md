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

- what random material is generated,
- where it is held temporarily,
- who owns each buffer,
- how it is zeroed,
- what state machine controls provisional vs authoritative state,
- what exact condition permits promotion to authoritative,
- whether the current `MasterKeyManager` is reused directly,
- which existing APIs are used,
- what new production adapters would be required.

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

- exact Hive box,
- exact key/name,
- serialization format,
- versioning requirements,
- whether the existing wrapper envelope is sufficient,
- how corruption is detected,
- how absence is distinguished from corruption,
- how successful load recovers the authoritative MK.

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

- exact JSON structure,
- exact use of the existing `PasswordKeyDerivation.wrapMasterKeyWithRecovery()` output,
- whether an explicit format/version field already exists,
- what metadata is required,
- whether the existing `device_key.json` location remains unchanged,
- how integrity/authenticity is validated,
- what is considered malformed vs unsupported vs tampered.

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

- what happens if the password is wrong,
- what happens if the mnemonic is wrong,
- what happens if both are wrong,
- how wrapper tampering is detected,
- how malformed JSON is handled,
- how an old legacy `device_key.json` is recognized,
- whether legacy recovery remains supported,
- whether legacy recovery is migration-assisted or explicitly unsupported,
- exactly when recovered MK becomes authoritative locally.

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

- raw wrapper contents,
- passwords,
- mnemonic words,
- keys,
- decrypted MK,
- raw sensitive exception contents.

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

| ArtifactOwnerPersistent?Authoritative?Recovery source |     |     |     |     |
| ----------------------------------------------------- | --- | --- | --- | --- |
| MK                                                    | ... | ... | ... | ... |
| Password verifier                                     | ... | ... | ... | ... |
| Password-KEK wrapper                                  | ... | ... | ... | ... |
| Recovery-KEK wrapper                                  | ... | ... | ... | ... |
| legacy authSalt wrapper                               | ... | ... | ... | ... |
| NEK                                                   | ... | ... | ... | ... |
| TEK                                                   | ... | ... | ... | ... |

## Table B — State machine

| StateMK statusLocal wrapperRemote wrapperNext valid transitions |     |     |     |     |
| --------------------------------------------------------------- | --- | --- | --- | --- |
| Fresh                                                           | ... | ... | ... | ... |
| Provisional                                                     | ... | ... | ... | ... |
| Authoritative                                                   | ... | ... | ... | ... |
| Recovery                                                        | ... | ... | ... | ... |
| Password change                                                 | ... | ... | ... | ... |
| Failed                                                          | ... | ... | ... | ... |

## Table C — Failure matrix

| Failure pointMK statusDurable stateRetry?Recovery action |     |     |     |     |
| -------------------------------------------------------- | --- | --- | --- | --- |
| ...                                                      | ... | ... | ... | ... |

## Table D — Legacy compatibility

| Existing repository stateDetectionBehaviorSecurity consequence |     |     |     |
| -------------------------------------------------------------- | --- | --- | --- |
| legacy authSalt file                                           | ... | ... | ... |
| new MK wrapper                                                 | ... | ... | ... |
| malformed                                                      | ... | ... | ... |
| tampered                                                       | ... | ... | ... |

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

Admin: Here is the latest files of the project @files.zip

# IMPLEMENTOR

# FINAL STAGE 3 PRODUCTION INTEGRATION DESIGN

**Scope:** design review only.
**Production implementation:** not started.
**Source of truth:** latest `/mnt/data/files.zip`, plus the already-approved Stage 1–4 security architecture and the existing Stage 3 primitives.

---

## Executive finding

The actual repository contains the Stage 3 cryptographic primitives, but they are not wired into the production credential/recovery flows.

The real application still uses:

```text
system_crypto_pin
    ↓
legacy CryptoEngine
    ↓
legacy note/token encryption
```

while the approved architecture requires:

```text
Password Verifier
       ↓ authentication only

Password-KEK
       ↓
wrapped MK ─────┐

Recovery-KEK    │
       ↓        │
wrapped same MK ┘
       ↓
      MK
       ↓
Stage 4 HKDF
   ┌───┴───┐
  NEK     TEK
```

The approved architecture explicitly defines MK as a randomly generated, immutable dataset key and requires its persisted forms to be wrapped copies rather than plaintext MK.

The Stage 3 primitive implementation already provides:

```text
createPasswordVerifier
verifyPassword
wrapMasterKeyWithPassword
unwrapMasterKeyWithPassword
wrapMasterKeyWithRecovery
unwrapMasterKeyWithRecovery
changePassword
```

and the current `changePassword()` implementation already verifies that the Password-KEK and Recovery-KEK wrappers resolve to the same MK before creating the new wrappers. It does not generate a new MK.

The missing work is therefore primarily **production wiring, persistence, migration, and reconciliation**, not new cryptography.

---

# A. Current implementation map

## Actual production chain

The latest project snapshot shows the current credential/data path is still:

```text
password entered
    ↓
CryptoEngine.hashPin(...)
    ↓
system_crypto_pin
    ↓
CryptoEngine.encryptProcess(...)
CryptoEngine.decryptProcess(...)
    ↓
encrypted notes / GitHub credentials
```

The current password-change flow explicitly invokes:

```text
localDatabaseProvider.notifier.migrateEncryptedNotes(...)
```

before replacing `system_crypto_pin`.

The current recovery flow explicitly invokes:

```text
CryptoEngine.unwrapDeviceKey(...)
    ↓
authSalt
    ↓
CryptoEngine.hashPinWithSalt(...)
    ↓
system_crypto_pin
```

So the existing production recovery path recovers an authentication-salt value, **not MK**.

The previous architecture audit describes this same legacy behavior: `system_crypto_pin` is both the verifier-like stored value and the effective input to note/token encryption, while `device_key.json` wraps `authSalt`.

## Approved Stage 3 chain

The approved architecture instead specifies:

```text
password
    ├──→ Password Verifier       → comparison only
    └──→ Password-KEK             → unwrap local MK wrapper

password + mnemonic
    ↓
Recovery-KEK
    ↓
unwrap remote Recovery wrapper
    ↓
same MK
```

The recovery architecture requires both password and mnemonic together and explicitly states that password alone on a new device is insufficient.

---

# B. Existing Stage 3 primitives: implementation status

| Primitive                                          | Actual status                   | Production use                                     |
| -------------------------------------------------- | ------------------------------- | -------------------------------------------------- |
| Password normalization/canonical recovery encoding | Implemented                     | Used by Stage 3 primitive                          |
| Password verifier                                  | Implemented/tested              | Not wired into the new production credential model |
| Password-KEK wrapping                              | Implemented/tested              | No production caller                               |
| Password-KEK unwrapping                            | Implemented/tested              | No production caller                               |
| Recovery-KEK wrapping                              | Implemented/tested              | No production caller                               |
| Recovery-KEK unwrapping                            | Implemented/tested              | No production caller                               |
| Same-MK password change                            | Implemented/tested              | No production caller                               |
| Recovery-wrapper refresh during password change    | Implemented in latest primitive | No production caller                               |
| MasterKeyManager generation/authority state        | Implemented/tested              | No production caller                               |
| Stage 4 HKDF                                       | Implemented/tested              | No production note/token caller                    |

So the correct classification is:

```text
Stage 3 architecture          = approved
Stage 3 primitives             = implemented
Stage 3 production wiring     = incomplete
```

---

# C. Exact current `device_key.json` semantics

The latest project snapshot confirms the legacy production format is:

```json
{
  "wrapSalt": "...",
  "wrapNonce": "...",
  "wrappedAuthSalt": "..."
}
```

Semantically:

```text
password + mnemonic
    ↓
legacy combinedSecret
    ↓
Argon2id
    ↓
legacy AES-GCM wrapping
    ↓
authSalt
```

`wrappedAuthSalt` contains the legacy authentication-salt ciphertext/tag representation.

The current production implementation does **not** wrap MK.

This is not an ambiguity that can safely be ignored.

## New approved `device_key.json`

The new production file should be the **direct JSON output of**:

```text
PasswordKeyDerivation.wrapMasterKeyWithRecovery(...)
```

That existing primitive emits:

```json
{
  "v": 1,
  "kdf": "argon2id",
  "memory": 65536,
  "iterations": 3,
  "salt": "...",
  "nonce": "...",
  "ct": "...",
  "mac": "..."
}
```

No additional cryptographic wrapper is necessary.

This directly reuses the existing Stage 3 wrapper format rather than inventing another one.

The approved architecture explicitly specifies the Recovery-KEK-wrapped MK as the remote artifact in `device_key.json`.

---

# D. Artifact ownership

## Table A — Artifact ownership

| Artifact                | Owner                                          | Persistent? |           Authoritative? | Recovery source                      |
| ----------------------- | ---------------------------------------------- | ----------: | -----------------------: | ------------------------------------ |
| MK                      | `MasterKeyManager` during Stage 3              |          No | Yes only after promotion | Password wrapper or Recovery wrapper |
| Password verifier       | Local MK security record                       |         Yes |                       No | Password comparison only             |
| Password-KEK wrapper    | Local MK security record                       |         Yes |                       No | Correct password                     |
| Recovery-KEK wrapper    | Local cached record + remote `device_key.json` |         Yes |                       No | Correct password + mnemonic          |
| Legacy authSalt wrapper | Legacy compatibility artifact                  |         Yes |                       No | Legacy password + mnemonic           |
| NEK                     | Stage 4 `DomainKeyDerivation`                  |          No |  No persistent authority | Re-derived from authoritative MK     |
| TEK                     | Stage 4 `DomainKeyDerivation`                  |          No |  No persistent authority | Re-derived from authoritative MK     |

The important ownership invariant is:

```text
MK itself
    → never persisted plaintext

wrapped MK
    → persisted

NEK/TEK
    → never persisted
```

---

# E. Proposed local persistence

The current code has no production local MK-wrapper key.

The design should introduce one logical security record in:

```text
rocen_settings_box
```

under a dedicated key such as:

```text
master_key_record_v1
```

This is **storage metadata**, not a new cryptographic format.

Recommended logical record:

```json
{
  "v": 1,
  "status": "pending_remote | authoritative",
  "passwordVerifier": "...",
  "passwordWrap": "{...existing Stage 3 wrapper JSON...}",
  "recoveryWrap": "{...existing Stage 3 wrapper JSON...}",
  "recoveryPublishState": "pending | published",
  "repository": "..."
}
```

The record contains no plaintext MK.

The locally cached Recovery wrapper is useful because the mnemonic must never be persisted; without the cached wrapper, an interrupted remote publication could require the user to re-enter the mnemonic merely to retry the exact same recovery artifact.

The approved architecture explicitly permits Recovery-wrapper metadata to exist locally when cached and defines the actual remote wrapper as the cross-device recovery artifact.

### Why one record

Using one logical record makes the set of:

```text
verifier
password wrapper
recovery wrapper
pending status
```

a single durable unit rather than scattering them across independently committed Hive keys.

Startup must validate the complete record.

---

# F. Local wrapper states

The local record has four relevant interpretations:

| State                     | Meaning                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------ |
| Missing                   | This installation has no new MK security state                                                   |
| Complete + authoritative  | Local wrapper set is committed and dataset MK is established                                     |
| Complete + pending remote | Candidate MK/wrappers exist, but remote Recovery artifact has not yet been established/confirmed |
| Malformed                 | Security record exists but cannot be trusted                                                     |

Corruption must never cause the application to generate a replacement MK automatically if a remote dataset already exists.

---

# G. First-device MK establishment

For a repository-backed dataset, the exact sequence should be:

```text
user already has/establishes cryptography password
    ↓
generate 32-byte random MK
    ↓
MK enters MasterKeyManager PROVISIONAL
    ↓
generate/display 12-word recovery mnemonic
    ↓
PasswordKeyDerivation.wrapMasterKeyWithPassword(MK, password)
    ↓
PasswordKeyDerivation.wrapMasterKeyWithRecovery(
    MK, password, mnemonic)
    ↓
persist local master_key_record_v1 as pending_remote
    ↓
conditional remote creation of device_key.json
    ↓
verify remote file is the expected NEW schema
    ↓
PROMOTE provisional MK to AUTHORITATIVE
    ↓
mark local record authoritative
```

The MK is generated by the existing `MasterKeyManager` using the existing CSPRNG path. No password-derived MK exists.

The approved architecture explicitly defines MK as a random 256-bit value generated once and subsequently recovered only from wrapped copies.

## Temporary ownership

During wrapper generation:

```text
MasterKeyManager
    → owns provisional MK
```

The production integration may obtain a temporary defensive copy for the existing Stage 3 wrapper functions:

```text
temporary Uint8List
    ↓
PasswordKeyDerivation.wrap...
    ↓
temporary Uint8List zeroed
```

The wrapper strings never contain plaintext MK.

The existing manager's authoritative state transition remains the authority boundary rather than bypassing it.

---

# H. Exact promotion condition

The MK becomes authoritative only after:

```text
local Password-KEK wrapper persisted successfully
+
local Recovery wrapper/pending record persisted successfully
+
remote Recovery-wrapped-MK artifact conditionally created successfully
+
remote artifact verified as the expected new wrapper
```

Then:

```text
MasterKeyManager.promoteProvisionalToAuthoritative()
```

is the in-memory authority transition.

No promotion occurs merely because:

```text
MK was generated
```

or:

```text
local wrapper was written
```

or:

```text
password authentication succeeded
```

This preserves the existing Stage 2 provisional/authoritative invariant. The current `MasterKeyManager` explicitly refuses authoritative use while provisional.

---

# I. First-device crash cases

## Case A

```text
MK generated
↓
local wrapper write succeeds
↓
app crashes
↓
remote wrapper never published
```

Durable state:

```text
master_key_record_v1 = pending_remote
```

On restart:

```text
do NOT generate a new MK
↓
authenticate with local password
↓
unwrap local Password-KEK wrapper
↓
reuse cached Recovery wrapper
↓
retry conditional remote publication
```

If it still succeeds, the same MK becomes authoritative.

---

## Case B

```text
remote wrapper published
↓
local finalization write fails
```

The remote artifact is now authoritative.

The local record remains pending or may be absent.

Next startup must:

```text
detect new device_key.json
↓
do NOT generate MK
↓
recover same MK from remote using password + mnemonic
```

If the local pending record exists and its cached Recovery wrapper exactly matches the remote wrapper, the device can safely finalize its local state without generating another key.

---

## Case C

```text
remote wrapper published
↓
process crashes
↓
local "authoritative" flag never recorded
```

Same treatment as Case B.

The remote artifact wins the authority race.

No new MK is generated.

---

## Case D

```text
local wrapper committed
↓
remote publish fails/timeout
```

The local MK remains **provisional**, not authoritative.

The pending record remains.

Retry reuses the same Recovery wrapper.

A timeout is never treated as permission to generate a second MK.

---

# J. Remote write mechanism

For authority-establishing writes, use the existing conditional operations:

```text
fresh remote absence
    → createFileIfAbsent()
```

and for a controlled schema migration:

```text
known current ref SHA
    → updateFileWithFastForwardCheck()
```

Do **not** use the current `GithubBackupService.amendSync()` as the authority mechanism. Its implementation creates a commit and then force-updates the branch reference; it is not the appropriate primitive for establishing exclusive ownership of the new device-key artifact.

The existing `updateFileWithFastForwardCheck()` already gives the required branch-movement conflict behavior.

---

# K. Joining-device recovery

For a repository containing the new schema:

```text
fetch device_key.json
    ↓
strictly validate new wrapper structure
    ↓
user enters password + mnemonic
    ↓
PasswordKeyDerivation.unwrapMasterKeyWithRecovery(...)
    ↓
validate successful 32-byte result
    ↓
install/recover authoritative MK through MasterKeyManager
    ↓
create local Password-KEK wrapper
    ↓
persist local master_key_record_v1
    ↓
register/adopt password-state device metadata
```

There is **no generation path** in this branch.

---

# L. Recovery failure behavior

### Wrong password

Recovery-KEK derivation produces the wrong key and AES-GCM authentication fails.

Result:

```text
no MK installed
```

### Wrong mnemonic

Same result.

### Both wrong

Same result.

### Tampered wrapper

If structure remains valid but the authentication tag fails, the result is indistinguishable from a wrong credential to the existing primitive.

Externally it should therefore be a generic:

```text
RECOVERY_FAILED
```

rather than exposing:

```text
wrong password
wrong mnemonic
tampered ciphertext
```

as distinct cryptographic conclusions.

### Malformed wrapper

Reject before attempting KDF/decrypt.

### Unsupported version

Reject before attempting cryptography.

### Invalid KDF parameters

Reject before invoking Argon2id.

### Truncated fields

Reject during structural/length validation.

No failed recovery path creates a replacement MK.

---

# M. Strict wrapper validation

The production adapter should perform:

```text
raw JSON
↓
duplicate-key-aware parsing
↓
object-type validation
↓
required-field validation
↓
allowed-field validation
↓
version validation
↓
KDF validation
↓
base64/length validation
↓
existing PasswordKeyDerivation unwrap
```

The current Stage 3 primitive's JSON parser cannot detect duplicate JSON object member names after Dart's normal `jsonDecode` has collapsed them.

Therefore the production artifact adapter should reject duplicate keys **before** passing the normalized object to the existing cryptographic primitive.

This is a validation hardening, not a new cryptographic protocol.

No raw wrapper contents should be logged.

---

# N. Legacy `device_key.json` migration

The legacy schema must never be interpreted as an MK wrapper.

Detection:

```text
has wrapSalt + wrapNonce + wrappedAuthSalt
and lacks new v/kdf/... structure
    → LEGACY_V1
```

The recommended compatibility policy is:

```text
explicit one-time migration
```

rather than silently overwriting it or pretending it is already an MK artifact.

### Migration

An already-authorized device:

```text
legacy repository
    ↓
validate legacy device_key.json
    ↓
generate ONE provisional MK
    ↓
create local Password/Recovery wrappers
    ↓
preserve legacy recovery artifact
    ↓
conditionally establish new device_key.json
    ↓
promote ONE winning MK
```

For the transition period, the legacy artifact should be preserved separately, for example as:

```text
device_key_legacy_v1.json
```

This is a **legacy metadata preservation artifact**, not part of the new cryptographic hierarchy.

The new application can then recover:

```text
new device_key.json
    → MK
```

and, while legacy ciphertext still exists:

```text
device_key_legacy_v1.json
    → authSalt
    → legacy system_crypto_pin
```

so existing legacy note data remains readable until its designated Stage 6 migration.

Older client compatibility with the new `device_key.json` schema must be treated as a controlled-upgrade boundary rather than assumed.

---

# O. Critical password-change boundary

Here is the remaining stage-dependency problem.

The approved architecture says:

```text
old password
    ↓
unwrap same MK
    ↓
new Password-KEK wrapper
+
new Recovery-KEK wrapper
+
new verifier
```

and explicitly says existing note ciphertext does not need re-encryption because the MK does not change.

The existing production code, however, still has:

```text
new password
    ↓
new system_crypto_pin
    ↓
migrateEncryptedNotes(oldPinHash, newPinHash)
```

This is necessary for the current legacy ciphertext because those notes were actually encrypted using the legacy password-derived value.

Therefore there are two incompatible requirements:

```text
DO NOT modify legacy note ciphertext in Stage 3
```

and:

```text
remove legacy password-dependent note migration from password change
```

They cannot both be satisfied for already-existing legacy notes.

Simply deleting `migrateEncryptedNotes()` in Stage 3 would make existing encrypted notes undecryptable after password change.

Keeping `system_crypto_pin` as a hidden legacy data key while changing the real verifier would avoid re-encryption, but would create a new persistent legacy-key architecture that is not part of the approved design and would leave old password-derived access semantics alive.

I would **not invent that mechanism**.

### Therefore

The safe transition is:

```text
Stage 3 production integration
    ↓
introduce the new MK wrapper/password/recovery layer
    +
continue legacy ciphertext compatibility
    ↓
Stage 6
    ↓
migrate legacy ciphertext to MK/NEK/TEK
    ↓
remove legacy password-derived encryption
    ↓
password change becomes pure MK rewrap
```

That means the current production call to `migrateEncryptedNotes()` cannot honestly be removed during this Stage 3 integration without either moving Stage 6 earlier or approving a new legacy-key compatibility mechanism.

This is an actual stage-boundary dependency, not an implementation preference.

---

# P. Password-change design after the prerequisite transition

Once the MK wrapper state exists, the new production password-change operation itself should be:

```text
verify old password
    ↓
unwrap local Password-KEK MK
    ↓
verify existing Recovery wrapper resolves to SAME MK
    ↓
obtain/re-enter mnemonic
    ↓
create new Password-KEK wrapper over SAME MK
    ↓
create new Recovery-KEK wrapper over SAME MK
    ↓
create new password verifier
    ↓
validate all three artifacts
    ↓
local durable commit
    ↓
remote Recovery-wrapper update
    ↓
update password-state generation using existing reconciliation
```

The invariant is:

```text
MK_before == MK_after
```

and:

```text
NEK_before == NEK_after
TEK_before == TEK_after
```

because all are functions of the same unchanged MK.

No Stage 6 ciphertext migration belongs here.

The Stage 3 primitive already follows this same-MK principle and produces both new wrappers plus the new verifier.

---

# Q. Password-change crash choreography

## Local commit fails

```text
old wrapper
old verifier
old recovery wrapper
    ↓
remain authoritative
```

Prepared new artifacts are discarded.

No notes change.

## Local commit succeeds, remote update fails

```text
new local password wrapper
new local verifier
new cached recovery wrapper
    ↓
committed locally

remote recovery wrapper
    ↓
still old
```

The operation is marked pending.

The device does not pretend GitHub is updated.

Existing `PendingReason`/password-state reconciliation machinery should be reused, but its current `CryptoEngine.wrapDeviceKeyWithParams()` call must eventually be replaced by publication of the already-prepared new Recovery-MK wrapper.

The existing architecture explicitly anticipates a pending remote device-key publication state.

## Remote update succeeds, local finalization fails

On restart:

```text
remote new wrapper
+
local pending wrapper
```

Compare them.

If they are the same new wrapper:

```text
finalize local state
```

If they differ:

```text
conflict
```

Never silently choose a different MK.

## Second password change while previous remote update is pending

Do not allow a new password rotation to overwrite the unresolved pending remote recovery state.

Require the pending state to be reconciled first.

This prevents a sequence of locally-successful rotations from making remote recovery semantics ambiguous.

---

# R. Legacy compatibility matrix

## Table D — Legacy compatibility

| Existing repository state               | Detection                                       | Behavior                                               | Security consequence                             |
| --------------------------------------- | ----------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------ |
| Legacy authSalt file                    | legacy fields present, no new `v/kdf` wrapper   | Explicit migration-assisted path                       | No legacy file is mistaken for MK                |
| New MK wrapper                          | valid `v=1`, Argon2id, wrapper fields           | Normal password+mnemonic recovery                      | Same MK recovered                                |
| Missing file                            | no `device_key.json`                            | First-device establishment if dataset is genuinely new | No blind generation when dataset already exists  |
| Malformed                               | invalid JSON/fields/types                       | Reject                                                 | No MK installed                                  |
| Unsupported                             | unsupported version/KDF                         | Reject                                                 | No cryptographic interpretation                  |
| Valid new wrapper but wrong credentials | wrapper valid, unwrap fails                     | Generic recovery failure                               | No key leakage                                   |
| Valid new wrapper for a different MK    | new wrapper does not match local expected state | Conflict/recovery                                      | Never silently replace local authoritative state |

---

# S. State machine

## Table B — State machine

| State           | MK status                                       | Local wrapper         | Remote wrapper            | Next valid transitions                     |
| --------------- | ----------------------------------------------- | --------------------- | ------------------------- | ------------------------------------------ |
| Fresh           | none                                            | absent                | absent/unknown            | Provisional                                |
| Provisional     | candidate only                                  | pending/complete      | absent or pending         | Authoritative, conflict, failed            |
| Authoritative   | one established MK                              | complete              | expected recovery wrapper | Password change, recovery/join             |
| Recovery        | no local authoritative MK until unwrap succeeds | absent/partial        | valid new wrapper         | Authoritative or failure                   |
| Password change | existing authoritative MK retained              | old → new pending     | old → new pending         | Authoritative unchanged, pending, rollback |
| Failed          | depends on point of failure                     | retained or discarded | retained or unknown       | Retry/recovery/reconciliation              |

---

# T. Failure-state matrix

## Table C — Failure matrix

| Failure point                                          | MK status                               | Durable state                   | Retry?               | Recovery action                                                                                 |
| ------------------------------------------------------ | --------------------------------------- | ------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------- |
| MK generation failure                                  | None                                    | No new record                   | Yes                  | Start fresh                                                                                     |
| Password-KEK derivation failure                        | Provisional candidate discarded         | No authoritative wrapper        | Yes                  | Generate/use same session transaction only if candidate still valid; otherwise no new authority |
| Recovery-KEK derivation failure                        | Provisional                             | No authoritative remote state   | Yes                  | Do not promote                                                                                  |
| Local serialization failure                            | Provisional discarded                   | No usable pending record        | Yes                  | Safe to generate a new candidate because remote was untouched                                   |
| Local Hive write failure before remote                 | Provisional discarded                   | No local commit                 | Yes                  | Generate new candidate only after confirming remote still absent                                |
| Remote JSON serialization failure                      | Provisional                             | Local pending wrapper may exist | Yes                  | Reuse same candidate/wrapper; never regenerate blindly                                          |
| GitHub upload failure                                  | Provisional                             | Local pending wrapper           | Yes                  | Reuse cached Recovery wrapper                                                                   |
| GitHub timeout                                         | Provisional                             | Local pending wrapper           | Yes                  | Re-read remote first; exact-match if already published                                          |
| GitHub authentication failure                          | Provisional                             | Local pending wrapper           | Yes                  | Reauthenticate; no new MK                                                                       |
| GitHub conflict                                        | Candidate discarded                     | Remote state wins               | Yes                  | Recover remote MK                                                                               |
| Remote already has legacy wrapper                      | No automatic promotion                  | Legacy state                    | Controlled migration | Do not interpret authSalt as MK                                                                 |
| Remote has new wrapper for different MK                | Local candidate discarded or conflict   | Remote authoritative candidate  | Yes                  | Recover/reconcile; never overwrite silently                                                     |
| Crash before local commit                              | No durable MK                           | Nothing new                     | Yes                  | Re-evaluate remote before generating                                                            |
| Crash after local commit, before remote                | Provisional/pending                     | Cached wrappers                 | Yes                  | Retry same Recovery wrapper                                                                     |
| Crash after remote commit, before finalization         | Remote authoritative                    | Local pending/old               | Yes                  | Recover/finalize same MK                                                                        |
| Password-change local failure                          | Existing MK remains authoritative       | Old local artifacts             | Yes                  | Discard prepared new artifacts                                                                  |
| Password-change remote failure                         | New local wrapper authoritative locally | Remote old/pending              | Yes                  | Reconcile using existing pending machinery                                                      |
| Password-change remote success, local finalize failure | Same MK                                 | Remote new + local pending/old  | Yes                  | Compare and finalize                                                                            |
| Recovery failure                                       | No MK installed                         | Existing local state unchanged  | Yes                  | Correct credentials/mnemonic                                                                    |
| Malformed recovery wrapper                             | No MK installed                         | State unchanged                 | Yes after repair     | Repair repository; never generate replacement automatically                                     |
| Wrong password                                         | No MK installed                         | State unchanged                 | Yes                  | Retry                                                                                           |
| Wrong mnemonic                                         | No MK installed                         | State unchanged                 | Yes                  | Retry                                                                                           |

---

# U. Exact legacy/current `system_crypto_pin` boundary

Current production roles:

```text
settings.dart
    → creates it
    → reads it
    → changes it
    → uses it for GitHub credential encryption

database.dart
    → uses it for legacy note encryption/decryption

settings recovery flow
    → reconstructs it from legacy authSalt

QuickNote / other legacy callers
    → pass it into CryptoEngine
```

The intended new roles are:

```text
Password Verifier
    → comparison only

Password-KEK
    → unwrap MK

Recovery-KEK
    → unwrap same MK
```

Therefore the current `system_crypto_pin` is **not yet equivalent to the approved Password Verifier**.

It must not simply be renamed and reused.

The Stage 3 production integration should introduce the new verifier inside the new MK security record while retaining the legacy credential path only for legacy ciphertext compatibility until Stage 6.

This is a compatibility state, not the final cryptographic architecture.

---

# V. Stage 4 boundary

No Stage 4 redesign is required.

Once:

```text
MasterKeyManager.state == authoritative
```

the already-approved Stage 4 primitive becomes the next layer:

```text
MasterKeyManager
    ↓
authoritative MK
    ↓
DomainKeyDerivation
    ├── rocenv2 notes
    └── rocenv2 github_token
```

`DomainKeyDerivation` must not persist NEK or TEK.

It remains a consumer of the established MK.

The existing Stage 4 derivation implementation therefore stays unchanged by this design.

---

# W. Stage 5 boundary

Stage 3 must expose only the prerequisite:

```text
authoritative MK can be legitimately established/recovered
```

Stage 3 does **not** add:

```text
SessionSecurityManager
SessionKeyMaterial
session epochs
ACTIVATING
ProviderContainer lifecycle
FLAG_SECURE
```

Stage 5 later consumes:

```text
authoritative MK
```

and takes ownership of its session lifetime.

No Stage 5 lifecycle mechanism belongs in this implementation.

---

# X. Production file impact

## Files that will eventually change

| File                                                  | Current responsibility                            | Planned Stage 3 responsibility                                                                                | Why it must change                                                                                |
| ----------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `lib/core/master_key_manager.dart`                    | MK state/generation/init                          | Expose production-safe MK transaction/installation hooks while preserving provisional/authoritative invariant | Current helper does not persist local wrappers or orchestrate the complete production transaction |
| `lib/core/password_key_derivation.dart`               | Existing Stage 3 crypto primitives                | Remain primary crypto primitive; only narrowly harden parser validation if necessary                          | Already implements required cryptography                                                          |
| `lib/core/password_state_manager.dart`                | Shared password generation/pending/reconciliation | Publish the new Recovery-MK wrapper and reuse pending/reconciliation states                                   | Current retry path rebuilds legacy authSalt wrapper                                               |
| `lib/features/settings.dart`                          | Password setup/change/GitHub recovery UI          | Call production MK integration service instead of legacy device-key/recovery wiring                           | Current production flows bypass Stage 3 primitives                                                |
| `lib/core/master_key_local_store.dart` *(new)*        | —                                                 | Persist `master_key_record_v1` in `rocen_settings_box`                                                        | No local MK wrapper state exists today                                                            |
| `lib/core/device_key_artifact.dart` *(new)*           | —                                                 | Strictly classify legacy/new remote artifacts and serialize/validate the new wrapper                          | Prevents legacy authSalt from being interpreted as MK                                             |
| `lib/core/master_key_production_service.dart` *(new)* | —                                                 | Orchestrate first-device establishment, recovery, wrapper rotation, local/remote choreography                 | Keeps settings UI from becoming the authority state machine                                       |

## Files that should **not** be changed for Stage 3 integration

| File                                  | Reason                                                                                                 |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `lib/core/domain_key_derivation.dart` | Existing Stage 4 primitive already provides the required MK→NEK/TEK operation                          |
| `lib/core/crypto_isolate.dart`        | Existing Argon2id/AES-GCM primitive is sufficient                                                      |
| `lib/core/canonical_encoding.dart`    | Stage 1 canonical encoding is already frozen                                                           |
| `lib/core/database.dart`              | Do not perform Stage 6 ciphertext migration here yet                                                   |
| `lib/core/github_backup_service.dart` | Existing conditional fast-forward APIs are sufficient; use them correctly rather than redesigning sync |
| `lib/core/crypto_engine.dart`         | Legacy path must remain available during transition; do not silently migrate ciphertext here           |
| `main.dart`                           | Stage 5/root architecture belongs later                                                                |
| Android files                         | Not part of Stage 3                                                                                    |

---

# Y. Data-migration boundary

Stage 3 may migrate:

```text
legacy device recovery metadata
legacy authentication-state representation
```

Stage 3 may establish:

```text
new MK
new Password-KEK wrapper
new Recovery-KEK wrapper
new Password Verifier
```

Stage 3 must NOT migrate:

```text
existing note ciphertext
existing token ciphertext
legacy encrypted database payloads
```

That remains Stage 6 work.

The approved architecture explicitly separates the new MK-protected data model from the future envelope/data migration stage.

---

# Z. Security invariants

The design guarantees, or is designed to guarantee:

```text
[ ] one dataset-authoritative MK
[ ] MK generated randomly, never derived from password
[ ] Password Verifier is comparison-only
[ ] Password-KEK unwrap returns same dataset MK
[ ] Recovery-KEK unwrap returns same dataset MK
[ ] wrong credentials never produce an accepted MK
[ ] legacy authSalt wrapper never treated as MK
[ ] no replacement MK generated during recovery
[ ] no plaintext MK persisted
[ ] no plaintext MK logged
[ ] provisional MK not promoted after failed authority establishment
[ ] remote conflicts cannot silently create two authorities
[ ] temporary MK copies zeroed after wrapping
[ ] Stage 4 HKDF remains unchanged
[ ] Stage 5 receives established MK
[ ] Stage 6 ciphertext migration remains outside scope
```

---

# AA. The remaining architectural blockers

There are **two genuine unresolved dependencies**.

## Blocker 1 — legacy password-change transition

The current production ciphertext is still password-derived.

Therefore:

```text
remove migrateEncryptedNotes()
```

during Stage 3

would break existing encrypted notes.

Conversely, keeping legacy password-derived decryption indefinitely conflicts with the fully separated Password-KEK/Verifier model.

The approved architecture does not specify a sanctioned transitional legacy-data-key envelope for avoiding note re-encryption.

I therefore will **not invent one**.

The decision that must be made before implementation is:

```text
A.
Keep legacy note/password migration only until Stage 6,
explicitly treating it as temporary compatibility behavior,

OR

B.
Move the Stage 6 legacy ciphertext migration earlier,

OR

C.
Explicitly approve a new transitional compatibility mechanism
for preserving the legacy data key without ciphertext migration.
```

Only A or B preserve the current approved cryptographic architecture without inventing another key-management mechanism.

## Blocker 2 — first-device authority for local-only installations

The approved Stage 2 authority model uses remote dataset establishment as the ownership boundary, while the current product permits the cryptography password to exist before GitHub backup setup.

Therefore the design still needs an explicit rule for:

```text
fresh installation
+
password configured
+
no GitHub dataset yet
```

The currently approved design does not define a separate local-only dataset-authority marker.

I will not silently invent one.

The clean existing-architecture choices are:

```text
A.
MK remains provisional until the dataset is established remotely,

or

B.
approve a local-only authority marker as an explicit extension
of the existing Stage 2 authority model.
```

This is not a cryptographic primitive problem; it is an authority/persistence-policy boundary.

---

# AB. Required implementation test plan

Before Stage 3 production integration is accepted, the following must be added.

### First-device

```text
firstDeviceGeneratesOneMK
localPasswordWrapperPersisted
remoteRecoveryWrapperPersisted
sameMKInBothWrappers
promotionOnlyAfterRemoteCommit
failedPublishDoesNotPromote
retryReusesSamePendingWrapper
```

### Recovery

```text
recoverSameMKFromRecoveryWrapper
wrongPasswordDoesNotInstallMK
wrongMnemonicDoesNotInstallMK
malformedWrapperRejected
unsupportedWrapperRejected
legacyWrapperNeverTreatedAsMK
```

### Ownership

```text
noPlaintextMKPersisted
noSecondPersistentMK
temporaryMKCopyZeroed
sameMKAcrossPasswordChange
```

### Password change

```text
passwordChangePreservesMK
passwordChangeCreatesNewPasswordWrapper
passwordChangeCreatesNewRecoveryWrapper
passwordChangeCreatesNewVerifier
oldWrappersNotAcceptedAfterCommittedRotation
remoteFailureProducesPendingState
remoteSuccessThenLocalFailureRecoversSafely
```

### Initialization races

```text
twoFirstDevicesOnlyOneMKWins
losingDeviceDiscardsProvisionalMK
losingDeviceRecoversWinningMK
ambiguousRemoteCreateNeverGeneratesSecondMK
```

### Legacy migration

```text
legacyDeviceKeyDetected
legacyDeviceKeyNotParsedAsMK
legacyArtifactPreserved
newDeviceKeyCreatedOnlyAfterExplicitMigration
legacyRecoveryPathUsesLegacyArtifactOnly
```

---

# AC. Final implementation readiness gate

```text
STAGE 3 PRODUCTION INTEGRATION DESIGN READY?

[✓] One authoritative MK lifecycle defined
[✓] First-device establishment defined for remote-backed dataset
[✓] Local Password-KEK wrapper persistence defined
[✓] Remote Recovery-KEK wrapper persistence defined
[✓] Joining-device recovery defined
[✓] Same-MK password rewrap defined
[✓] Crash/retry choreography defined
[✓] Legacy device_key.json detection defined
[✓] Legacy/new wrapper distinction defined
[✓] Tampered/malformed handling defined
[✓] Exact promotion boundary defined
[✓] Failure outcomes defined
[✓] system_crypto_pin roles identified
[✓] Stage 4 boundary defined
[✓] Stage 5 consumption boundary defined
[✓] No Stage 5 implementation included
[✓] No Stage 6 ciphertext migration included
[✓] No new core cryptographic primitive invented
[✓] Production file impact identified
[✓] Security invariants testable

[BLOCKED] Transitional behavior for legacy password-dependent
          ciphertext is not explicitly approved.

[BLOCKED] Local-only first-device authority semantics are not explicitly
          defined by the existing Stage 2 authority model.
```

The first blocker is the more fundamental one: **the current production data still depends on the password-derived legacy key, while the approved Stage 3 password-change architecture explicitly removes that dependency without migrating ciphertext.** That transition cannot be made safe by simply changing call sites.

The second blocker must also be resolved before a global future Stage 5 session can be applied uniformly to installations that have no remotely established dataset.

No production files were changed during this design review.

STAGE 3 PRODUCTION INTEGRATION DESIGN — BLOCKED

# AUDITOR

We have made the architectural decision:

# SELECTED PATH — BLOCK B

We will move the legacy ciphertext migration earlier and complete the production MK architecture now.

The application is **not currently in public users' hands**. There is no deployed user dataset that we need to preserve for backward compatibility.

Therefore:

- We do NOT need to preserve compatibility with old user installations.
- We do NOT need to design a long-lived legacy compatibility architecture.
- We do NOT need to support old public repositories indefinitely.
- We do NOT need to optimize around backward compatibility for users we do not have.
- We are explicitly willing to perform a one-time migration of the current development/test data if needed.
- A clean final cryptographic architecture is more important than preserving the current legacy ciphertext format.

However:

**Do NOT implement anything yet.**

This task is a **design-only review** for how Block B will be implemented.

Do not modify production code.

Do not migrate any data yet.

Do not begin Stage 5.

Do not invent a transitional legacy-key architecture.

---

# 1. Goal of Block B

The objective is to eliminate the legacy password-dependent data-encryption architecture and establish the intended production hierarchy:

```text
Password
    ├──→ Password Verifier
    │       └── authentication only
    │
    └──→ Password-KEK
            ↓
      Password-wrapped MK
            │
            ▼
     authoritative dataset MK
            │
            ├──→ Stage 4 HKDF → NEK
            │                      ↓
            │                   note data
            │
            └──→ Stage 4 HKDF → TEK
                                   ↓
                              GitHub token data

```

Recovery:

```text
password + recovery mnemonic
        ↓
    Recovery-KEK
        ↓
Recovery-wrapped same MK
        ↓
       MK

```

The critical invariants are:

```text
MK is random
MK is generated once
MK is never derived from password
Password Verifier cannot reconstruct MK
Password-KEK unwraps the same MK
Recovery-KEK unwraps the same MK
Password changes preserve MK
NEK/TEK are derived from MK
Legacy password-derived data encryption is removed

```

---

# 2. Important scope clarification

We are intentionally **not focusing on historical user-data migration**.

We are not asking you to design:

```text
old public release compatibility
multi-version upgrade support
legacy user recovery guarantees
long-term legacy format compatibility

```

because there are currently no public users whose data needs to be preserved.

You may assume:

```text
current repository is a controlled development/test environment

```

and we are allowed to make the clean architectural transition now.

However, you must still explain **what happens to the current legacy ciphertext during the transition** so that the implementation does not leave the codebase internally inconsistent.

The goal is to eliminate the legacy architecture, not to preserve it indefinitely.

---

# 3. Explain the exact implementation strategy

Before writing code, explain exactly how you will implement Block B.

Your design must answer:

```text
1. How is the first authoritative MK established?
2. How is the Password-KEK-wrapped MK persisted locally?
3. How is the Recovery-KEK-wrapped MK persisted remotely?
4. How is the same MK established/recovered on a joining device?
5. How is password change converted to same-MK rewrap?
6. How is the current system_crypto_pin role removed from data encryption?
7. How do existing notes move from password-derived encryption to NEK-based encryption?
8. How do existing GitHub tokens move from password-derived encryption to TEK-based encryption?
9. At what exact point does the application stop requiring the legacy encryption key?
10. At what exact point can the legacy CryptoEngine encryption path be deleted?

```

Do not provide vague architecture language.

Identify the actual production components and their interactions.

---

# 4. First-device establishment

Design the exact production flow:

```text
fresh dataset
    ↓
credential setup
    ↓
generate random MK
    ↓
Password-KEK wrap
    ↓
Recovery-KEK wrap
    ↓
persist local wrapper state
    ↓
publish remote recovery wrapper
    ↓
validate both artifacts
    ↓
promote MK authoritative

```

Explain:

- what `MasterKeyManager` does,
- what production service/adaptor does,
- where each wrapper lives,
- who owns temporary MK buffers,
- when buffers are zeroed,
- exactly what conditions allow promotion.

Do not generate MK from the password.

---

# 5. Local persistence design

Use the already-approved local security-storage location unless the actual repository proves it is impossible:

```text
rocen_settings_box

```

Define the final production record.

It should contain only what is required for:

```text
password authentication
local MK recovery
recovery-wrapper caching/state
pending remote synchronization

```

It must never contain plaintext MK.

Clearly distinguish:

```text
credential verifier
Password-KEK wrapper
Recovery-KEK wrapper
pending state
authoritative state

```

Do not create unnecessary additional secrets.

---

# 6. Remote recovery artifact

The final remote artifact must use the existing Stage 3 Recovery-KEK wrapper format.

Do not invent a second wrapper.

Conceptually:

```text
device_key.json
    ↓
existing wrapMasterKeyWithRecovery() output

```

Explain:

- exact serialization,
- version handling,
- validation,
- conflict handling,
- creation/update primitive,
- authority rules.

The old legacy `wrappedAuthSalt` structure is no longer the target architecture.

Since there are no public users, explain the clean replacement/removal strategy for the legacy artifact rather than building long-term compatibility.

---

# 7. Joining-device recovery

Design:

```text
fetch device_key.json
    ↓
validate new Recovery wrapper
    ↓
password + mnemonic
    ↓
derive Recovery-KEK
    ↓
unwrap same authoritative MK
    ↓
install MK
    ↓
create local Password-KEK wrapper
    ↓
establish local security state

```

Wrong password, wrong mnemonic, malformed artifact, unsupported version, tampering, and invalid ciphertext must never cause a new MK to be generated.

The joining device must recover the existing dataset MK.

---

# 8. Password change

The final production password-change design must be:

```text
old password
    ↓
unwrap same MK
    ↓
new Password-KEK wrapper
    +
new Recovery-KEK wrapper
    +
new Password Verifier

```

The invariant:

```text
MK_before == MK_after

```

and therefore:

```text
NEK_before == NEK_after
TEK_before == TEK_after

```

Password change must NOT require re-encrypting already-MK-encrypted notes/tokens.

Because Block B removes the old password-derived encryption architecture, explain exactly how password change transitions from the current legacy behavior to the final behavior.

---

# 9. Legacy ciphertext transition

We are deliberately choosing Block B.

We are willing to migrate current controlled data.

Design the **cleanest migration strategy**, but do not spend effort on long-term compatibility.

You do NOT need to preserve a permanent legacy-data key architecture.

You do NOT need a multi-release compatibility layer.

You do NOT need to maintain both cryptographic systems indefinitely.

Instead define:

```text
LEGACY DATA
    ↓
authenticated legacy decrypt
    ↓
plaintext
    ↓
encrypt with NEK / TEK
    ↓
new ciphertext
    ↓
verify new ciphertext
    ↓
commit replacement

```

Explain how the migration can be:

- crash-safe,
- resumable,
- idempotent,
- verifiable,
- safe against partial progress,
- safe against corrupted individual records.

Do not implement the migration yet.

The important requirement is to define the migration boundary so the codebase can eventually reach:

```text
legacy encryption code = deleted

```

rather than carrying a permanent compatibility layer.

---

# 10. Exact moment legacy crypto can be removed

Define the exact completion condition for removing:

```text
system_crypto_pin as data-encryption material
legacy CryptoEngine note encryption
legacy token encryption
legacy authSalt recovery mechanism
legacy device_key.json format

```

Do not merely say “after migration.”

Specify the precise invariant:

```text
all protected application ciphertext
    → encrypted under MK-derived domain keys

all recovery
    → recovers MK directly

all password changes
    → rewrap same MK

no production caller
    → depends on password-derived data-encryption material

```

Then state which production files can be deleted or simplified.

---

# 11. Data model after Block B

Produce the final cryptographic data model:

```text
Password Verifier
Password-KEK wrapper
Recovery-KEK wrapper
MK
NEK
TEK
note ciphertext
token ciphertext

```

For each artifact specify:

```text
owner
persistent?
authoritative?
source of truth
recovery mechanism
lifecycle

```

---

# 12. Crash-safe implementation design

This is critical.

Design crash behavior for:

```text
first-device creation
password change
joining-device recovery
note migration
token migration
remote wrapper publication
local wrapper commit

```

Especially:

```text
local commit succeeds
remote commit fails
remote commit succeeds
local finalization fails
app crashes before checkpoint
app crashes after checkpoint
individual record migration fails

```

For every case explain:

```text
what survives
what gets retried
whether retry is idempotent
what key remains authoritative
what is rolled back
what must never be deleted

```

Do not claim local + GitHub operations are atomically transactional.

Use explicit durable states/checkpoints.

---

# 13. Concurrency and split-brain protection

Design for:

```text
two devices initialize simultaneously
two password changes overlap
one device publishes recovery wrapper while another changes it
stale GitHub ref
remote artifact changed unexpectedly

```

The final architecture must never silently produce:

```text
Device A → MK-A
Device B → MK-B
both believing they own the dataset

```

Explain exactly how the existing conditional GitHub operations are used to prevent this.

---

# 14. Local-only installation

Resolve the previous Blocker 2 explicitly.

We have:

```text
fresh installation
+
password configured
+
GitHub dataset not yet established

```

Since we chose Block B, determine the cleanest behavior for this controlled-development product.

Compare the existing approved authority model against the requirement to support the current product workflow.

Do not silently invent a cryptographic primitive.

State whether:

```text
MK remains provisional

```

until remote dataset establishment, or whether the existing authority model already contains sufficient semantics for local-only establishment.

If a new authority marker is required, explicitly identify that as a Stage 2 architectural extension rather than hiding it inside Stage 3.

---

# 15. Migration scope

We are explicitly NOT asking for historical-user compatibility.

Therefore do not design:

```text
legacy public-user upgrade support
multi-version repository compatibility
indefinite dual-format reads
permanent legacy keys

```

The migration only needs to make the current controlled codebase reach the final architecture safely.

If existing local test data must be discarded instead of migrated, state that possibility explicitly rather than inventing complexity.

---

# 16. File-level design

Use the actual latest repository.

For every file that would change, provide:

```text
file
current role
new role
exact changes required
reason
security impact

```

Identify:

```text
new files
modified files
files that can eventually be deleted
files that must remain untouched

```

Pay particular attention to:

```text
lib/core/master_key_manager.dart
lib/core/password_key_derivation.dart
lib/core/password_state_manager.dart
lib/core/crypto_engine.dart
lib/core/database.dart
lib/features/settings.dart
lib/features/quicknote.dart

```

Do not assume these are the only relevant files.

---

# 17. Stage boundaries

Explicitly separate:

### Stage 3 Block B integration

Must establish:

```text
production authoritative MK
Password-KEK wrapper
Recovery-KEK wrapper
password verifier separation
joining-device MK recovery
same-MK password rewrap
controlled legacy-data migration plan
removal of password-derived data-key dependency

```

### Stage 4

Already provides:

```text
MK → HKDF → NEK/TEK

```

Do not redesign HKDF.

### Stage 5

Will later provide:

```text
session ownership
session authorization
epoch invalidation
UI/provider lifetime
lifecycle lock
FLAG_SECURE

```

Do not implement Stage 5 now.

---

# 18. Security invariants

The final Block B design must guarantee:

```text
[ ] exactly one dataset-authoritative MK
[ ] MK generated randomly
[ ] MK never derived from password
[ ] Password Verifier cannot reconstruct MK
[ ] Password-KEK unwrap returns same MK
[ ] Recovery-KEK unwrap returns same MK
[ ] password change preserves MK
[ ] device addition preserves MK
[ ] no replacement MK during recovery
[ ] legacy authSalt artifact cannot be interpreted as MK
[ ] malformed/tampered wrappers cannot install MK
[ ] two concurrent devices cannot silently create two authorities
[ ] no plaintext MK persistence
[ ] no MK logging
[ ] temporary MK buffers are zeroed where possible
[ ] all final application ciphertext uses MK-derived domain keys
[ ] system_crypto_pin is no longer used as a data-encryption key
[ ] legacy note/token encryption is removed after migration
[ ] recovery directly recovers MK
[ ] Stage 4 HKDF remains unchanged
[ ] Stage 5 consumes established MK

```

---

# 19. Required design tables

## Table A — Final artifact ownership

| ArtifactOwnerPersistent?Authoritative?Recovery source |     |     |     |     |
| ----------------------------------------------------- | --- | --- | --- | --- |
| MK                                                    | ... | ... | ... | ... |
| Password verifier                                     | ... | ... | ... | ... |
| Password-KEK wrapper                                  | ... | ... | ... | ... |
| Recovery-KEK wrapper                                  | ... | ... | ... | ... |
| NEK                                                   | ... | ... | ... | ... |
| TEK                                                   | ... | ... | ... | ... |
| Legacy data key                                       | ... | ... | ... | ... |

The final row should explicitly state that the legacy data key is temporary migration-only or removed entirely.

## Table B — Production state machine

| StateMK statusLocal wrapperRemote wrapperData statusValid transitions |     |     |     |     |     |
| --------------------------------------------------------------------- | --- | --- | --- | --- | --- |
| Fresh                                                                 | ... | ... | ... | ... | ... |
| Provisional                                                           | ... | ... | ... | ... | ... |
| Authoritative                                                         | ... | ... | ... | ... | ... |
| Migrating                                                             | ... | ... | ... | ... | ... |
| Migrated                                                              | ... | ... | ... | ... | ... |
| Failed                                                                | ... | ... | ... | ... | ... |
| Conflict                                                              | ... | ... | ... | ... | ... |

## Table C — Crash matrix

| Crash/failureDurable stateMK statusSafe retry?Recovery action |     |     |     |     |
| ------------------------------------------------------------- | --- | --- | --- | --- |
| ...                                                           | ... | ... | ... | ... |

## Table D — Legacy transition

| Legacy itemSource keyTarget keyMigration checkpointFinal state |                  |                           |     |                    |
| -------------------------------------------------------------- | ---------------- | ------------------------- | --- | ------------------ |
| Note                                                           | ...              | NEK                       | ... | MK-encrypted       |
| GitHub token                                                   | ...              | TEK                       | ... | MK-encrypted       |
| device_key.json                                                | authSalt wrapper | Recovery-MK wrapper       | ... | new recovery model |
| system_crypto_pin                                              | legacy role      | verifier/KEK architecture | ... | no data-key role   |

---

# 20. Required design decisions

Explicitly answer:

### Decision 1

Is legacy note/token migration performed as part of the same Stage 3 implementation, or as a short prerequisite migration step immediately after Stage 3 wiring?

### Decision 2

Can the current controlled test/dev data simply be reset instead of migrated where doing so produces a cleaner security transition?

### Decision 3

Exactly when is the legacy data-encryption key permanently removed?

### Decision 4

Exactly when is the old `device_key.json` authSalt format permanently removed?

### Decision 5

What exact behavior applies to fresh local-only installations before GitHub establishment?

### Decision 6

What exact condition declares the final system “fully MK-based”?

---

# 21. Explicit non-goals

Do NOT implement or design:

```text
Stage 5 session locking
Stage 5 ProviderContainer lifecycle
Stage 5 ACTIVATING
Stage 5 lifecycle handling
Stage 5 FLAG_SECURE
Stage 6+ unrelated cryptographic features
new cryptographic primitives
permanent legacy compatibility architecture
public-user migration framework

```

Do NOT invent a second legacy compatibility key architecture.

---

# 22. Deliverables

Return:

### A. Final Block B architecture

A complete end-to-end diagram.

### B. Exact production integration sequence

Numbered, concrete implementation sequence.

### C. Exact migration boundary

Explain what moves from legacy encryption to MK-derived encryption and when.

### D. Crash/recovery model

Explicit failure behavior.

### E. Authority model

Exact point where MK becomes authoritative.

### F. Legacy removal plan

Exact point each legacy cryptographic dependency can be deleted.

### G. File-level impact

Exact files and responsibilities.

### H. Test strategy

The mandatory security and correctness tests required before calling Block B complete.

### I. Stage 5 handoff contract

Exactly what Stage 5 will receive from Stage 3.

---

# 23. Final status

Do not modify production code.

End with exactly:

```text
BLOCK B PRODUCTION INTEGRATION DESIGN — READY FOR IMPLEMENTATION

```

or:

```text
BLOCK B PRODUCTION INTEGRATION DESIGN — BLOCKED

```

If blocked, identify the exact unresolved decision/dependency.

The decision to use Block B has already been made.

Do not re-open A/B/C.

Do not optimize for preserving nonexistent public-user data.

Optimize for:

```text
clean cryptographic architecture
+
single authoritative MK
+
strong crash recovery
+
minimal long-term attack surface
+
simple future Stage 5 session security
+
eventual removal of all password-derived data encryption

```

# IMPLEMENTOR

# FINAL BLOCK B PRODUCTION INTEGRATION DESIGN

## Executive decision

**Block B is the correct path.**

The latest project snapshot is now at the point where the cryptographic primitives required by the approved architecture already exist:

```text
PasswordKeyDerivation
    ├── Password Verifier
    ├── Password-KEK wrap/unwrap
    ├── Recovery-KEK wrap/unwrap
    └── same-MK password-change rewrap
```

The latest `PasswordKeyDerivation.changePassword()` already performs the important same-MK operation and refreshes both Password-KEK and Recovery-KEK wrappers. It does not generate a replacement MK.

The missing work is production integration plus the one-time removal of the legacy password-derived data-key architecture.

The final Block B policy is:

```text
legacy current development data
    ↓
one-time controlled cutover
    ↓
MK/NEK/TEK data model
    ↓
legacy crypto code removed
```

There will be **no permanent legacy compatibility layer**.

---

# A. Final Block B architecture

```text
                         PASSWORD
                            │
             ┌──────────────┴──────────────┐
             │                             │
             ▼                             ▼
     Password Verifier                Password-KEK
     authentication only                   │
                                           ▼
                               Local Password-MK Wrapper
                                           │
                                           ▼
                                    authoritative MK
                                           │
                         ┌─────────────────┴─────────────────┐
                         │                                   │
                         ▼                                   ▼
              Stage 4 HKDF / NEK                 Stage 4 HKDF / TEK
                         │                                   │
                         ▼                                   ▼
                  encrypted notes                  encrypted GitHub token


                 PASSWORD + 12-WORD MNEMONIC
                              │
                              ▼
                         Recovery-KEK
                              │
                              ▼
                    Remote Recovery-MK Wrapper
                              │
                              ▼
                       same authoritative MK
```

The fundamental invariant remains:

```text
MK
    = one random dataset key

Password-KEK
    = one independent wrapping mechanism

Recovery-KEK
    = second independent wrapping mechanism

NEK / TEK
    = deterministic children of that same MK
```

The architecture explicitly defines MK as randomly generated once and never derived from the password; the persisted forms are wrapped copies.

---

# B. One necessary Stage 2 extension: durable local authority

The current `MasterKeyManager` authority state is in memory. That is sufficient for its original session-bound design, but Block B must support the existing product behavior where a user can configure encryption before enabling GitHub.

Therefore the clean local-only rule is:

```text
fresh local dataset
    ↓
generate MK
    ↓
create both local wrappers + verifier
    ↓
durably commit master-key record
    ↓
MK becomes locally authoritative
```

This requires a **small non-cryptographic Stage 2 authority extension**:

> A complete, validated local MK security record is itself sufficient to establish dataset authority when no remote dataset has yet been associated with the installation.

This does **not** introduce a new key or cryptographic protocol.

It simply extends the existing provisional/authoritative state model so local-only operation is representable after restart.

When GitHub is configured later:

```text
local authoritative MK
    ↓
Recovery wrapper already exists locally
    ↓
conditionally publish same wrapper
```

No new MK is generated.

If another remote wrapper already exists, it is compared against the locally authoritative MK. A mismatch becomes a conflict, never silent replacement.

---

# C. First-device establishment

## Exact sequence

```text
1. User establishes cryptography password.

2. Generate 128-bit recovery mnemonic entropy using the
   existing mnemonic generation mechanism.

3. Generate one random 256-bit MK using MasterKeyManager.

4. MasterKeyManager state = PROVISIONAL.

5. Create Password Verifier from the raw password.

6. Obtain a temporary defensive MK copy.

7. Create Password-KEK wrapper over MK using:
       PasswordKeyDerivation.wrapMasterKeyWithPassword()

8. Create Recovery-KEK wrapper over the SAME MK using:
       PasswordKeyDerivation.wrapMasterKeyWithRecovery()

9. Validate both wrapper artifacts:
       Password wrapper → unwrap → MK-A
       Recovery wrapper → unwrap → MK-B
       constant-time compare MK-A == MK-B == provisional MK

10. Zero every temporary plaintext MK buffer.

11. Persist the complete local security record.

12. Read the record back and structurally validate it.

13. Promote the provisional MK to AUTHORITATIVE.

14. If GitHub is already configured:
       conditionally publish the Recovery wrapper.

15. Read back the remote artifact and validate that it
    unwraps to the SAME MK.

16. Mark remote recovery state as published.

17. Initialize/join password_state.json.

```

The existing `MasterKeyManager.generateProvisionalMasterKey()` and `promoteProvisionalToAuthoritative()` remain the authority-state mechanisms. They should not be bypassed.

## Important ordering

Local authority is established only after the complete local wrapper record has been durably committed.

Therefore:

```text
MK generated
≠ authoritative

wrappers generated
≠ authoritative

remote wrapper generated
≠ authoritative
```

The authority boundary is:

```text
validated local security record committed
→ promote provisional MK
```

for a fresh local-only dataset.

Remote publication then establishes the dataset's recovery representation without replacing that MK.

---

# D. Buffer ownership

During first-device setup:

```text
MasterKeyManager
    → owns provisional MK

temporary wrapper buffer
    → caller-owned

PasswordKeyDerivation
    → receives caller-owned copy

wrapper result
    → ciphertext string, no plaintext MK

temporary plaintext copy
    → zero immediately after use
```

The production integration must never retain:

```text
Uint8List
```

provided by another component as authoritative key storage.

After authority:

```text
MasterKeyManager
    → authoritative in-memory MK for this pre-Stage-5 implementation
```

and later Stage 5 will transfer session ownership into its session key owner.

No provider owns MK.

No Hive record owns plaintext MK.

No GitHub file contains plaintext MK.

---

# E. Local Password-KEK wrapper persistence

Use:

```text
rocen_settings_box
```

as the approved location.

The final local logical record should be:

```json
{
  "schema": 1,
  "authority": "authoritative",
  "passwordVerifier": "...",
  "passwordWrap": "{existing Stage 3 wrap JSON}",
  "recoveryWrap": "{existing Stage 3 recovery wrap JSON}",
  "remoteRecovery": {
    "status": "unpublished|published|conflict",
    "repository": "..."
  }
}
```

Store this as one serialized value under a dedicated key, rather than scattering the cryptographic state over unrelated keys.

Suggested logical key:

```text
master_key_record_v1
```

This is storage metadata, not a cryptographic envelope.

## Fields

### `passwordVerifier`

Existing Stage 3 verifier record:

```text
base64(saltVerifier):base64(hash)
```

authentication only.

### `passwordWrap`

The exact JSON produced by:

```text
PasswordKeyDerivation.wrapMasterKeyWithPassword()
```

No second wrapper format.

### `recoveryWrap`

The exact JSON produced by:

```text
PasswordKeyDerivation.wrapMasterKeyWithRecovery()
```

This gives the installation a local cached Recovery-KEK wrapper without storing the mnemonic.

### `authority`

Must be:

```text
authoritative
```

only after the local security record has been fully committed and verified.

### `remoteRecovery.status`

Used only for distributed persistence bookkeeping:

```text
unpublished
published
conflict
```

No secret data.

---

# F. Local record validity states

The loader must distinguish:

```text
MISSING
VALID
MALFORMED
UNSUPPORTED
```

### Missing

No new MK security state exists.

For a completely fresh installation:

```text
start first-device establishment
```

### Valid

All required fields exist and the embedded wrapper structures are valid.

Then:

```text
unwrap local Password wrapper
→ authoritative MK
```

### Malformed

Record exists but structure is invalid.

Never generate a replacement MK merely because the record is malformed.

If remote state exists, recover from the remote wrapper instead.

### Unsupported

Schema version is unknown.

Stop and require a controlled application upgrade/reset.

No cryptographic interpretation is attempted.

---

# G. Remote Recovery artifact

The final `device_key.json` is simply:

```text
PasswordKeyDerivation.wrapMasterKeyWithRecovery(...)
```

serialized as JSON.

No additional cryptographic wrapper is needed.

Example logical representation:

```json
{
  "v": 1,
  "kdf": "argon2id",
  "memory": 65536,
  "iterations": 3,
  "salt": "...",
  "nonce": "...",
  "ct": "...",
  "mac": "..."
}
```

This reuses the existing Stage 3 wrapper format.

The old:

```json
{
  "wrapSalt": "...",
  "wrapNonce": "...",
  "wrappedAuthSalt": "..."
}
```

is not valid new-format data.

---

# H. Remote artifact authority rules

## First-device remote bootstrap

When local MK is already authoritative:

```text
fetch device_key.json
```

### Missing

```text
conditional create with local Recovery wrapper
```

### Existing new-format wrapper

Unwrap it with:

```text
password + mnemonic
```

and compare the recovered MK with the local authoritative MK.

Two cases:

```text
same MK
→ adopt/confirm remote wrapper

different MK
→ REMOTE_DATASET_CONFLICT
```

Never overwrite an existing new-format wrapper just because the local device has a different MK.

### GitHub conflict

The existing conditional create operation must remain the authority race protection.

One device wins.

Every other device must recover or report conflict.

This prevents:

```text
Device A → MK-A
Device B → MK-B
```

from silently becoming one repository's two keys.

---

# I. Joining-device recovery

The final sequence is:

```text
1. User selects an existing repository.

2. Fetch device_key.json.

3. Strictly recognize the new Recovery-MK wrapper format.

4. User supplies:
       password
       12-word mnemonic

5. PasswordKeyDerivation.unwrapMasterKeyWithRecovery()

6. If unwrap fails:
       no MK installed
       no replacement MK generated

7. Validate returned length = 32 bytes.

8. Create local Password-KEK wrapper over the recovered MK.

9. Cache the Recovery wrapper locally.

10. Create local Password Verifier.

11. Persist the complete local record.

12. Validate local record.

13. Install/recover the authoritative MK.

14. Join password_state.json using the existing device-registration flow.
```

The recovered key is the existing dataset MK.

It is never regenerated.

---

# J. Recovery failure model

| Situation                       | Result                                           |
| ------------------------------- | ------------------------------------------------ |
| Wrong password                  | Recovery unwrap fails; no MK                     |
| Wrong mnemonic                  | Recovery unwrap fails; no MK                     |
| Both wrong                      | Recovery unwrap fails; no MK                     |
| Tampered wrapper                | AEAD authentication fails; no MK                 |
| Malformed JSON                  | reject before crypto                             |
| Unsupported wrapper version     | reject before crypto                             |
| Invalid KDF parameters          | reject before Argon2                             |
| Truncated ciphertext/tag        | reject/fail authentication                       |
| Unexpected fields               | reject as malformed                              |
| Legacy authSalt wrapper         | never interpreted as MK                          |
| New wrapper for another dataset | conflict; never silently replace local authority |

Externally, wrong credentials and cryptographic tampering do not need to be distinguished to the user.

Do not expose cryptographic parser details through logs or user-facing strings.

---

# K. Legacy `device_key.json` removal

Because the application has no public users, the final policy is:

```text
legacy device_key.json
    → controlled development transition only
    → then deleted permanently
```

We do **not** build a long-term parser or recovery path for it.

For the current development repository, the cleanest procedure is:

```text
controlled repository reset
    ↓
remove legacy device_key.json
    ↓
remove/reset legacy password_state metadata
    ↓
establish new MK architecture
    ↓
publish new device_key.json
```

If the current development repository needs to preserve its existing data, the controlled local migration described below is performed first, then the remote repository is reseeded from the migrated local dataset.

This avoids adding an indefinite legacy-repository compatibility subsystem.

---

# L. Password change

The latest Stage 3 primitive already implements the desired cryptographic operation:

```text
old Password wrapper
    ↓
unwrap MK

old Recovery wrapper
    ↓
unwrap MK

compare:
    MK-A == MK-B

then:

new Password wrapper
+
new Recovery wrapper
+
new Password verifier
```

No MK generation.

No note encryption.

No token encryption.

No NEK/TEK change.

Because:

```text
NEK = HKDF(MK, notes)
TEK = HKDF(MK, github_token)
```

unchanged MK means unchanged NEK and TEK.

---

# M. Production password-change choreography

```text
1. Read current authoritative local MK.

2. Obtain old password and new password.

3. Require mnemonic re-entry.

4. Read current Password wrapper and Recovery wrapper.

5. PasswordKeyDerivation.changePassword()

6. Validate returned artifacts.

7. Persist new local security record.

8. Verify local read-back.

9. Mark remote recovery update pending.

10. Publish new device_key.json + password-state generation.

11. Confirm remote state.

12. Clear pending state after confirmation.
```

The local commit happens before the remote side effect so a network failure does not invalidate the user's local password.

The remote update is separately reconciled.

This remains a distributed persistence operation, not an atomic transaction.

---

# N. Remote password-change concurrency

The current `GithubBackupService` has a useful `updateFileWithFastForwardCheck()`, but it updates only one file.

For Block B password rotation, the Recovery wrapper and password-state generation must advance together.

Therefore add one persistence-only primitive:

```text
updateFilesWithFastForwardCheck()
```

It should:

```text
fetch current branch SHA
    ↓
verify expected parent SHA
    ↓
create tree containing all updated files
    ↓
create commit with current SHA as parent
    ↓
update branch reference with force = false
```

For password rotation the commit contains:

```text
device_key.json
password_state.json
```

in the same Git commit.

This prevents a remote state where:

```text
new password generation
+
old Recovery wrapper
```

are independently committed.

The existing `amendSync()` force-push behavior must not be used for this authority-sensitive operation.

---

# O. Local/remote crash choreography

## First-device creation

### Local commit succeeds, remote publish never happens

```text
local MK = authoritative
remoteRecovery = unpublished
```

Restart:

```text
load same local MK
reuse same Recovery wrapper
retry remote publication
```

No new MK.

### Remote publish succeeds, local finalization crashes

On restart:

```text
remote new wrapper exists
local old/pending state detected
```

If there is no local authoritative record, recover from remote.

If local authoritative MK exists, unwrap remote wrapper and verify equality.

No new MK.

### Remote create conflicts

The local candidate is not promoted on the remote race path unless the local record has already established local authority.

The remote existing wrapper determines whether this is:

```text
same-MK confirmation
```

or:

```text
different-MK conflict
```

---

# P. Password-change crash choreography

### New local wrapper creation fails

```text
old local record remains authoritative
```

Prepared new wrapper material is discarded.

### Local commit succeeds, remote update fails

```text
new local password wrapper
new local verifier
new cached Recovery wrapper
remote old Recovery wrapper
```

State:

```text
remoteRecovery = pending
```

Retry later.

The same MK remains authoritative.

### Remote update succeeds, local finalization crashes

On restart:

```text
fetch remote device_key.json
fetch password_state.json
```

If the remote wrapper/state corresponds to the intended new generation:

```text
finalize local state
```

The old local MK remains the same.

### Another device changed password first

The branch/ref or password-generation check detects the conflict.

Do not silently overwrite the newer remote Recovery wrapper.

Existing password-state reconciliation remains the distributed-consistency mechanism.

---

# Q. Block B legacy data cutover

This is the point where Block B necessarily introduces a raw-key AEAD **adapter**, but does not invent a new cryptographic primitive.

The existing Stage 4 `DomainKeyDerivation` already supplies:

```text
MK → NEK
MK → TEK
```

The current `CryptoEngine` only exposes password-derived AES-GCM operations.

Therefore the missing integration capability is:

```text
raw 256-bit key
    +
fresh AES-GCM nonce
    ↓
existing AES-GCM primitive
```

This should be implemented as a small application-data adapter using the existing `package:cryptography` AES-GCM primitive.

It is **not** a new KDF, key hierarchy, or cryptographic primitive.

It is also intentionally **not** the later Stage 6 AAD/envelope design.

---

# R. Block B data-cutover representation

Use a minimal key-domain ciphertext representation:

```text
version
nonce
mac
ciphertext
```

For local encrypted note content, store a Base64-encoded binary package:

```text
[version=1][12-byte nonce][16-byte MAC][ciphertext]
```

For local GitHub-token storage, use the same keyed representation with the token domain selected by the calling API.

The key domain is determined by the API:

```text
notes → NEK
github token → TEK
```

There is no password KDF in this format.

There is no AAD yet.

There is no KDF metadata.

Those remain Stage 6 concerns.

The representation exists only to accomplish the approved Block B key cutover.

---

# S. Local note migration

A controlled one-time migration utility is preferable to permanently shipping a legacy reader.

For each:

```text
type == encrypted_note
```

perform:

```text
legacy ciphertext
    ↓
legacy CryptoEngine decrypt
    ↓
plaintext
    ↓
NEK AES-GCM encrypt
    ↓
new keyed ciphertext
    ↓
NEK decrypt verification
    ↓
compare plaintext
    ↓
replace record
```

Non-encrypted notes remain:

```text
type == note
```

and are untouched.

## Checkpointing

Because this is controlled migration, use a durable migration record:

```text
migration_schema = 1
status = pending | complete
lastCompletedItemId
```

The tool processes one note at a time:

```text
decrypt
→ encrypt
→ verify
→ write replacement
→ checkpoint
```

A crash before the checkpoint causes that record to be retried.

A crash after the checkpoint causes the record to be skipped.

The operation is therefore resumable and idempotent.

After every successful migration record:

```text
legacy plaintext temporary buffer
→ zero where mutable
```

Do not retain all plaintext notes in one in-memory collection.

---

# T. Remote note migration policy

Because there are no public users, **do not build a permanent remote legacy-note migration protocol**.

The cleanest controlled transition is:

```text
1. Migrate local development notes if they are worth preserving.

2. Reset/remove the controlled development repository's
   legacy note backup files.

3. Create the new device_key.json.

4. Initialize new password_state.json.

5. Re-publish the migrated local notes using NEK.

6. Verify each uploaded note by fetching and decrypting it
   using NEK before considering its migration complete.
```

This avoids introducing a second production migration protocol for remote legacy objects.

The remote repository is therefore clean after the cutover:

```text
no legacy encrypted notes
no legacy device_key.json
no legacy password-derived token blobs
```

---

# U. GitHub token migration

The existing local token record is:

```text
github_access_encrypted
```

and currently uses the legacy password-derived path, optionally wrapped by the existing hardware layer.

For Block B, the clean production cutover should be:

```text
read legacy token blob
    ↓
authenticate/decrypt under legacy credential
    ↓
extract token + repository
    ↓
encrypt token payload with TEK
    ↓
verify TEK decrypt
    ↓
store new token blob
```

The hardware PIN/token wrapper is not carried forward because hardware-MK wrapping belongs to the later hardware stage.

A controlled implementation may alternatively require token re-entry; because there are no public users, that is an acceptable simplification for development data. The production architecture itself requires only that the final stored token be TEK-protected.

---

# V. Exact legacy-encryption removal boundary

The old password-derived architecture can be deleted only after these conditions are simultaneously true:

```text
[1] Every encrypted local note has the new NEK ciphertext form.

[2] Every encrypted remote note that is retained has the new
    NEK representation.

[3] GitHub token storage is TEK-protected.

[4] New note writes use NEK.

[5] New token writes use TEK.

[6] Note decryption no longer reads system_crypto_pin.

[7] Token decryption no longer reads system_crypto_pin.

[8] Password verification uses PasswordKeyDerivation verifier.

[9] Password change uses same-MK wrapper rekeying.

[10] Recovery unwraps MK directly.

[11] No production caller depends on password-derived data-key material.

[12] No production caller uses legacy device_key.json recovery.

[13] Legacy development data migration is marked complete or
     controlled data has been reset.

[14] New recovery device_key.json has been verified.

[15] New password_state.json is associated with the new recovery artifact.
```

Only then delete the legacy data-encryption implementation.

---

# W. Legacy code that becomes deletable

After the cutover is verified, these legacy responsibilities can be removed.

## `CryptoEngine`

Delete or retire production uses of:

```text
encryptProcess
encryptProcessWithParams
decryptProcess
decryptProcessWithParams
hashPin
hashPinWithSalt
hashPinWithSaltUsingParams
verifyPin
extractAuthSalt
wrapDeviceKey
wrapDeviceKeyWithParams
unwrapDeviceKey
verifyPinWithHardwareBinding
```

`splitForBackup()` / `mergeFromBackup()` can also be removed once the new remote note format no longer uses the legacy layout.

Hardware wrappers for password/token blobs are also not part of the final Block B architecture; the later hardware-MK stage will have its own integration.

## `database.dart`

Delete:

```text
migrateEncryptedNotes(...)
```

after the controlled cutover is complete.

Replace legacy encrypted-note write/decrypt callers with the NEK data adapter.

## `settings.dart`

Remove:

```text
system_crypto_pin
last_active_crypto_pin_snapshot
hw_wrapped_pin
legacy device_key authSalt recovery
legacy note re-encryption during password change
```

and replace them with:

```text
master_key_record_v1
PasswordKeyDerivation
MasterKeyManager
Recovery wrapper handling
same-MK password change
```

## `password_state_manager.dart`

Remove the legacy:

```text
currentPinHash
extractAuthSalt
wrapDeviceKeyWithParams
```

dependency.

The pending recovery-publication state should refer to the new Recovery-MK wrapper.

---

# X. Final artifact ownership

## Table A — Final artifact ownership

| Artifact             | Owner                                              |              Persistent? |          Authoritative? | Recovery source                                        |
| -------------------- | -------------------------------------------------- | -----------------------: | ----------------------: | ------------------------------------------------------ |
| MK                   | `MasterKeyManager` until Stage 5 session ownership | No plaintext persistence |                     Yes | Password wrapper or Recovery wrapper                   |
| Password verifier    | local security record                              |                      Yes |                      No | Password comparison                                    |
| Password-KEK wrapper | local security record                              |                      Yes |                      No | Password                                               |
| Recovery-KEK wrapper | local security record + `device_key.json`          |                      Yes |                      No | Password + mnemonic                                    |
| NEK                  | `DomainKeyDerivation` caller while in use          |                       No | No persistent authority | Re-derived from MK                                     |
| TEK                  | `DomainKeyDerivation` caller while in use          |                       No | No persistent authority | Re-derived from MK                                     |
| Legacy data key      | migration utility only                             |                Temporary |                      No | Existing `system_crypto_pin` during controlled cutover |

After cutover:

```text
Legacy data key
    → removed entirely
```

---

# Y. Production state machine

## Table B — Production state machine

| State         | MK status                                    | Local wrapper     | Remote wrapper                         | Data status                                  | Valid transitions                            |
| ------------- | -------------------------------------------- | ----------------- | -------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| Fresh         | None                                         | Missing           | Missing/unknown                        | Legacy or empty                              | Provisional                                  |
| Provisional   | Random candidate                             | Pending creation  | None/pending                           | Legacy/empty                                 | Authoritative or Failed                      |
| Authoritative | One dataset MK                               | Complete          | Missing/published                      | New or migrating                             | Migrating, Password Change, Remote Bootstrap |
| Migrating     | Same MK                                      | Complete          | New/being reseeded                     | Legacy → new                                 | Migrated or Failed                           |
| Migrated      | Same MK                                      | Complete          | New                                    | All retained protected data keyed by NEK/TEK | Normal operation                             |
| Failed        | Previous valid state retained where possible | Old valid record  | Old valid state                        | Previous data unchanged                      | Retry                                        |
| Conflict      | Existing MK protected                        | Valid local state | Different authoritative remote wrapper | Not altered                                  | Recovery/reconciliation                      |

---

# Z. Legacy transition

## Table D — Legacy transition

| Legacy item                    | Source key                         | Target key                 | Migration checkpoint                  | Final state                         |
| ------------------------------ | ---------------------------------- | -------------------------- | ------------------------------------- | ----------------------------------- |
| Local encrypted note           | legacy password-derived ciphertext | NEK                        | per-record migration marker           | NEK ciphertext                      |
| Remote development note backup | legacy password-derived ciphertext | NEK                        | controlled reseed/remote verification | NEK ciphertext                      |
| GitHub token                   | legacy password-derived ciphertext | TEK                        | token verification checkpoint         | TEK ciphertext                      |
| `device_key.json`              | authSalt wrapper                   | Recovery-KEK wrapper of MK | remote artifact verification          | Recovery-MK wrapper                 |
| `system_crypto_pin`            | legacy verifier + data key         | Password Verifier          | security-record verification          | verifier only, then old key deleted |
| `hw_wrapped_pin`               | hardware-wrapped legacy credential | none                       | not carried forward                   | removed                             |
| `migrateEncryptedNotes()`      | legacy password rotation           | none                       | cutover completion                    | deleted                             |

---

# AA. Crash matrix

## Table C — Crash matrix

| Crash/failure                                           | Durable state                                    | MK status                                        |             Safe retry? | Recovery action                              |
| ------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------ | ----------------------: | -------------------------------------------- |
| MK generation fails                                     | No new record                                    | None                                             |                     Yes | Restart fresh                                |
| Password wrapper fails                                  | No authority                                     | Provisional candidate discarded                  |                     Yes | Generate new candidate                       |
| Recovery wrapper fails                                  | No authority                                     | Provisional candidate discarded                  |                     Yes | Generate new candidate                       |
| Local record commit fails                               | No authoritative record                          | Candidate discarded                              |                     Yes | Fresh establishment                          |
| Local record commits                                    | Complete local record                            | Authoritative                                    |                     Yes | Continue remote bootstrap later              |
| Remote create fails                                     | Local authoritative                              | Authoritative                                    |                     Yes | Reuse same Recovery wrapper                  |
| Remote create succeeds, local finalization crashes      | Remote new wrapper                               | Recoverable/authoritative depending local record |                     Yes | Re-read remote and validate against local MK |
| Remote artifact differs from local MK                   | Local authoritative                              | Authoritative locally                            |  No automatic overwrite | Report dataset conflict                      |
| Password change preparation fails                       | Old record                                       | Old MK authoritative                             |                     Yes | Keep old password state                      |
| Password change local commit fails                      | Old record                                       | Old MK authoritative                             |                     Yes | Retry                                        |
| Password change remote update fails                     | New local record                                 | Same MK authoritative                            |                     Yes | Pending remote reconciliation                |
| Remote password update succeeds, local finalize crashes | Remote new state                                 | Same MK                                          |                     Yes | Reconcile on restart                         |
| Note migration record fails                             | Prior checkpoint                                 | Same MK                                          |                     Yes | Retry only failed record                     |
| App crashes after note checkpoint                       | Migrated records retained                        | Same MK                                          |                     Yes | Continue from checkpoint                     |
| Token migration fails                                   | Legacy token retained until verified replacement | Same MK                                          |                     Yes | Retry/re-enter token                         |
| Recovery wrapper malformed                              | No MK installed                                  | None                                             |        Yes after repair | Do not generate replacement MK               |
| Recovery wrapper tampered                               | No MK installed                                  | None                                             | Yes with valid artifact | Do not generate replacement MK               |
| Wrong recovery password                                 | No MK installed                                  | None                                             |                     Yes | Retry                                        |
| Wrong mnemonic                                          | No MK installed                                  | None                                             |                     Yes | Retry                                        |

---

# AB. Local/remote consistency rule

The most important persistence rule is:

```text
Cryptographic correctness
    ≠
distributed persistence atomicity
```

The application must never claim that a local Hive write and GitHub write are one transaction.

The durable state model instead guarantees:

```text
local MK remains stable
remote wrapper may temporarily be pending
retry is deterministic
remote authority is checked before overwrite
```

Because the MK itself never changes during ordinary password rotation, distributed failure does not create a second dataset key.

---

# AC. Concurrency and split-brain

## Two fresh devices

Device A:

```text
MK-A local
→ remote create wins
```

Device B:

```text
MK-B local
→ remote create conflict
```

Device B must not overwrite the remote wrapper.

It must enter conflict handling.

If Device B instead has no established local dataset and is joining the repository:

```text
recover remote MK-A
→ local authority becomes MK-A
```

Therefore:

```text
one repository
→ one MK
```

---

## Two password changes

Since both devices already possess the same MK:

```text
Device A
    MK unchanged
    new Password wrapper A

Device B
    MK unchanged
    new Password wrapper B
```

Only one remote Recovery wrapper can become current.

The remote branch/ref CAS chooses one update.

The losing device gets an explicit reconciliation state.

It must never silently overwrite the winning wrapper.

---

## Stale remote ref

`updateFilesWithFastForwardCheck()` must reject when:

```text
expectedParentSha != currentRefSha
```

No retry may blindly reuse the stale parent.

The caller re-reads:

```text device_key.json
password_state.json
branch SHA
```

before deciding whether the operation is still valid.

---

# AD. Local-only installation

The final behavior is:

```text
fresh install
+
password configured
+
GitHub not configured
```

→ create one local authoritative MK.

Sequence:

```text
MK
↓
Password wrapper
+
Recovery wrapper
+
Verifier
↓
local authoritative record
↓
MK authoritative
```

The recovery mnemonic is displayed to the user, but never stored.

Later:

```text
GitHub configured
↓
publish the already-existing Recovery wrapper
```

No new MK is generated.

If a remote repository already contains another new-format Recovery wrapper:

```text
unwrap remote MK
compare with local MK
```

and either:

```text
same → associate repository
different → conflict
```

This is the necessary small Stage 2 authority extension identified earlier.

---

# AE. Migration decision

### Decision 1

**Legacy note/token migration is a one-time controlled cutover, not permanent runtime compatibility.**

For this project the cleanest production strategy is:

```text
controlled migration/reset
→ new architecture
→ legacy code deleted
```

No long-lived dual reader/writer exists.

### Decision 2

**Yes, current controlled development data may be reset.**

Because there are no public users, deleting the current development GitHub repository contents and reseeding from the migrated local dataset is preferable to building remote legacy compatibility.

### Decision 3

The legacy data-encryption key is permanently removed immediately after:

```text
all retained protected data
→ verified NEK/TEK encryption

and

no production caller
→ reads/writes it
```

### Decision 4

The legacy `device_key.json` authSalt format is permanently removed during the same cutover.

The final remote artifact is the Stage 3 Recovery-MK wrapper.

### Decision 5

Fresh local-only installations establish authority locally after the complete local MK security record is committed.

This requires the small Stage 2 durable-authority extension described above.

### Decision 6

The system is “fully MK-based” when:

```text
every protected ciphertext
    → NEK or TEK

recovery
    → directly recovers MK

password changes
    → rewrap same MK

no production data encryption
    → depends on system_crypto_pin

legacy device-key recovery
    → deleted
```

---

# AF. Exact implementation sequence

When this design is approved for implementation, the work should occur in this order:

```text
1. Add the small Stage 2 durable-local-authority extension.

2. Add local Master-Key security record persistence.

3. Add production Master-Key integration service.

4. Wire first-device establishment:
       MK
       verifier
       Password wrapper
       Recovery wrapper

5. Wire local-only authority establishment.

6. Wire new-format device_key.json publication.

7. Wire joining-device Recovery-KEK MK recovery.

8. Add multi-file fast-forward GitHub commit support.

9. Replace production password-change orchestration with
   PasswordKeyDerivation.changePassword().

10. Add the controlled Block B local data migration utility.

11. Migrate controlled development encrypted notes to NEK.

12. Convert/re-enter stored GitHub credentials and protect with TEK.

13. Reset/reseed the controlled development GitHub repository.

14. Replace production note encryption/decryption with NEK.

15. Replace production token encryption/decryption with TEK.

16. Verify all retained local/remote ciphertext.

17. Delete legacy system_crypto_pin data-key dependencies.

18. Delete legacy device-key authSalt recovery.

19. Delete legacy CryptoEngine password-encryption APIs.

20. Delete database.migrateEncryptedNotes().

21. Remove legacy migration flags/checkpoints after final validation.

22. Run the repository-wide ownership and caller audit.

23. Run the full Block B regression suite.

24. Freeze the resulting production MK architecture.

25. Only then resume Stage 5.
```

---

# AG. File-level impact

| File                                               | Current role                                                  | New role                                                     | Exact required change                                                                              | Security impact                        |
| -------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `core/master_key_manager.dart`                     | MK generation/authority/in-memory state                       | Same, plus local-authority-compatible production integration | Add production-safe provisional MK copy/installation hooks and durable-authority startup semantics | Preserves one-MK invariant             |
| `core/password_key_derivation.dart`                | Stage 3 crypto primitives                                     | Primary password/recovery wrapper primitive                  | Keep existing algorithms; expose/validate production integration cleanly                           | No crypto redesign                     |
| `core/domain_key_derivation.dart`                  | Stage 4 MK→NEK/TEK                                            | Existing child-key primitive                                 | Keep HKDF exactly unchanged                                                                        | Preserves frozen Stage 4               |
| `core/password_state_manager.dart`                 | Password generation/device registry + legacy device-key retry | Shared remote password-state reconciliation                  | Remove authSalt wrapping; make pending state refer to Recovery-MK wrapper publication              | Prevents stale recovery metadata       |
| `core/github_backup_service.dart`                  | GitHub read/write primitives                                  | Add secure multi-file CAS commit                             | Add `updateFilesWithFastForwardCheck()` using non-force ref update                                 | Prevents concurrent metadata overwrite |
| `core/database.dart`                               | Local capture state + legacy password migration               | NEK-backed note persistence                                  | Replace legacy encryption callers; remove `migrateEncryptedNotes()` after cutover                  | Removes password-derived data key      |
| `features/settings.dart`                           | Password setup/change, token setup, recovery                  | Production MK setup/recovery/password rewrap UI              | Replace legacy flows with Stage 3 production service                                               | Removes legacy security architecture   |
| `features/quicknote.dart`                          | Note encryption/decryption + GitHub backup                    | NEK-backed notes + existing backup behavior                  | Replace system_crypto_pin crypto calls with NEK; remove legacy key reads                           | Removes direct PIN-derived encryption  |
| `core/crypto_engine.dart`                          | Legacy KDF/encryption/device-key/hardware wrappers            | Reduced legacy-free utility surface                          | Delete legacy password-encryption/recovery methods after cutover                                   | Shrinks attack surface                 |
| `main.dart`                                        | App composition                                               | No Stage 3 role change                                       | Leave session architecture for Stage 5                                                             | Avoids Stage leakage                   |
| `navbar.dart`                                      | Current navigation widgets                                    | No Block B cryptographic role                                | Leave unchanged in Block B                                                                         | Avoids Stage 5 root changes            |
| `features/bookmarks.dart`                          | To-do data                                                    | No cryptographic role change                                 | Leave unless migration touches provider initialization                                             | Keeps scope controlled                 |
| `features/clipboard.dart`                          | Media clipboard                                               | No Block B cryptographic role                                | Leave untouched                                                                                    | Avoids unrelated behavior              |
| `core/debug_log.dart` + security-sensitive callers | Diagnostic logging                                            | Non-secret diagnostics only                                  | Remove secret-bearing diagnostic strings touched by Block B                                        | Prevents secret leakage                |
| `tool/*` new                                       | —                                                             | Controlled one-time migration                                | Optional non-shipped cutover utility                                                               | Avoids permanent legacy compatibility  |

---

# AH. Files that must remain outside Block B scope

Do not modify for this integration unless a concrete dependency appears:

```text
Stage 5:
    SessionSecurityManager
    session_key_material
    lifecycle gate
    ProviderContainer session boundary
    FLAG_SECURE

Stage 6:
    final envelope v2
    AAD redesign
    full key-versioned ciphertext protocol
    unrelated format migration beyond the controlled Block B key cutover

Stage hardware:
    hardware-backed MK wrapping architecture
```

The Stage 4 HKDF parameters and domain strings are frozen and remain unchanged.

---

# AI. Mandatory Block B test strategy

## First-device

```text
firstDeviceGeneratesOneMK
localPasswordWrapperRoundTrip
localRecoveryWrapperRoundTrip
sameMKAcrossBothWrappers
promotionOnlyAfterLocalCommit
remoteWrapperConfirmsSameMK
localOnlyDatasetEstablishesAuthority
```

## Recovery

```text
recoverSameMKFromRemoteWrapper
wrongPasswordDoesNotInstallMK
wrongMnemonicDoesNotInstallMK
bothWrongDoesNotInstallMK
malformedWrapperRejected
unsupportedWrapperRejected
tamperedWrapperRejected
legacyAuthSaltWrapperCannotBeParsedAsMK
```

## Ownership

```text
noPlaintextMKPersisted
noSecondPersistentMK
temporaryMKCopiesZeroed
```

## Password change

```text
passwordChangePreservesMK
passwordChangePreservesNEK
passwordChangePreservesTEK
newPasswordWrapperValid
newRecoveryWrapperValid
newVerifierValid
oldWrapperNotActive
noNoteReencryptionDuringFinalPasswordChange
```

## Concurrency

```text
twoDevicesOneRemoteMKWins
losingDeviceDoesNotOverwriteRemote
differentLocalMKProducesConflict
sameLocalMKAssociatesExistingRemote
staleRemoteRefRejected
concurrentPasswordChangeConflictDetected
```

## Migration

```text
legacyNoteDecryptsWithControlledLegacyPath
migratedNoteDecryptsWithNEK
migratedNotePlaintextMatchesOriginal
migrationCheckpointResumes
alreadyMigratedRecordIsIdempotent
oneCorruptLegacyRecordDoesNotCorruptOthers
tokenMigratesToTEK
```

## Final removal

Repository scan must prove:

```text
no production system_crypto_pin data-key caller
no production legacy encrypt/decrypt caller
no production legacy device-key recovery caller
no production migrateEncryptedNotes caller
no production PasswordKeyDerivation bypass
no production MK regeneration during recovery
```

---

# AJ. Stage 5 handoff contract

When Block B is complete, Stage 5 receives exactly this conceptual contract:

```text
DatasetKeyService
    ↓
establishOrRecoverAuthoritativeMK(...)
    ↓
authoritative 32-byte dataset MK
```

and:

```text
DomainKeyDerivation
    ↓
MK
    ├── NEK
    └── TEK
```

Stage 5 then owns the **session lifetime** of those key materials.

Stage 5 must not create another dataset key.

It must not recover the MK through `system_crypto_pin`.

It must not regenerate the MK on unlock.

It must consume the authoritative MK established by Block B.

---

# AK. Final security invariants

```text
[✓] Exactly one dataset-authoritative MK
[✓] MK generated randomly
[✓] MK never derived from password
[✓] Password Verifier is authentication-only
[✓] Password-KEK unwrap returns same dataset MK
[✓] Recovery-KEK unwrap returns same dataset MK
[✓] Password changes preserve MK
[✓] Device additions preserve MK
[✓] Recovery never generates replacement MK
[✓] Legacy authSalt artifact cannot be interpreted as MK
[✓] Malformed/tampered wrappers cannot install MK
[✓] Remote CAS prevents silent split-brain
[✓] No plaintext MK persistence
[✓] No MK logging
[✓] Temporary plaintext MK copies are zeroed where possible
[✓] NEK/TEK come only from existing Stage 4 HKDF
[✓] No permanent legacy compatibility architecture
[✓] Legacy data encryption is migration-only
[✓] Final protected note data uses NEK
[✓] Final GitHub token data uses TEK
[✓] Password change uses wrapper rekeying, not note re-encryption
[✓] Recovery directly recovers MK
[✓] Stage 5 receives established MK
[✓] Stage 6 full envelope/AAD redesign remains separate
```

---

# AL. Final readiness gate

```text
BLOCK B PRODUCTION INTEGRATION DESIGN

[✓] One authoritative MK lifecycle fully defined
[✓] First-device establishment fully defined
[✓] Local Password-KEK wrapper persistence fully defined
[✓] Remote Recovery-KEK wrapper persistence fully defined
[✓] Joining-device recovery fully defined
[✓] Same-MK password change fully defined
[✓] Local-only installation behavior explicitly resolved
[✓] Remote concurrency/split-brain behavior defined
[✓] Local/remote crash behavior defined
[✓] Controlled legacy note migration defined
[✓] Controlled GitHub token migration defined
[✓] Legacy device_key.json removal defined
[✓] system_crypto_pin removal boundary defined
[✓] Exact legacy CryptoEngine deletion boundary defined
[✓] Stage 4 HKDF boundary unchanged
[✓] Stage 5 handoff contract defined
[✓] No Stage 5 implementation included
[✓] No permanent legacy compatibility layer
[✓] No new KDF/key hierarchy invented
[✓] No hardware-MK wrapping pulled forward
[✓] Security invariants testable
[✓] Production file impact identified
```

The only special prerequisite is the explicitly identified **small Stage 2 durable-local-authority extension**. It is not a new cryptographic design and is required because the current product already supports local operation before GitHub establishment.

The actual legacy development repository should then be treated as a controlled cutover target: either migrate its local encrypted notes with the one-time tool, or discard them and reseed cleanly. The remote development repository should preferably be reset/reseeded rather than becoming the foundation for a permanent legacy migration subsystem.

No production code has been changed in this review.

BLOCK B PRODUCTION INTEGRATION DESIGN — READY FOR IMPLEMENTATION

# AUDITOR

We have made the final implementation decision.

# IMPLEMENT BLOCK B NOW

The application has **no public users and no user data that must be preserved**.

Therefore we do NOT need a migration system for existing legacy data.

We are choosing the cleanest possible security transition:

```text
LEGACY DEVELOPMENT DATA
        ↓
      DISCARD
        ↓
NEW MK-BASED PRODUCTION ARCHITECTURE

```

There will be:

- no legacy-data migration utility,
- no temporary ciphertext format,
- no permanent compatibility layer,
- no transitional legacy-data key,
- no multi-format runtime reader,
- no preservation of the current development ciphertext.

We are explicitly allowed to reset/delete the current development/test encrypted data and reseed the application using the final architecture.

**Begin implementing Block B now.**

Do NOT implement Stage 5 yet.

Do NOT wait for a migration design.

Do NOT create a migration mechanism.

Do NOT preserve the old development ciphertext.

---

# 1. Final target architecture

The production application must become:

```text
                    PASSWORD
                       │
             ┌─────────┴─────────┐
             │                   │
             ▼                   ▼
      Password Verifier      Password-KEK
      authentication only          │
                                  ▼
                         Password-wrapped MK
                                  │
                                  ▼
                         AUTHORITATIVE MK
                                  │
                         existing Stage 4 HKDF
                            ┌─────┴─────┐
                            ▼           ▼
                           NEK         TEK
                            │           │
                            ▼           ▼
                          NOTES       GITHUB TOKEN

```

Recovery:

```text
PASSWORD + 12-WORD MNEMONIC
            ↓
       Recovery-KEK
            ↓
   Recovery-wrapped MK
            ↓
      SAME AUTHORITATIVE MK

```

Security invariants:

```text
MK is random
MK is generated once
MK is never derived from password
Password Verifier cannot reconstruct MK
Password-KEK unwraps same MK
Recovery-KEK unwraps same MK
Password changes preserve same MK
NEK/TEK derive from same MK
No plaintext MK is persisted
No plaintext MK is logged
No second authoritative MK exists

```

---

# 2. No migration system

This is an explicit decision.

Do NOT create:

```text
migrateEncryptedNotes()
legacy migration tool
migration checkpoints
legacy ciphertext version detector
dual-format reader
temporary Block B ciphertext format
legacy-data-key compatibility layer

```

We are not preserving the current encrypted development dataset.

The current development data may be:

```text
deleted
reset
recreated
reseeded

```

This is intentional.

Do not spend implementation effort on backward compatibility for data that has no users.

---

# 3. Do NOT create a temporary ciphertext format

This corrects the previous Block B design.

Do NOT implement:

```text
legacy ciphertext
    ↓
temporary Block B ciphertext
    ↓
future Stage 6 ciphertext

```

That would create another migration later.

Instead:

```text
new production data
    ↓
final approved MK-based architecture

```

The Stage 4 HKDF hierarchy must be the foundation.

If the final note/token ciphertext envelope belongs to Stage 6, do not invent a second persistent Block B format merely to satisfy the current implementation.

We are allowed to reset the development data, so there is no need to make legacy ciphertext readable by the new application.

---

# 4. What happens to the current legacy development data

The implementation procedure should explicitly support a clean reset.

For the controlled development repository:

```text
remove/reset legacy device_key.json
remove/reset legacy password_state.json
remove/reset legacy encrypted development data
remove/reset legacy system_crypto_pin state

```

Then establish the new architecture from a clean state.

The application must not attempt to interpret old development artifacts as part of the new architecture.

Legacy artifacts are not a compatibility target.

---

# 5. First-device establishment

Implement the actual production MK flow.

Use the existing `MasterKeyManager` and existing `PasswordKeyDerivation`.

Desired sequence:

```text
fresh dataset
    ↓
user establishes password
    ↓
create Password Verifier
    ↓
generate random 256-bit MK
    ↓
MasterKeyManager = PROVISIONAL
    ↓
create Password-KEK wrapper over MK
    ↓
create Recovery-KEK wrapper over SAME MK
    ↓
validate both wrappers resolve to the same MK
    ↓
persist local security record
    ↓
if remote repository configured:
    conditionally publish Recovery-MK wrapper
    ↓
verify remote wrapper corresponds to SAME MK
    ↓
establish authority

```

Do not derive MK from the password.

Do not generate another MK on recovery.

Do not create a synthetic session MK.

---

# 6. Local-only first device

Implement the agreed small durable local-authority extension.

Current product behavior permits the user to establish cryptographic setup before GitHub is configured.

Therefore:

```text
fresh installation
+
password configured
+
no GitHub repository

```

must be able to establish:

```text
one local authoritative MK

```

after the complete local security record is successfully committed and verified.

The local security record becomes the durable authority record.

No new cryptographic primitive is required.

No second MK is generated when GitHub is configured later.

When GitHub is configured:

```text
existing local authoritative MK
        ↓
existing Recovery wrapper
        ↓
publish same wrapper

```

If an existing remote dataset is discovered, compare the remote MK to the local MK and refuse silent replacement.

---

# 7. Local security record

Create the approved local security record in:

```text
rocen_settings_box

```

using a dedicated logical key such as:

```text
master_key_record_v1

```

It should contain only required security metadata:

```json
{
  "schema": 1,
  "authority": "authoritative",
  "passwordVerifier": "...",
  "passwordWrap": "{existing Stage 3 wrapper}",
  "recoveryWrap": "{existing Stage 3 recovery wrapper}",
  "remoteRecovery": {
    "status": "unpublished|published|conflict",
    "repository": "..."
  }
}

```

No plaintext MK.

No plaintext password.

No mnemonic.

No NEK.

No TEK.

---

# 8. Remote device_key.json

The new `device_key.json` must be the existing Stage 3 Recovery-KEK wrapper output.

Use:

```text
PasswordKeyDerivation.wrapMasterKeyWithRecovery(...)

```

directly.

Do not invent another encryption format around it.

The old:

```json
{
  "wrapSalt": "...",
  "wrapNonce": "...",
  "wrappedAuthSalt": "..."
}

```

is obsolete for this development system.

Because no public data must be preserved, simply reset/remove the old artifact during controlled setup.

The new production artifact becomes the only supported `device_key.json`.

---

# 9. Joining-device recovery

Implement the actual production recovery flow:

```text
select existing repository
    ↓
fetch new device_key.json
    ↓
validate new Recovery wrapper
    ↓
enter password + 12-word mnemonic
    ↓
unwrap authoritative MK
    ↓
validate 32-byte MK
    ↓
create local Password-KEK wrapper
    ↓
create local Password Verifier
    ↓
persist local security record
    ↓
install authoritative MK

```

Recovery MUST:

```text
recover existing MK

```

not:

```text
generate new MK

```

Wrong password, wrong mnemonic, malformed wrapper, unsupported version, invalid authentication tag, or tampering must never create a replacement MK.

---

# 10. Password change

Replace the current password-change behavior with the existing Stage 3 same-MK operation.

Required:

```text
old password
    ↓
unwrap SAME MK
    ↓
new Password-KEK wrapper
+
new Recovery-KEK wrapper
+
new Password Verifier

```

Invariant:

```text
MK_before == MK_after
NEK_before == NEK_after
TEK_before == TEK_after

```

Do NOT re-encrypt application ciphertext because of the password change.

Do NOT generate a new MK.

Do NOT migrate notes during password change.

Because the current development data is disposable, the old legacy password-dependent encrypted data can simply be reset as part of the clean cutover.

---

# 11. Eliminate system_crypto_pin as a data-encryption key

This is a fundamental part of Block B.

The final production architecture must NOT use:

```text
system_crypto_pin
    ↓
note encryption
system_crypto_pin
    ↓
token encryption

```

Instead:

```text
MK
 ↓
HKDF
 ├── NEK → notes
 └── TEK → GitHub token

```

The password verifier remains authentication-only.

Do not leave a hidden password-derived legacy data key behind.

Do not introduce another compatibility key.

---

# 12. Production note encryption

Because there is no public data to preserve, production note storage should be created directly using the approved final architecture.

Use:

```text
authoritative MK
    ↓
existing Stage 4 DomainKeyDerivation
    ↓
NEK
    ↓
approved note encryption implementation

```

Do not keep the old password-derived note encryption path merely for compatibility.

Do not create a temporary Block B ciphertext format.

If the final note envelope is assigned to Stage 6, identify the exact dependency and stop that specific integration point rather than inventing a temporary production format.

The goal is:

```text
NO LEGACY NOTE CIPHERTEXT
+
NO TEMPORARY BLOCK B CIPHERTEXT

```

---

# 13. Production GitHub token encryption

Likewise:

```text
authoritative MK
    ↓
existing Stage 4 DomainKeyDerivation
    ↓
TEK
    ↓
approved token encryption implementation

```

Do not retain password-derived token encryption.

Do not create a temporary compatibility key.

Because there is no user data to preserve, the current development token may simply be removed and re-entered under the new architecture.

---

# 14. Exact final legacy removal

After the clean reset and direct new architecture implementation, verify that production contains no callers for:

```text
system_crypto_pin as data key
legacy password note encryption
legacy password token encryption
legacy authSalt recovery
legacy device_key.json recovery
migrateEncryptedNotes

```

Then remove those obsolete production APIs and code paths.

Do not leave dead legacy security code available for future developers to accidentally call.

The desired final result is:

```text
Password Verifier
Password-KEK
Recovery-KEK
MK
NEK
TEK

```

and no second data-encryption architecture.

---

# 15. MasterKeyManager ownership

Until Stage 5 exists, use the current agreed Stage 3 ownership model.

Do not create a second permanent MK owner.

There must be only one authoritative live MK.

Temporary defensive copies may exist during wrapper operations, but:

```text
copy
→ use
→ zero

```

Do not retain caller-owned `Uint8List` buffers as authoritative key storage.

Do not persist plaintext MK.

---

# 16. Remote concurrency

The repository authority rules must prevent two devices from silently establishing different MKs.

Use the existing conditional/fast-forward behavior appropriately.

Desired invariant:

```text
one repository
    ↓
one authoritative MK

```

If:

```text
Device A → MK-A
Device B → MK-B

```

and both attempt first establishment:

```text
other device detects conflict

```

Never silently overwrite a different remote Recovery wrapper.

For multi-file password/recovery metadata updates, use a compare-and-swap/fast-forward strategy rather than force-pushing.

---

# 17. Crash handling

Even though we are not migrating old data, first-device and password-state persistence must still be crash-safe.

Handle:

```text
local commit succeeds
remote publish fails
remote publish succeeds
local finalization fails
GitHub timeout
stale GitHub ref
process crash

```

The key invariant is:

```text
crash cannot create two authoritative MKs

```

and:

```text
retry never generates a second MK

```

Use durable pending state where remote synchronization is not complete.

Do not claim local Hive + GitHub is one atomic transaction.

---

# 18. Do not use remote data as authority when local dataset is clearly new

For local-only installations:

```text
no associated remote dataset

```

the complete validated local security record establishes local authority.

For an installation explicitly joining an existing repository:

```text
inspect remote dataset first

```

before generating a new dataset MK.

Never generate a new MK and only afterward discover that an existing remote dataset already has another authoritative MK.

If remote and local authorities differ:

```text
```

Never silently replace either one.

---

# 19. Security logging

During implementation remove/redact any logging of:

```text
MK
password
PIN
mnemonic
tokens
plaintext notes
note titles
sensitive filenames
crypto inputs/outputs
secret-bearing exceptions

```

Use structured security events instead.

Do not log raw exception text when it could contain protected data.

---

# 20. Stage boundaries

Block B implementation may modify the production cryptographic architecture as required to establish:

```text
Password Verifier
Password-KEK
Recovery-KEK
MK
NEK
TEK

```

and remove the legacy password-derived data-key system.

Do NOT implement:

```text
Stage 5 session locking
SessionSecurityManager
ACTIVATING
ProviderContainer lifecycle
AppLifecycleListener
FLAG_SECURE
session epochs

```

Those remain Stage 5.

Do NOT redesign Stage 4 HKDF.

Do NOT introduce the later Stage 6 envelope/AAD redesign unless that is already explicitly required as the final production ciphertext format at this stage. Do not invent a temporary format to bridge the gap.

---

# 21. Implementation order

Implement in this order:

```text
1. Add the small durable local-authority extension.

2. Add local master-key security record.

3. Add production Master-Key integration service.

4. Wire first-device MK establishment.

5. Wire Password Verifier.

6. Wire Password-KEK persistence.

7. Wire Recovery-KEK persistence.

8. Wire local-only authority.

9. Wire remote Recovery-MK publication.

10. Wire joining-device recovery.

11. Wire password-change same-MK rewrap.

12. Remove legacy production password-derived data-key behavior.

13. Establish final NEK/TEK production consumers.

14. Reset/remove current controlled development legacy data.

15. Re-enter/reseed controlled development data using MK-derived keys.

16. Remove obsolete legacy recovery/device-key code.

17. Remove obsolete legacy CryptoEngine password-data-encryption APIs.

18. Remove migrateEncryptedNotes and related legacy paths.

19. Audit all production callers.

20. Run complete tests and static analysis.

21. Perform repository-wide cryptographic ownership audit.

22. Freeze Block B.

23. Only then resume Stage 5.

```

Important:

**Do not implement a migration utility between step 12 and step 13.**

The current legacy data is disposable.

The reset/reseed is the transition.

---

# 22. Required tests

### MK establishment

```text
firstDeviceGeneratesOneMK
localPasswordWrapperRoundTrip
localRecoveryWrapperRoundTrip
sameMKAcrossBothWrappers
localAuthorityPersistsAcrossRestart

```

### Recovery

```text
recoverSameMKFromRemoteWrapper
wrongPasswordDoesNotInstallMK
wrongMnemonicDoesNotInstallMK
malformedWrapperRejected
unsupportedWrapperRejected
tamperedWrapperRejected
noReplacementMKOnRecoveryFailure

```

### Password change

```text
passwordChangePreservesMK
passwordChangePreservesNEK
passwordChangePreservesTEK
newPasswordWrapperValid
newRecoveryWrapperValid
newVerifierValid
oldPasswordCannotUnlockWithNewWrapper

```

### Concurrency

```text
twoFirstDevicesCannotCreateTwoAuthorities
remoteExistingDifferentMKProducesConflict
sameMKAssociatesExistingRemote
staleRemoteRefRejected

```

### Crash/retry

```text
retryAfterLocalCommitFailure
retryAfterRemoteFailure
remoteSuccessLocalFinalizeRecovery
retryDoesNotGenerateSecondMK

```

### Final architecture

```text
noProductionSystemCryptoPinDataKeyCaller
noProductionLegacyNoteEncryptionCaller
noProductionLegacyTokenEncryptionCaller
noProductionLegacyDeviceRecoveryCaller
noProductionMigrateEncryptedNotesCaller
noReplacementMKRecoveryPath

```

### Key ownership

```text
noSecondPersistentMK
noPlaintextMKPersistence
temporaryMKCopiesZeroed

```

---

# 23. Repository-wide final audit

After implementation, search the entire repository for:

```text
system_crypto_pin
MasterKeyManager
PasswordKeyDerivation
DomainKeyDerivation
CryptoEngine
wrapDeviceKey
unwrapDeviceKey
hashPin
hashPinWithSalt
migrateEncryptedNotes
SecureBytes
_masterKeyBytes
Uint8List.fromList

```

Then prove:

```text
one authoritative MK
+
no legacy data-encryption key
+
no legacy recovery architecture
+
no temporary Block B ciphertext format
+
NEK/TEK derive from MK

```

Do not rely on the absence of obvious call sites alone. Inspect ownership and actual data flow.

---

# 24. Final Block B completion gate

Do not declare Block B complete until all are true:

```text
[ ] One authoritative random MK exists
[ ] MK is never password-derived
[ ] Password Verifier is authentication-only
[ ] Password-KEK wrapper exists locally
[ ] Recovery-KEK wrapper exists remotely
[ ] Same MK is recovered by both wrappers
[ ] Local-only authority is durable
[ ] Existing repository discovery occurs before new-MK generation
[ ] Concurrent first-device establishment cannot silently split authority
[ ] Joining device recovers existing MK
[ ] Password change preserves MK
[ ] Password change preserves NEK/TEK
[ ] system_crypto_pin is no longer a data-encryption key
[ ] legacy note encryption is removed
[ ] legacy token encryption is removed
[ ] legacy authSalt recovery is removed
[ ] legacy device_key.json format is removed
[ ] no migration utility exists
[ ] no temporary ciphertext format exists
[ ] current development data has been reset/reseeded
[ ] final production data uses the MK-based architecture
[ ] no plaintext MK is persisted
[ ] no MK is logged
[ ] crash/retry cannot create a second authoritative MK
[ ] remote concurrency uses conditional updates
[ ] all required tests pass
[ ] full static analysis passes
[ ] repository-wide ownership audit passes
[ ] Stage 5 remains untouched

```

---

# 25. Final report

After implementation, report:

### Files changed

Exact files.

### Files deleted

Exact obsolete legacy files/code paths.

### Security changes

Explain each security-relevant change.

### Tests

Exact commands actually executed and results.

### Static analysis

Exact command and result.

### Repository ownership audit

Show where the sole authoritative MK lives and prove there is no second owner.

### Final cryptographic data flow

Show:

```text
PASSWORD
 ├── Verifier
 └── Password-KEK → MK
                    ├── NEK → Notes
                    └── TEK → GitHub token

PASSWORD + MNEMONIC
        ↓
   Recovery-KEK
        ↓
       SAME MK

```

### Stage 5 handoff

State exactly what Stage 5 will receive.

It must be:

```text
a legitimately established/recoverable authoritative dataset MK
+
existing Stage 4 MK→NEK/TEK derivation
+
no dependency on system_crypto_pin for data encryption

```

Do not include Stage 5 session ownership yet.

---

# Final instruction

**Implement Block B as a clean cutover.**

We do not need to preserve current development data.

We do not need a migration framework.

We do not need temporary compatibility encryption.

We do not need a transitional legacy key.

We want the codebase to move directly from:

```text
legacy development implementation

```

to:

```text
clean MK/NEK/TEK production architecture

```

with the smallest possible cryptographic attack surface.

Do not mark Block B complete merely because the code compiles.

The implementation must satisfy the security invariants above and pass the actual repository-wide audit.

**Begin implementation now.**