# Rocen Multi-Device Blueprint

## Status

**ABORTED FOR CURRENT RELEASE — BLUEPRINT ONLY**

This document preserves a future multi-device/security architecture that was considered during development but intentionally **not implemented as a normal user-facing feature**.

The decision is based primarily on user experience: requiring an ordinary user to understand and remember multiple recovery secrets would add substantial friction and create more ways for recovery to fail. The architecture may become appropriate later for an advanced/high-security mode if users explicitly request it.


## Why This Idea Was Considered

Rocen uses GitHub as its backup transport and shared repository.

For a user with one device, some cross-device password-state checks can be unnecessary. A single-device user generally does not need repeated checks asking whether another device changed the shared password state.

The proposed solution was to distinguish:

```text
SOLO DEVICE
MULTI-DEVICE
```

The intended goal was:

```text
SOLO MODE
→ minimize unnecessary GitHub API calls
→ keep normal write/concurrency protection
→ avoid repeated cross-device password-state checks

MULTI-DEVICE MODE
→ enable cross-device password-state coordination
→ track enrolled devices
→ detect devices that are behind another device
```

The optimization idea remains valid, but the additional recovery-secret system was judged too high-friction for the normal product.


# Proposed Architecture

## 1. Multi-Device Toggle

A future settings option would appear below the interface/theme controls:

```text
MULTI-DEVICE ENABLE    [ OFF / ON ]
```

### OFF

The application behaves primarily as a single-device backup client.

Ordinary note changes would avoid unnecessary cross-device password-state checks before every push.

Normal GitHub write integrity and conflict/concurrency protection would remain enabled.

### ON

The application enables cross-device coordination.

Password-state checks can be performed when needed so multiple devices do not silently diverge.


# 2. Shared `device_key.json`

The proposed future structure was:

```json
{
  "key": {
    "wrapSalt": "...",
    "wrapNonce": "...",
    "wrappedAuthSalt": "..."
  },
  "digit": {
    "recovery": "...",
    "toggle": "ON"
  }
}
```

This should **not** be implemented literally without cryptographic authentication of the policy metadata.

A repository editor must not be able to simply change:

```text
toggle = OFF
```

to:

```text
toggle = ON
```

and thereby bypass a security boundary.

Any future implementation must authenticate the multi-device policy state.


# 3. Shared `password_state.json`

The device-registration design evolved into this conceptual model:

```json
{
  "version": 2,
  "passwordGeneration": 3,
  "passwordChangeId": "...",
  "passwordChangedAt": "...",
  "changedByDeviceId": "device-A",

  "multiDeviceEnabled": true,

  "devices": [
    {
      "deviceNumber": 1,
      "deviceId": "device-A",
      "passwordGeneration": 3,
      "status": "active"
    },
    {
      "deviceNumber": 2,
      "deviceId": "device-B",
      "passwordGeneration": 2,
      "status": "active"
    }
  ]
}
```

### Shared password state

These fields describe the current shared password event:

```text
passwordGeneration
passwordChangeId
passwordChangedAt
changedByDeviceId
```

### Device registry

The `devices` array describes enrolled devices.

Each entry contains:

```text
deviceNumber
deviceId
passwordGeneration
status
```

`deviceNumber` is the simple human/order identifier:

```text
Device 1
Device 2
Device 3
...
```

`deviceId` remains the actual unique installation identity.

The existing random per-installation device ID should **not** be replaced by the sequential number.

# 4. Fresh First Device

A brand-new backup would begin with:

```text
Device A
deviceNumber = 1
passwordGeneration = 1
```

GitHub would contain:

```text
device_key.json
password_state.json
```

The initial password state would represent generation 1.

This prevents a new device from being locally treated as generation 0 while the shared repository starts at generation 1.

# 5. Joining Device

A new device connecting to an existing backup would:

```text
1. Configure a password.
2. Configure the GitHub token + repository.
3. Provide the recovery phrase.
4. Read device_key.json.
5. Read password_state.json.
6. Validate that the device is allowed to join.
7. Adopt the current password generation.
8. Register itself as the next device.
```

A joining device must **not** create a new password generation merely because it joined.

For example:

```text
Device A
generation = 1

Device B joins
generation = 1
```

The existing `changedByDeviceId` must still identify the device that actually changed the password state.

# 6. Device Awareness

Once devices are registered, Device A can fetch the shared state and see:

```text
Device 1
Device 2
Device 3
...
```

This solves the limitation of having only one `changedByDeviceId`.

The password-generation mechanism describes the current password state, while the device registry describes backup membership.

# 7. Password Change on a Multi-Device Backup

Example:

```text
Device A
generation = 1

Device B
generation = 1
```

A changes the password.

Shared state becomes:

```text
passwordGeneration = 2
changedByDeviceId = Device A
```

The device registry can then represent:

```text
Device A → generation 2
Device B → generation 1
```

Device B is behind.

The application can detect:

```text
Device B is registered
Device B is still on generation 1
Shared generation is 2
```

and require Device B to update before normal multi-device synchronization continues.

# Why the Original Recovery Idea Was Aborted

A proposed recovery model introduced an additional 8-digit recovery code.

The intended recovery flow was:

```text
Password
+
12-word recovery phrase
+
8-digit recovery code
+
GitHub repository
```

That creates three separate things an ordinary user must understand or preserve:

```text
1. Password
2. 12-word recovery phrase
3. 8-digit recovery code
```

For a mainstream application, this creates too much friction.

A recovery system is only useful when users can reliably understand and use it. Adding another remembered secret increases the number of ways recovery can fail.

Therefore:

> **Do not introduce the 8-digit recovery secret into the normal Rocen user experience unless there is a clear product/security requirement for it.**

# Future High-Security Recovery Concept

An advanced recovery design was considered in which recovery material would combine user-held secrets with repository-held cryptographic parameters.

The conceptual inputs were:

```text
12-word recovery phrase
user password
device/backup key material
Argon2id
random salt
nonce
```

An important cryptographic conclusion is:

**Public repository metadata, salts, and nonces are not secrets.**

They can be encryption/KDF parameters, but they should not be counted as independent secret entropy.

An encrypted copy of an 8-digit code is also not automatically strong merely because it is encrypted.

A stronger future design would use a random master key with separate wrapping keys.

Conceptually:

```text
                 RANDOM BACKUP MASTER KEY
                           |
              +------------+------------+
              |                         |
       Password-derived KEK       Recovery-derived KEK
          (Argon2id)                 (Argon2id)
              |                         |
              +------------+------------+
                           |
                  Wrapped backup key
```

This would separate:

```text
normal password unlock
```

from:

```text
disaster recovery
```

instead of making recovery depend on an additional numeric secret.

# Important Cryptographic Principle

A future implementation must not claim:

> "Even a top-end GPU cannot decrypt this."

Security depends on secret entropy and the KDF/encryption construction.

Argon2id is useful because it makes password guessing more expensive, but it cannot make a weak human secret equivalent to a high-entropy random key.

For any future implementation:

```text
Secret entropy
+
Argon2id parameters
+
authenticated encryption
+
secure key hierarchy
```

must be considered together.

# Solo Mode Design Goal

The strongest reason to preserve this blueprint is API efficiency, not to make users manage more secrets.

A future solo mode should aim for:

```text
App open
→ one refresh when appropriate

Note changed
→ local change
→ direct GitHub push

No unnecessary password-state preflight
```

But solo mode must **not** mean:

```text
blindly overwrite GitHub
```

Normal optimistic concurrency / write integrity must remain.

The optimization should remove unnecessary cross-device coordination, not remove protection against remote-write conflicts.

# Mode Transition Rules

A future implementation must explicitly define what happens when the user changes modes.

### OFF → ON

Require a valid local security state and synchronize the shared configuration with GitHub.

### ON → OFF

Do **not** silently revoke existing devices.

If multiple devices are active, the application should require an explicit device-management/revocation decision before disabling multi-device coordination.

This prevents accidentally stranding valid devices.

# Lost Device / Replacement

A future multi-device implementation should distinguish:

```text
deviceNumber
deviceId
status
```

rather than pretending a replacement is the same physical device.

Example:

```json
{
  "deviceNumber": 1,
  "deviceId": "device-A",
  "status": "revoked"
}
```

and:

```json
{
  "deviceNumber": 2,
  "deviceId": "device-B",
  "status": "active"
}
```

This preserves device history and makes replacement explicit.

# Concurrency Requirement

Sequential device numbering cannot safely be implemented as:

```text
highestNumber + 1
```

without concurrency protection.

Example:

```text
Device B reads highest = 1
Device C reads highest = 1

Both choose:
deviceNumber = 2
```

Therefore device registration must use an atomic/conditional update mechanism.

The existing GitHub synchronization design already uses conditional write information such as expected/parent commit state. A future device-registration mechanism should reuse the same principle.

# What This Blueprint Must NOT Change

If this feature is eventually implemented, it should preserve Rocen's existing security architecture:

```text
Password hashing / KDF
Encryption
Hardware binding
Secure local credential storage
GitHub certificate pinning
GitHub request security
Repository write integrity
Recovery phrase support
```

The multi-device feature should be an orchestration layer around those primitives, not a replacement for them.

# Recommended Product Direction

For the normal Rocen release:

```text
Keep the UX simple.
Keep the 12-word recovery phrase.
Do not require an 8-digit recovery secret.
Use solo behavior by default.
```

For a future advanced/high-security edition or explicit user request:

```text
Add multi-device enrollment.
Add authenticated device registry.
Add stronger recovery/key hierarchy.
Add explicit device revocation.
Add password-generation reconciliation.
Add efficient solo-mode synchronization.
```

The advanced design should be introduced only when there is a demonstrated need.


# Final Decision

**Do not implement the original 8-digit recovery-code workflow in the current product.**

Keep this document as the blueprint.

The preferred future direction is:

```text
Simple default user experience
        +
single recovery phrase
        +
optional advanced multi-device mode
        +
authenticated shared device registry
        +
efficient solo-mode synchronization
```

The purpose of this document is to preserve the design so the work can be resumed later without having to reconstruct the architecture from memory.
