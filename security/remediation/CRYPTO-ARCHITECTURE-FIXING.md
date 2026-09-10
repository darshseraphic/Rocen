# PROMPT

## Architectural Specification #4: Master-Key Cryptographic Target Architecture

> **Notice:** This document defines the prioritization, design phase, and threat-modeling requirements for the **Rocen Cryptographic Master-Key Redesign**. **No code editing, commits, or file rewrites are to be executed during this pass.**

## Executive Directives & Scope Constraints

* **No Legacy Data Migration Needed:** The app currently has no active user base. Do **not** spend effort or design complexity on migrating legacy v1 user notes or old installations.
* **Forward-Looking Extensibility:** The target design **must** incorporate strict cryptographic versioning to enable safe, atomic v2+ migrations in the future.
* **Strict Planning Mode:** This requirement is limited strictly to architectural analysis, key hierarchy definition, and threat modeling.

## Target Security Architecture Pillars

1. **Independent Random Master Key**
2. **Separate Password Verifier**
3. **Password-Derived KEK (Key Encryption Key)**
4. **Recovery-Derived Key Protection**
5. **Android Keystore / StrongBox Integration**
6. **GitHub Token Protection**
7. **Local Note Encryption**
8. **Zero-Re-encryption Password Changes**
9. **Cross-Tier Multi-Device Interoperability**
10. **Future-Safe Envelope Versioning**

## Architectural Breakdown & Design Requirements

### Section A: Current Architecture Analysis

Trace and document the existing implementation directly from source code (`crypto_engine.dart`, `crypto_isolate.dart`, `settings.dart`, `quicknote.dart`, etc.), explicitly ignoring claims in `README` or `CHANGELOG` if contradicted by the codebase:


$$\text{Password} \longrightarrow \text{Derived Values} \longrightarrow \text{Stored Values} \longrightarrow \text{Note Encrypt/Decrypt} \longrightarrow \text{GitHub Token} \longrightarrow \text{Password Change} \longrightarrow \text{Recovery} \longrightarrow \text{Device Key}$$

### Section B: Target Key Architecture

Design an decoupled, multi-tier key hierarchy rooted in an **independent, cryptographically random Master Key**.

```
                           [ User Password ]                     [ Recovery Phrase ]
                                   │                                      │
                             Argon2id KDF                            Argon2id KDF
                                   │                                      │
                        ┌──────────┴──────────┐                           │
                        ▼                     ▼                           │
               [ Password Verifier ]   [ Password KEK ]             [ Recovery KEK ]
               (Auth Verification)   (Key Wrapping)               (Key Wrapping)
                        │                     │                           │
                        │                     └───────────┬───────────────┘
                        │                                 │
                        │                         Unwraps / Protects
                        │                                 │
                        │                                 ▼
                        │                      ┌─────────────────────┐
                        │                      │  Random Master Key  │
                        │                      └──────────┬──────────┘
                        │                                 │
                        │                       Protects / Encrypts
                        │                                 │
                        └─────────────────────────┬───────┴────────────────────────┐
                                                  ▼                                ▼
                                          [ Local Notes ]                   [ GitHub Token ]

```

#### Key & Value Lifecycle Specification

For every key/value in the hierarchy, explicitly define:

* **Purpose & Function**
* **Generation Primitive**
* **Storage Location & State**
* **In-Memory Lifetime**
* **Protected Entities**
* **Protecting Material**
* **Exportability Constraints**
* **Extraction Security Impact**

> **Non-Negotiable Isolation Constraints:**
> 1. The stored **Password Verifier** MUST NOT be mathematically or cryptographically usable as a secret for note encryption.
> 2. The **Master Key** MUST be generated via a secure CSPRNG and remain strictly independent of the user's explicit password string.
> 
> 

### Section C: Local Secret Storage Matrix

Define the precise storage characteristics for every security-sensitive artifact:

| Artifact / Secret | Location | Plaintext / Encrypted | Protecting Primitive | Storage Rationale | Local Recovery Feasibility | Local Extraction Impact |
| --- | --- | --- | --- | --- | --- | --- |
| **Password Artifacts** |  |  |  |  |  |  |
| **Password Verifier** |  |  |  |  |  |  |
| **Raw Master Key** |  |  |  |  |  |  |
| **Wrapped Master Key** |  |  |  |  |  |  |
| **GitHub Access Token** |  |  |  |  |  |  |
| **Device Key / Hardware** |  |  |  |  |  |  |
| **Recovery Metadata** |  |  |  |  |  |  |
| **Note Payload** |  |  |  |  |  |  |
| **Encryption Metadata** |  |  |  |  |  |  |

### Section D: Encrypted Envelope Format V2

Design a self-describing, zero-dependency payload envelope that allows independent decryption without relying on the current host device's ambient state or global configurations.

#### Required Envelope Fields

* `format_version` (Format identifier)
* `key_version` (Master Key generation identifier)
* `cipher_algo` (e.g., AES-256-GCM)
* `kdf_algo` (e.g., Argon2id)
* `kdf_params` (Memory, Iterations, Parallelism)
* `salt`
* `nonce`
* `ciphertext`
* `auth_tag`
* `aad` (Additional Authenticated Data)
* `note_id_binding` (Explicit context binding)
* `anti_replay_counter` (Generation/Revision tracking)

#### Security Boundary Definitions

Specify field classification across the following parameters:

* **Encrypted Fields** vs. **Public Metadata**
* **Authenticated Fields (AAD Covered)**
* **Immutable Envelope Attributes**
* **Tamper Detection Mechanisms**
* **Title Strategy:** Formulate a recommendation on whether note titles should be stored encrypted alongside the payload or kept unencrypted but cryptographically bound via AAD.

### Section E: Zero-Re-encryption Password Change Protocol

Design a password update sequence that operates entirely on key-wrapping layers:

* **Master Key Persistence:** Retained without modification.
* **Updated Artifacts:** Password KEK, Password Verifier, Wrapped Master Key blob.
* **Scope Avoidance:** Eliminates the necessity to re-encrypt existing notes or update remote GitHub sync data.
* **Atomic Recovery:** Defines state-machine crash recovery to prevent lockouts during unexpected interruptions.

### Section F: Master Key Recovery Architecture

Detail the recovery phrase workflow:

* Derivation mechanisms for the **Recovery KEK**.
* Dual-wrapping strategy for the **Master Key**.
* Prevention of persistent recovery secrets or diagnostic log leaks.
* Security posture under total recovery phrase loss vs. password loss scenarios.

### Section G: Multi-Device Synchronization & Interoperability

Ensure full cross-platform compatibility across heterogeneous hardware and environment profiles:

* **Enrollment & Master Key Sharing:** Safe propagation across devices.
* **Cross-Tier Decryption:** Standard-tier devices MUST seamlessly decrypt payloads produced by Hardened-tier devices (and vice versa) using self-describing envelope metadata.
* **Hardware Interoperability:** Define how local Android Keystore / StrongBox protections wrap the shared Master Key without mutating shared payload structures.

### Section H: Future-Safe Versioning Strategy

Establish architectural guardrails for future cryptographic transitions:

* Crypto & Key Versioning Schemes
* Migration Markers & State Flags
* Strict Failure Boundaries for Unsupported Format Versions
* Prevention of Cryptographic Downgrade Attacks

### Section I: Failure Behavior Matrix

Explicitly define fail-closed behavior across all operational fault vectors:

```
[ Failure Condition ] ──► [ Security Response ] ──► [ System State ]

```

Required fault handling rules:

* Wrong Password / Invalid Key Unwrapping
* Corrupted Master Key Wrapper
* Ciphertext & Metadata Tampering / AAD Mismatch
* Out-of-Bounds or Invalid KDF Parameters
* Unsupported Format / Engine Version
* Missing Storage Keys / Android Keystore Failures
* Hardware-Backed StrongBox Unavailable
* Corrupted GitHub Sync Data / Partial Sync States

### Section J: `_isHardened()` Realignment Strategy

Re-architect `_isHardened()` to decouple global state from individual payload decryption:

1. **Decryption:** Reads explicit parameters directly from the payload envelope v2 header.
2. **Encryption:** `_isHardened()` dictates parameters **only** for newly authored or updated payloads.
3. **Fail-Closed Integration:** Safely defaults to `true` without risking data loss on unreadable notes.

### Section K: Security Test Plan & Verification Gate

Define non-negotiable verification assertions prior to code execution:

1. Legacy `system_crypto_pin` cannot decrypt v2 payloads.
2. Valid password correctly unwraps the Master Key.
3. Invalid password fails to unwrap the Master Key.
4. Password rotation maintains access to all historical notes.
5. Password rotation triggers zero note re-encryption operations.
6. Recovery phrase restores access to the original Master Key.
7. Heterogeneous device KDF parameter shifts do not disrupt existing ciphertext reading.
8. Mutated AAD triggers an immediate authentication fault.
9. Moving ciphertext across note IDs triggers an authentication failure.
10. Corrupted envelope metadata fails closed.
11. Unsupported envelope version fails closed.
12. Standard devices can read Hardened-device payloads.
13. Hardened devices can read Standard-device payloads.
14. Interrupted password updates automatically recover to a consistent state.
15. Interrupted key-wrapping operations automatically recover cleanly.
16. Android Keystore / StrongBox failure gracefully degrades without breaking cryptographic security.

### Section L: File Impact Analysis

* **`MUST CHANGE`**: Core cryptographic engines, settings controllers, key management modules.
* **`MAY CHANGE`**: Sync engines, local storage abstraction layers.
* **`SHOULD NOT CHANGE`**: Unrelated UI views, non-crypto helper utilities.

### Section M: Implementation Risk Matrix

Rank high-risk operational modules by implementation risk:

1. Key Generation & Entropy Acquisition
2. Key Wrapping & Unwrapping Pipelines
3. Atomic Password Rotation State Machine
4. Recovery Phrase Derivation & Master Key Unwrapping
5. Android Keystore / StrongBox Integration
6. Self-Describing Encrypted Payload Envelope Parser
7. Multi-Device Synchronization & State Alignment
8. GitHub Token Vaulting
9. Data Loss Prevention & Crash Recovery Mechanisms

### Section N: Design Decisions Requiring Explicit Approval

Isolate and highlight all major architectural choices that must receive formal approval before code execution.

## Core Non-Negotiables & Rules

```
┌──────────────────────────────────────────────────────────────────────────┐
│                             STRICT FORBIDDEN                             │
├──────────────────────────────────────────────────────────────────────────┤
│ ✕ Do NOT edit, commit, or rewrite code files in this phase.             │
│ ✕ Do NOT design legacy user v1 -> v2 migration paths.                    │
│ ✕ Do NOT invent unproven or custom cryptographic primitives.            │
│ ✕ Do NOT use the stored password verifier as encryption key material.    │
│ ✕ Do NOT rely on mutable local device state to parse existing payload.   │
│ ✕ Do NOT allow silent security downgrades under any circumstance.        │
└──────────────────────────────────────────────────────────────────────────┘

```

## Expected Output Structure

Deliver the target architecture review covering the following **15 required sections**:

1. Current Architecture Trace
2. Target Architecture Specification
3. Key Hierarchy Diagram & Lifecycle Rules
4. Secret-Storage Matrix
5. Encrypted Envelope Format V2 Specification
6. Password-Change Protocol Workflow
7. Master Key Recovery Workflow
8. Multi-Device Sync & Interoperability Design
9. `_isHardened()` Realignment Strategy
10. Future-Safe Versioning Architecture
11. Comprehensive Failure Behavior Matrix
12. Security Test Plan & Verification Gate
13. Detailed File Impact Analysis
14. Implementation Risk Matrix
15. Architectural Decisions Requiring Formal Approval

# AUDIT

## Rocen Master-Key Architecture — Design Review

No code modified. This is a design document only.


## 1. Current Architecture

Traced directly from the actual source, function by function.

**Password → verifier:**
`CryptoEngine.hashPin(pin)` → `hashPinWithSaltUsingParams(pin, salt, params)` → `Argon2id(pin, salt, params) = derivedBytes` → stored as `base64(salt):base64(derivedBytes)`.
Written to `system_crypto_pin` in `rocen_settings_box` (`settings.dart` lines 1378, 2541, 3584).

**Password → note/token encryption key (the core problem):**
`system_crypto_pin`'s full string value — read back as `globalPin`/`pinHash` — is passed **directly, unmodified** as the `pin` argument into `CryptoEngine.encryptProcess(payload, pinHash)`. Inside `encryptProcessWithParams` (`crypto_engine.dart` lines 86-114), that string is fed into `CryptoIsolate.deriveAndEncrypt(password: pinHash, salt: freshSalt, ...)`, which runs it through **a second, independent Argon2id derivation** to produce the actual AES-256-GCM key. Call sites: `quicknote.dart`'s `_compileAndSaveNote` (note body), `settings.dart`'s `_storeGithubCredentials`-adjacent flow (line ~3311, GitHub token).

**Decryption:** `decryptProcess(input, pinHash)` → `decryptProcessWithParams(input, pinHash, _activeEncryptionParams)`. `_activeEncryptionParams` is a **live getter** reading `_isHardened()` (which reads the *current* `kdf_hardened` Hive flag) **at the moment of decryption**, not whatever was true at encryption time.

**Wire format (current, "v1" in all but name):** `_version(1 byte) ‖ salt(16) ‖ nonce(12) ‖ mac(16) ‖ cipherText`. No KDF memory/iterations recorded. No AAD used anywhere in `crypto_isolate.dart`'s `deriveAndEncrypt`/`deriveAndDecrypt`.

**GitHub token:** `payload = 'token|repo'` → `CryptoEngine.encryptProcess(payload, pinHash)` (same reused-hash problem) → optionally `hardwareWrap(...)` via `MainActivity.kt`'s `hwEncrypt` channel (`githubTokenKeyAlias`) → stored as `github_access_encrypted`. `system_crypto_pin` itself is never deleted after hardware-wrapping — the plaintext-adjacent copy remains authoritative regardless.

**Password change:** `settings.dart`'s password-change flow computes `newPinHash` (fresh salt), then `database.dart`'s `migrateEncryptedNotes(oldPin, newPin, oldParams, newParams)` **decrypts every `encrypted_note` with the old value and re-encrypts with the new one** — because there is no independent key to merely re-wrap, only a re-derivable-from-password value used directly.

**Recovery (`device_key.json`):** `CryptoEngine.wrapDeviceKeyWithParams` — genuinely independent construction: `combinedSecret = '$password|${mnemonicWords.join(' ')}'` (raw password, not the hash), fresh `wrapSalt`, Argon2id-derives a key, AES-GCM-wraps the device's `authSaltBytes` (extracted from `system_crypto_pin`). This is correctly separated from the note/token path — it just wraps a different thing (the auth salt) for a different purpose (recovering the ability to re-derive the verifier on a new device), and does not touch or provide a master key, because none exists.

**Hardware layer:** `MainActivity.kt`'s `getOrCreateHwKey(alias)` — StrongBox-first, TEE-fallback, per-alias (`passwordKeyAlias`, `githubTokenKeyAlias`). Wraps *already-encrypted* blobs; never sees plaintext note/token content.

**The precise defect this design must fix:** `system_crypto_pin` simultaneously serves as (a) the password verifier and (b) — because it's passed unmodified into `encryptProcess` — the effective key-derivation input for every note and the token. Extracting it from the unencrypted `rocen_settings_box` is sufficient to decrypt everything, with no password-cracking step at all.

## 2. Proposed Architecture

Core principle: **one random master key, generated once, independent of the password, used directly for all data encryption. Everything else — password, recovery phrase, hardware — exists only to protect access to that one key, never to derive encryption keys themselves.**

```
                         ┌─────────────────────────┐
                         │   MASTER KEY (MK)        │
                         │   256-bit, Random.secure()│
                         │   generated once           │
                         └────────────┬────────────┘
                                      │ encrypts/decrypts directly
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              Note bodies       GitHub token      (future data types)
           (AES-256-GCM,      (AES-256-GCM,
            AAD-bound)         AAD-bound)

   MK is never stored in plaintext. It exists ONLY as:

   ┌───────────────────────────┐   ┌───────────────────────────┐   ┌──────────────────────────┐
   │ MK wrapped by Password-KEK │   │ MK wrapped by Recovery-KEK│   │ MK wrapped by Hardware key│
   │ (always present)           │   │ (always present)          │   │ (present when available)  │
   └──────────────┬─────────────┘   └──────────────┬─────────────┘   └─────────────┬────────────┘
                  │                                 │                               │
        Argon2id(password, saltKEK)      Argon2id(password|mnemonic, saltRecovery)  Android Keystore/
        = Password-KEK                    = Recovery-KEK                            StrongBox AES key
                  │                                 │                               │
        unlocks MK on normal          unlocks MK on a NEW device       unlocks MK without re-entering
        password entry                 or after password loss           password on same device
                                        (device_key.json path)           (convenience wrap only)


   SEPARATELY, unrelated to any of the above:

   Password Verifier = Argon2id(password, saltVerifier)
        → used ONLY by verifyPin() for the "is this the right password" UI check
        → NEVER passed to any encrypt/decrypt function
        → its compromise alone yields nothing usable against MK or note data
```

## 3. Key Hierarchy — explicit definitions

### Master Key (MK)
- **Purpose:** the single symmetric key that directly encrypts/decrypts all note bodies and the GitHub token.
- **Generation:** `Random.secure()`, 256 bits, once, at first password setup. Never regenerated except in an explicit, user-initiated "reset everything" scenario (out of scope here).
- **Storage:** never stored in plaintext, anywhere, ever. Only its **wrapped forms** are stored (see below).
- **Lifetime:** effectively permanent — survives password changes, device additions, recovery events. Regenerating it would orphan all existing ciphertext, so it is treated as immutable once created.
- **Protects:** note bodies, GitHub token, and (by design, extensibly) any future sensitive value.
- **Protected by:** Password-KEK-wrap, Recovery-KEK-wrap, and optionally Hardware-wrap (see below) — at least one wrap must always be unlockable, ideally two.
- **Exportable:** in wrapped form only, as part of `device_key.json` (Password-KEK-wrap and Recovery-KEK-wrap of MK both travel to GitHub — see Section 4). Never exported unwrapped.
- **If local storage is extracted:** attacker gets only wrapped blobs. Without the password or the recovery phrase, MK cannot be recovered — this is the entire point of the redesign.

### Password-KEK
- **Purpose:** a key-encryption-key, derived from the password, whose only job is to wrap/unwrap MK.
- **Generation:** `Argon2id(password, saltKEK, params)` — fresh `saltKEK`, generated once at setup, independent of every other salt in the system.
- **Storage:** never stored — derived fresh from the typed password every time it's needed. Only `saltKEK` (public, non-secret) and the resulting wrapped-MK blob are stored.
- **Lifetime:** exists only transiently, in memory, for the duration of a wrap/unwrap operation. Zeroed immediately after (via `SecureBytes`, matching the existing pattern).
- **Protects:** MK (specifically, one wrapped copy of it).
- **Protected by:** the strength of the password itself + Argon2id's cost.
- **Exportable:** no — it's never stored, only ever recomputed.
- **If local storage is extracted:** attacker gets `saltKEK` and the wrapped-MK blob. Recovering MK requires successfully guessing the password and re-deriving Password-KEK — the mandatory, non-skippable step that Finding 3A currently allows bypassing entirely.

### Password Verifier
- **Purpose:** exclusively for the "is this the correct password" UI check (`verifyPin`). Structurally identical in *construction* to today's `system_crypto_pin`, but with one critical change: **its output is never passed to anything else.**
- **Generation:** `Argon2id(password, saltVerifier, params)` — a **separate salt** from `saltKEK`, generated once at setup.
- **Storage:** `base64(saltVerifier):base64(verifierHash)`, stored in `rocen_settings_box` (successor to today's `system_crypto_pin` key name, or reusing the name with new semantics — a naming decision, see Section 15).
- **Lifetime:** permanent until password change (regenerated with the new password + a fresh salt at that time).
- **Protects:** nothing downstream — it exists purely as an authentication oracle.
- **Protected by:** nothing needs to protect it; it's meant to be comparison-only. Its extraction is the normal, expected "attacker has a crackable password hash" scenario every password system has — the redesign's entire point is that this specific extraction no longer also yields data access.
- **Exportable:** it's already "exported" in the sense of being stored locally; it never travels to GitHub (no reason to).
- **If local storage is extracted:** attacker gets a standard salted-Argon2id hash to offline-attack, exactly like any password verifier anywhere — and **critically, succeeding at that attack recovers only the ability to pass `verifyPin()`, not the ability to decrypt anything**, since this value is cryptographically unrelated to Password-KEK (different salt, and per the "do not derive two things from the same salt" principle, structurally non-transferable even though both derive from the same password).

### Recovery-KEK
- **Purpose:** a second, independent way to unwrap MK, usable when the password is known but the device is new (no local Password-KEK-wrapped MK cached yet) — or, combined with the mnemonic, when recovering from a lost/reset device.
- **Generation:** `Argon2id('$password|${mnemonicWords.join(' ')}', saltRecovery, params)` — this is exactly today's `combinedSecret` construction in `wrapDeviceKeyWithParams`, reused as-is (it's already correctly independent — no change needed to *this* derivation, only to *what it wraps*).
- **Storage:** never stored — derived fresh from password + mnemonic when needed. Only `saltRecovery` (public) and the resulting wrapped-MK blob are stored.
- **Lifetime:** transient, same as Password-KEK.
- **Protects:** MK (a second wrapped copy).
- **Protected by:** password strength + mnemonic's 128 bits of entropy, combined.
- **Exportable:** the wrapped-MK-via-Recovery-KEK blob is exactly what travels to GitHub as (the redesigned) `device_key.json`.
- **If local storage is extracted:** irrelevant on its own — this value is never stored locally in the first place; the *wrapped MK blob* it protects lives on GitHub, and recovering MK from it requires both the password and the physical/memorized mnemonic, neither of which local extraction yields.

### Hardware-backed key (Android Keystore/StrongBox)
- **Purpose:** an optional, additional, device-local wrap of MK that lets the app unlock MK on a *known, already-set-up* device without re-deriving Password-KEK every single time (a UX/performance convenience — Argon2id at the hardened tier is deliberately slow) — while adding a genuine hardware-isolation boundary.
- **Generation:** `MainActivity.kt`'s existing `getOrCreateHwKey(masterKeyAlias)` pattern, StrongBox-first with TEE fallback — reused mechanism, new alias, new payload (wraps MK directly, not a password hash).
- **Storage:** the hardware-wrapped-MK blob is stored locally (`rocen_settings_box`); the actual AES key never leaves Keystore/StrongBox.
- **Lifetime:** tied to the device; regenerated if the Keystore entry is ever invalidated (e.g., biometric enrollment change, factory reset).
- **Protects:** MK (a third, device-local-only wrap — never synced to GitHub, since it's meaningless on any other device).
- **Protected by:** Android's hardware security boundary.
- **Exportable:** no, by Android Keystore design — the underlying AES key cannot be extracted even by the app itself.
- **If local storage is extracted (no root):** the wrapped blob alone is useless without the Keystore-resident key, which a cold filesystem copy cannot include.
- **If local storage is extracted (rooted, per Attacker C):** on a StrongBox-backed device, the key still cannot be extracted (secure-element isolation); on TEE-only, the *ability to invoke* the key may be reachable by a sufficiently privileged attacker, consistent with the existing, already-documented Attacker-C limitation — this redesign does not change that ceiling, it only ensures the *fallback path* (Password-KEK, Recovery-KEK) is never weaker than intended when hardware-wrap isn't available or fails.

## 4. Secret-Storage Model

| Value | Location | Plaintext or encrypted | Protected by | Why stored | Recoverable from local storage alone? | What an extraction attacker gets |
|---|---|---|---|---|---|---|
| Password Verifier | `rocen_settings_box` | Plaintext-stored Argon2id hash (standard verifier pattern) | Nothing (by design — it's the auth anchor) | Enables local "is this the right password" check without network | N/A — it's a hash, not directly reversible | A crackable verifier, same as any password system; success yields nothing beyond passing `verifyPin()` |
| `saltKEK` | `rocen_settings_box` | Plaintext (non-secret, salts are always public) | N/A | Needed to re-derive Password-KEK from the password | N/A | Nothing useful alone |
| Wrapped MK (Password-KEK) | `rocen_settings_box` | Ciphertext (AES-GCM) | Password-KEK (requires the real password to unwrap) | The normal, everyday unlock path | **No** — requires the password | An opaque blob; useless without correctly guessing the password |
| `saltRecovery` | `rocen_settings_box` locally, and inside `device_key.json` on GitHub | Plaintext | N/A | Needed to re-derive Recovery-KEK | N/A | Nothing useful alone |
| Wrapped MK (Recovery-KEK) | `device_key.json` on GitHub (not stored locally — no local need for it under normal operation) | Ciphertext | Recovery-KEK (requires password + mnemonic) | Cross-device/lost-device recovery | No | An opaque blob; useless without both password and mnemonic |
| Wrapped MK (Hardware) | `rocen_settings_box` | Ciphertext | Android Keystore/StrongBox key | Fast unlock on a known device without re-running Argon2id every time | No (key never leaves Keystore) | An opaque blob; useless without the Keystore-resident key |
| GitHub token | `rocen_settings_box` | Ciphertext, encrypted **directly with MK** (not a password-derived value) | MK | Needed to authenticate to GitHub | No — requires MK, which requires the password/mnemonic/hardware-unlock | An opaque blob; recovering it requires the same effort as recovering MK itself — **no shortcut via the verifier, unlike today** |
| Device ID | `rocen_settings_box`, and (per the earlier audit's P-1 recommendation, independently worth doing) NOT published remotely — only `deviceNumber` is | Plaintext | N/A — not a secret | Local bookkeeping for multi-device coordination | N/A | Reveals nothing beyond "this app is installed here" |
| Recovery metadata (`known_password_generation`, pending-publish flags) | `rocen_settings_box` | Plaintext | N/A — not secrets | Coordination bookkeeping | N/A | Nothing security-relevant |
| Note data (unencrypted type) | `rocen_captures_box` | Plaintext | N/A (explicitly user-chosen unlocked type) | User's own choice | N/A — meant to be plaintext | Full note content, as intended by the user's own choice of note type |
| Note data (encrypted type) | `rocen_captures_box` | Ciphertext, AES-256-GCM directly under MK, AAD-bound to note ID | MK | The actual protected data | **No** — requires MK | An opaque, AAD-protected blob; recovering content requires recovering MK first, which requires the password or mnemonic |
| Note title (any type) | `rocen_captures_box` | **Decision point — see Section 15.** Recommended: kept as plaintext but **authenticated** (bound into the note's AAD) rather than encrypted | AAD binding (integrity only, not confidentiality) under the recommended design | Needed for list display without a decrypt-and-render cost on every scroll | Readable, but tamper-evident | Title text is visible; cannot be swapped for a different note's title/ciphertext pairing without detection |
| Encryption envelope metadata (version, KDF params, salts, nonce) | Stored alongside each ciphertext (see Section 5) | Plaintext (metadata is meant to be public/self-describing) | AAD-authenticated where relevant | Enables self-contained decryption independent of device state | N/A — not secret | Learns the KDF cost tier and format version used; no more sensitive than a modern password hash format string (e.g., `$argon2id$v=19$m=...`) already publicly reveals |

## 5. Encryption Envelope v2

```
┌──────────────────────────────────────────────────────────────────┐
│ Byte 0:        formatVersion        (1 byte, = 2)                 │
│ Byte 1:        keyVersion           (1 byte — which MK generation,│
│                                       supports future MK rotation)│
│ Byte 2:        algorithmId          (1 byte, = 1 for AES-256-GCM) │
│ Byte 3:        kdfAlgorithmId       (1 byte, = 1 for Argon2id —   │
│                                       only relevant for wrap      │
│                                       envelopes, see note below)  │
│ Bytes 4-7:     kdfMemory            (uint32, only in wrap         │
│                                       envelopes; 0 for note/token │
│                                       envelopes, which use MK     │
│                                       directly with no KDF step)  │
│ Bytes 8-11:    kdfIterations        (uint32, same condition)      │
│ Next 16 bytes: salt                 (only present in wrap         │
│                                       envelopes; absent/zero-     │
│                                       length for note/token       │
│                                       envelopes since MK is used  │
│                                       directly, no derivation)    │
│ Next 12 bytes: nonce                (always present)              │
│ Next N bytes:  AAD-length-prefixed  (see below — this is the      │
│                AAD block             canonical AAD actually used, │
│                                       stored so decrypt doesn't    │
│                                       need to reconstruct it from  │
│                                       possibly-mutated surrounding │
│                                       app state)                  │
│ Next 16 bytes: authentication tag   (AES-GCM's own MAC)           │
│ Remaining:     ciphertext                                         │
└──────────────────────────────────────────────────────────────────┘
```

**Important distinction this format makes explicit that today's format doesn't:** there are two different *kinds* of envelope, sharing the same outer structure —
- **Wrap envelopes** (Password-KEK-wraps-MK, Recovery-KEK-wraps-MK) *do* need `kdfMemory`/`kdfIterations`/`salt`, because unwrapping requires re-deriving a KEK from the password/mnemonic.
- **Data envelopes** (MK-encrypts-note, MK-encrypts-token) do **not** need any KDF fields at all, because MK is used *directly* as the AES-256-GCM key with no derivation step — this is precisely what eliminates Finding 3C's entire failure class for actual note/token data: there is no "current device state" to consult during note decryption anymore, only "do I have MK unwrapped in memory right now."

**AAD content, canonical form:** `AAD = utf8Encode('rocen:v2:${noteId}:${generation}')` where `generation` is the note's own monotonically-incrementing revision counter (new field on `CaptureItem`, starts at 1, increments on every re-encryption of that note) — this simultaneously closes the metadata-tamper gap (3D) and gives a real, per-note anti-replay binding (Section 9's finding): a stale ciphertext blob from generation 3 cannot be successfully decrypted once the app expects generation 5 for that note ID, because the AAD used at decrypt time won't match what's embedded in the stale blob's own stored AAD field, causing an authentication failure rather than a silent stale-content acceptance.

**What's encrypted:** note body content only (matches the current, presumably-intentional product decision that "locking" a note protects its body).

**What's authenticated but not encrypted:** the note ID and generation counter (via AAD), plus — per the recommendation below — the title.

**What's pure public metadata:** format version, key version, algorithm IDs, KDF parameters (for wrap envelopes), salts, nonces. None of this is secret; all of it needs to be readable before decryption can even be attempted.

**What's immutable once written:** `formatVersion`, `keyVersion`, `algorithmId`, salt, nonce — none of these should ever be edited in place; a content update produces an entirely new envelope (new nonce mandatorily, since nonce reuse under the same key is the one unforgivable AES-GCM mistake) with an incremented `generation`.

**Tamper detection:** any modification to ciphertext, the stored AAD block, or the tag itself causes AES-GCM's built-in tag verification to fail during decrypt — surfaced as a typed `EnvelopeAuthenticationFailure`, distinct from `WrongPasswordFailure` (see Section 11) so the app can tell these apart, which today's single `'DECRYPTION FAULT'` string cannot.

### Title: encrypted vs. authenticated-only — recommendation

**Recommend: title stays visible, but authenticated (bound into AAD), not encrypted.**

Reasoning: encrypting the title would require decrypting *every visible note* just to render a scrollable list — a real, felt performance cost for a mobile list view, and a UX regression from what the app does today (titles are always readable). The actual security gap being closed here isn't "titles must be hidden," it's "titles must not be silently swappable without detection" — which authenticated-but-visible fully solves. If a future product decision wants hidden titles too, that's a separable, additive change (a second small encrypted blob for title, independent of this redesign) — not something this fix should bundle in and thereby complicate.

## 6. Password-Change Flow

**Master Key: unchanged.** This is the entire point of the redesign — MK is never regenerated on a password change.

**What changes:**
- Password Verifier: regenerated (`Argon2id(newPassword, freshSaltVerifier)`), replacing the stored value.
- Password-KEK: implicitly changes (it's derived from the password, never stored) — meaning the **wrapped-MK-via-Password-KEK blob must be re-wrapped**: unwrap MK using the *old* Password-KEK, re-wrap it using a *newly-derived* Password-KEK (fresh `saltKEK`, new wrap envelope). This is a single AES-GCM unwrap + rewrap of a 256-bit key — computationally trivial, nothing like re-encrypting every note.
- Recovery-KEK wrap: **only needs updating if the user also wants their recovery phrase's protection to reflect the new password** (since Recovery-KEK is derived from `password|mnemonic`). This should happen in the same operation, for consistency — otherwise a user's mnemonic + *old* password could still unwrap MK via the stale Recovery-KEK wrap, which is a real, avoidable inconsistency (not a security hole per se, since both old and new password are things "the legitimate user has known," but confusing and worth avoiding). Recommend: always re-wrap both Password-KEK and Recovery-KEK together, atomically, in every password change.
- Hardware wrap: re-wrap using the existing hardware key (no new Keystore key needed) — MK hasn't changed, only trivially re-encrypt the same MK bytes under the same Keystore-resident key (this step is actually a no-op if the hardware key itself hasn't changed — could genuinely be skipped entirely, since re-wrapping identical plaintext under an identical key with the *same* key material produces no security benefit; only worth doing if the implementation prefers a fresh nonce for hygiene, which is optional and low-priority).

**Notes needing re-encryption: none.** Since notes are encrypted directly with MK, and MK is unchanged, **every existing note's ciphertext remains valid and decryptable immediately after a password change, with zero re-encryption work.** This directly fixes 3F and is the single biggest practical win of the redesign.

**GitHub data needing rewriting:** only `device_key.json`'s wrapped-MK-via-Recovery-KEK blob (if the Recovery-KEK is being refreshed as recommended above), plus `password_state.json`'s normal generation-increment bookkeeping (unchanged from today's existing, already-correct flow).

**Interruption/crash safety:** this reuses the exact pending-state pattern already built and verified working this session (`PendingReason`, `retryDeviceKeyPublish`, the `deviceKeyNotReady` CONTINUE flow) — the sequence should be: (1) derive new Password-KEK, re-wrap MK locally, commit locally *before* touching anything remote; (2) update the verifier locally; (3) attempt the Recovery-KEK re-wrap and GitHub publish, and if *that* step fails/is interrupted, the device is left in exactly the same well-understood "pending" state the existing mechanism already handles correctly — the local password change (steps 1-2) has already succeeded and notes remain fully accessible throughout, which is a strictly safer intermediate state than today's design (where an interrupted password change under the *current* architecture leaves notes re-encrypted with a *new* value but the device-key-wrap potentially stale — this redesign's local-first ordering removes that specific class of risk entirely, since local note access never depends on the remote step succeeding at all).

## 7. Recovery Flow

**How the recovery phrase derives protection:** unchanged mechanism from today (`combinedSecret = password|mnemonic`, Argon2id, fresh salt) — but now it wraps **MK** instead of wrapping an "auth salt" that then has to be used to reconstruct a verifier-equivalent value. This is a meaningful simplification: today's recovery flow's *output* (an unwrapped auth salt) still has to go through another derivation step to become useful; the redesign's recovery flow's output (unwrapped MK) is **immediately, directly usable** to decrypt notes and the token — no further derivation needed.

**Is a separate Recovery-KEK needed?** Yes — and it already effectively exists in today's code as the `combinedSecret`-derived key inside `wrapDeviceKeyWithParams`; the redesign reuses this exact derivation, just changes what it wraps (MK, not an auth salt).

**How MK is recovered:** on a new/reset device: user enters password + 12-word mnemonic → app fetches `device_key.json` from GitHub → re-derives Recovery-KEK from `password|mnemonic` + the fetched `saltRecovery` → unwraps MK from the fetched blob → MK is now available in memory → app can immediately decrypt notes (pulled from GitHub) and the token.

**What gets stored remotely:** `saltRecovery` (public), the Recovery-KEK-wrapped-MK blob (ciphertext), device coordination metadata (unchanged from today).

**What never gets stored, anywhere, in any form:** the raw mnemonic words, the raw password, `combinedSecret`, MK itself in unwrapped form. This matches today's already-correct behavior (Part 1, Section 3G confirmed the mnemonic is never persisted) — the redesign doesn't need to change this property, only preserve it.

**Keeping the raw phrase out of persistence/logs:** identical to today's approach — generated, displayed once, held only as transient `List<String>`/`String` values subject to normal Dart GC, explicitly not logged anywhere (confirmed absence of any logging call site touching mnemonic values). The known, already-documented limitation (Dart `String`s can't be explicitly zeroed) is unchanged by this redesign and remains a separately-tracked, lower-priority item.

**If the user loses the recovery phrase:** exactly as today — the Recovery-KEK path becomes permanently unusable (there is no way to regenerate a lost mnemonic's protection without the mnemonic itself), but the Password-KEK path remains fully functional as long as the password is remembered and at least one device retains its local Password-KEK-wrapped-MK blob. **This is strictly better than today**, where losing the mnemonic combined with needing a new device is a harder recovery scenario than losing it while keeping the same device, because today's local password-based access and remote recovery-based access aren't unwrapping the *same* underlying secret through two independent doors the way this redesign's MK is.

**If the user forgets the password:** if the mnemonic is available, recovery proceeds via Recovery-KEK exactly as designed. If **both** are lost, MK is permanently unrecoverable, by design — this is the correct, expected outcome for a genuinely zero-knowledge encryption scheme, not a bug to work around.

**No bypass introduced:** recovery still requires possessing *both* the password and the mnemonic (for the Recovery-KEK path) or just the password (for the Password-KEK path, only usable on a device that already has a local wrap) — there is no third, weaker path introduced anywhere in this design.

## 8. Multi-Device Flow

```
Device A (already set up, has local Password-KEK-wrapped-MK and Hardware-wrapped-MK)
   │
   │  creates/edits an encrypted note
   │  → MK (already unwrapped in memory after this session's unlock) encrypts note directly
   │  → pushes ciphertext + envelope metadata to GitHub, exactly as today's sync flow already does
   ▼
GitHub repository (unchanged sync mechanism, new envelope format)
   ▲
   │  Device B (new device, no local MK wrap of any kind yet)
   │  → user enters password + mnemonic
   │  → fetches device_key.json, derives Recovery-KEK, unwraps MK
   │  → MK now held in memory on Device B
   │  → pulls the same note ciphertext from GitHub
   │  → decrypts directly with MK — no KDF parameter negotiation needed at all,
   │    because note envelopes never depended on any device's KDF tier in the first place
   │  → Device B then creates its OWN local Password-KEK-wrap of MK (derived using
   │    whatever KDF tier — standard or hardened — Device B's own root-detection
   │    determines) and its OWN Hardware-wrap (if Device B has StrongBox/TEE),
   │    so subsequent unlocks on Device B don't need the mnemonic again
   └──────────────────────────────────────────────────────────────────────────
```

**New device enrollment:** exactly the recovery flow (Section 7) — there's no separate "enrollment" mechanism needed; recovering MK onto a device *is* enrollment.

**Device-key handling:** `device_key.json`'s role is simplified and clarified — it exists solely to let *any* device with the password+mnemonic recover MK; it is not otherwise consulted during normal operation.

**Password-change propagation:** per Section 6, a password change on Device A re-wraps MK under a new Password-KEK and (optionally, recommended) a new Recovery-KEK, publishing the updated `device_key.json`. Device B, on its next sync, sees the generation bump via the existing `password_state.json` mechanism (unchanged), and if Device B's *local* Password-KEK-wrapped-MK still unwraps correctly (it does — MK didn't change, only Device A's wrap did; Device B's own local wrap, made under Device B's own remembered password, is unaffected *unless* the user is also changing their password from Device B's perspective, in which case Device B needs the same local re-wrap Device A got) — **Device B does not need to re-derive or re-fetch anything for existing notes to keep working**, since MK, the actual decryption key, never changed.

**Recovery on a second device:** identical to "new device enrollment" above — no special case needed.

**Different KDF/security tiers across devices:** this is the redesign's key structural win for Section G's explicit requirement. Because **note/token envelopes carry no KDF dependency at all** (MK is used directly), a Standard-tier phone and a Hardened-tier (rooted-flagged) tablet can freely read and write the *same* notes with **zero compatibility concern** — the only place KDF tier matters at all is in each device's own *local* Password-KEK wrap, which is purely local, purely about how *that device* protects its own cached copy of MK, and never needs to match any other device's choice.

**What must be identical across devices:** MK itself (obviously), the note ciphertext/envelope format version understanding (all devices must support the same `formatVersion`, or reject gracefully — Section 10).

**What can be device-specific:** KDF tier (standard/hardened) for that device's *own* local wraps, whether hardware-wrapping is available/used, `deviceNumber`/`deviceId` bookkeeping.

**Hardware protection's interaction with the shared MK:** purely additive and purely local — a device's hardware wrap is never synced, never relied upon by any other device, and its absence/failure on any given device simply means that device falls back to deriving Password-KEK from the typed password every unlock (slower, not less secure) rather than affecting MK's availability elsewhere at all.

## 9. `_isHardened()` Strategy

Direct answers to your four questions:

**Should `_isHardened()` still control decryption?** **No, not for data envelopes (notes, token).** Once MK-direct-encryption is in place, decrypting a note/token never needs to know or care about any "hardened" flag at all — it just needs MK, which is either already unwrapped in memory or needs unwrapping via Password-KEK/Recovery-KEK/Hardware-wrap, none of which read `_isHardened()` at the *note-decryption* layer.

**Should it only influence creation of NEW encrypted data?** More precisely: **it should only influence how a device chooses parameters for its own local Password-KEK derivation** (and, if Recovery-KEK re-wrap parameters are ever chosen per-device rather than fixed, that too) — not "new encrypted data" in the note/token sense, since that data no longer has a KDF step at all. This is a meaningfully narrower scope than today, where `_isHardened()` currently gates note/token encryption directly.

**Should decryption always read its exact KDF parameters from the encrypted envelope?** **Yes, for wrap envelopes** (Password-KEK-wrap, Recovery-KEK-wrap) — this is exactly Finding 3C's fix, now scoped correctly: it only needs to apply to the two wrap envelopes, not to every note, since notes no longer have a KDF step to record parameters for in the first place. This is a smaller surface to fix than originally scoped, which is a genuine simplification this redesign produces as a side effect.

**After the v2 envelope exists, can `_isHardened()` safely fail closed to `true`?** **Yes — and at that point, this becomes fully safe with no caveat**, unlike the interim state we deliberately held off on last session. Once wrap envelopes are self-describing (carry their own `kdfMemory`/`kdfIterations`), a transient `_isHardened()` failure during a *future* wrap operation can never cause a cross-operation mismatch, because every unwrap reads the parameters that specific wrap was actually created with, not whatever `_isHardened()` says *right now*. This directly resolves the concern that made us correctly defer `_isHardened()`'s own fail-open fix last session — the fix to `_isHardened()` should ship *as part of* this master-key/envelope-v2 work, not before it and not as an awkward standalone patch.

## 10. Future-Versioning Strategy

- **Crypto format versioning:** `formatVersion` byte in every envelope (starts at 2, since 1 already existed informally). A new format version is introduced only when the envelope *structure itself* changes (new fields, different field order/sizes).
- **Key versioning:** separate `keyVersion` byte, tracking *which generation of MK* a given envelope was encrypted under — this is deliberately independent of `formatVersion`, since MK could theoretically be rotated (a future, currently out-of-scope feature — e.g., "I suspect my MK is compromised, generate a new one and re-encrypt everything") without the envelope *structure* changing at all. Building this field in now, even though MK rotation isn't being implemented today, costs nothing and avoids a second breaking format change later purely to add a field that could have existed from day one.
- **Migration markers:** a per-installation `crypto_schema_version` value in `rocen_settings_box`, distinct from any individual envelope's version, tracking "has this device's *local wraps* (not its notes) been migrated to the new scheme yet."
- **Detecting new versions:** the decrypt path always reads `formatVersion` first, byte zero, before attempting anything else — exactly as today's single-version check already does, just now with real branching logic instead of a bare equality-or-throw.
- **Unsupported versions fail how:** a `formatVersion` the running app doesn't recognize throws a typed `UnsupportedEnvelopeVersionException` immediately, surfaced to the user as "this data requires a newer version of the app" — never silently attempting a best-effort interpretation.
- **Atomic, recoverable future migrations:** any future format bump should follow the same principle used in Section 6's password-change design — write the new format's data successfully and confirm it before ever deleting/invalidating the old format's data, so an interrupted migration leaves the *old*, still-fully-functional data intact rather than a half-migrated, broken state.
- **Avoiding silent downgrade:** the decrypt path never "falls back" to an older, weaker interpretation of newer data, and — symmetrically — the *encrypt* path always uses the current app version's preferred format/KDF tier for anything newly created, never an older, weaker one, regardless of what format any of the user's *existing* data happens to be in.

## 11. Failure Behavior

| Failure | Behavior |
|---|---|
| Wrong password | `verifyPin()` returns `false` (unchanged from today — correctly fail-closed already). Separately, attempting to unwrap MK via Password-KEK with a wrong password fails the AES-GCM tag check on the wrap envelope, throwing a typed `WrongPasswordFailure` — never returns partial/garbage key material. |
| Corrupted Master Key wrapper | AES-GCM tag check on the wrap envelope fails → typed `CorruptedWrapperFailure`, distinct from `WrongPasswordFailure` so the UI can say "this looks corrupted" rather than "check your password" — a real diagnostic improvement over today's single ambiguous string. |
| Corrupted ciphertext (note/token) | AES-GCM tag check fails on the data envelope → typed `CorruptedDataFailure`. Original file/local copy is never deleted or altered on this path. |
| Wrong AAD | Tag check fails (AAD is authenticated as part of the same GCM operation) → same `CorruptedDataFailure`/`TamperDetectedFailure` category — this is precisely how the substitution/tamper attack from Finding 3D becomes detectable rather than silent. |
| Invalid KDF parameters (e.g., a wrap envelope claims an absurd `kdfMemory`) | Reject before attempting derivation if parameters fall outside a sane, hardcoded bound (e.g., reject anything above what `_authParamsHardened`/`_encryptionParamsHardened` would ever legitimately use) — prevents a malformed/malicious envelope from triggering an OOM via an attacker-chosen enormous memory-cost value. |
| Unsupported crypto version | `UnsupportedEnvelopeVersionException`, surfaced plainly (Section 10). |
| Missing key (MK never unwrapped this session) | The app should never attempt a note operation without MK already resident in memory — any code path reaching a decrypt call without MK available is treated as an internal logic error (assertion failure in debug, a generic "please unlock again" prompt in release), not a security decision point. |
| Android Keystore failure | Falls back to requiring Password-KEK derivation (typed password) for that unlock — exactly today's `hardwareWrap`/`hardwareUnwrap` returning `null` and the caller correctly falling back, a pattern already proven correct in the current codebase and reused unchanged. |
| StrongBox unavailable | Falls back to TEE-only, exactly as `getOrCreateHwKey` already does today — unchanged, already correct. |
| Recovery failure (wrong password/mnemonic combination during recovery) | AES-GCM tag check fails on the Recovery-KEK wrap envelope → typed `RecoveryFailure`, with no partial/degraded MK ever produced. |
| GitHub backup corruption (malformed `device_key.json`) | Rejected by the same structural validation `password_state_manager.dart` already applies to `password_state.json` (missing/wrong-typed fields → `FormatException`) — reuse that exact, already-correct pattern for `device_key.json`'s new fields too. |
| Partial sync (some notes updated, `device_key.json` not yet) | Because MK never depends on sync completion (it's already resident in memory once unwrapped, regardless of what's synced), a partial sync cannot ever leave notes undecryptable locally — only remotely-fetched notes on *other* devices might be stale until sync completes, which is an availability/freshness concern, not a decryption-failure risk. |
| Application crash during key update (mid password-change) | Per Section 6's local-first ordering, a crash before the local re-wrap commits leaves the old wraps fully intact (nothing was destroyed yet); a crash after the local re-wrap commits but before the remote publish leaves the device in the existing, already-correctly-handled `deviceKeyNotReady`-equivalent pending state — notes remain accessible throughout either way. |

**Global principle enforced throughout:** every failure category above produces a **distinct, typed exception**, never a single ambiguous string — this alone is a meaningful diagnosability improvement over today's `'DECRYPTION FAULT'` catch-all, without requiring any UI-facing wording decisions to be made in this design pass.

## 12. Security Test Plan

Mapped directly to your sixteen required cases:

1. **Extracted old `system_crypto_pin`-equivalent (the new Password Verifier) cannot decrypt a v2 note** — attempt `encryptProcess`/`decryptProcess`-style direct use of the verifier's stored value as a key input; assert it fails, since v2's data envelopes require MK, not a password-derived hash, and the verifier is never wired into the unwrap path at all.
2. **Correct password unlocks the Master Key** — full happy path: derive Password-KEK, unwrap MK, confirm it matches the MK used at setup time (compare against a test fixture, never by re-deriving — MK should never be re-derivable, only unwrappable).
3. **Wrong password cannot unwrap the Master Key** — assert `WrongPasswordFailure`, assert no MK-shaped value is ever returned, not even a wrong one.
4. **Password change preserves access to existing notes** — encrypt a note before a password change, change the password, decrypt the same note afterward with the new password; assert success with zero re-encryption calls made (instrument/mock the note-store layer to assert `migrateEncryptedNotes`-equivalent is never invoked).
5. **Password change does not unnecessarily re-encrypt all notes** — same test as #4, explicitly asserting the note ciphertext bytes are byte-identical before and after the password change (proving no re-encryption touched them at all).
6. **Recovery restores access to the same Master Key** — wrap MK via Recovery-KEK, simulate a "new device" (fresh in-memory state, no cached Password-KEK wrap), unwrap via password+mnemonic, assert the recovered MK matches the original test fixture exactly.
7. **KDF parameters can change between devices without breaking existing ciphertext** — encrypt a note under a "Device A, standard tier" fixture; simulate "Device B, hardened tier" (different `_isHardened()` value) decrypting the same note; assert success, since note envelopes carry no KDF dependency.
8. **Modified AAD causes authentication failure** — take a valid v2 note envelope, mutate one byte of the stored AAD field, attempt decrypt, assert `TamperDetectedFailure`/tag-check failure.
9. **Ciphertext moved to another note ID causes authentication failure** — take Note A's full envelope (including its AAD, which encodes Note A's ID), attempt to decrypt it while asserting/expecting Note B's ID; assert failure, since the AAD comparison at decrypt time won't match.
10. **Corrupted envelope fields fail safely** — for each field (version byte, salt, nonce, tag, ciphertext), flip a bit and assert a typed failure is thrown, never a crash, never a plausible-looking wrong plaintext.
11. **Unsupported version fails closed** — set `formatVersion` to a value the app doesn't recognize (e.g., `99`); assert `UnsupportedEnvelopeVersionException`, never an attempt to interpret it as v1 or v2 by guessing.
12. **Standard device can decrypt hardened-device ciphertext** — same as test #7, one specific direction.
13. **Hardened device can decrypt standard-device ciphertext** — same as test #7, the other direction.
14. **Interrupted password change is recoverable** — simulate a crash/interruption between the local re-wrap commit and the remote `device_key.json` publish; assert (a) notes remain fully decryptable locally throughout, and (b) the existing pending-state mechanism correctly detects and offers to complete the interrupted remote step on next launch.
15. **Interrupted key-wrapping update is recoverable** — narrower version of #14, specifically simulating a crash *during* the local Password-KEK re-wrap write itself (e.g., process killed mid-`Hive.put`); assert the *old* wrap remains valid and MK remains unlockable with the *old* password (transactional "don't destroy the old wrap until the new one is confirmed written" ordering).
16. **Hardware-backed protection failure does not silently weaken the cryptographic design** — force `hardwareWrap`/`hardwareUnwrap` to fail; assert the app falls back to full Password-KEK/Recovery-KEK derivation (the same strength as if hardware wrapping were never attempted at all) rather than, say, silently storing MK in a weaker or unwrapped form as a "just make it work" fallback.

## 13. File Impact

**MUST CHANGE**
- `crypto_engine.dart` — the core of the redesign: MK generation, Password-KEK/Recovery-KEK derivation and wrap/unwrap functions, envelope v2 read/write, verifier separated from encryption entirely, `_isHardened()`'s scope narrowed per Section 9.
- `crypto_isolate.dart` — needs a new isolate-dispatched function for "encrypt/decrypt directly with a given key" (no KDF step) for data envelopes, alongside the existing KDF-then-encrypt functions (still needed for wrap envelopes).
- `database.dart` — `CaptureItem` needs a `generation` field for AAD binding (Section 5); `migrateEncryptedNotes` is no longer needed as a password-change mechanism (Section 6) — it should be removed or repurposed, not left as dead/misleading code.
- `settings.dart` — every call site currently doing `CryptoEngine.encryptProcess(payload, pinHash)` for notes/token needs to instead request MK (already-unwrapped, held in whatever the app's session-scoped "unlocked" state ends up being) and use the new direct-encrypt path; the password-change flow needs the new local-first re-wrap sequencing (Section 6).
- `password_state_manager.dart` — `device_key.json`'s schema needs the new Recovery-KEK-wrapped-MK blob field, replacing/supplementing today's wrapped-auth-salt field.
- `quicknote.dart` — note save/load call sites need updating to the new encrypt/decrypt API shape.

**MAY CHANGE**
- `MainActivity.kt` — likely needs a new Keystore alias (`masterKeyAlias`) alongside the existing `passwordKeyAlias`/`githubTokenKeyAlias`, but the `hwEncrypt`/`hwDecrypt`/`getOrCreateHwKey` mechanism itself is reusable as-is.
- `github_backup_service.dart` — only if `device_key.json`'s upload/fetch call sites need shape changes beyond what `password_state_manager.dart` already handles internally; possibly no change needed here at all if the schema change is fully contained in the calling layer.
- `clipboard.dart`, `bookmarks.dart`, `ideainbox.dart` — only if any of these directly call `CryptoEngine.encryptProcess`/`decryptProcess` today (not confirmed in this pass — worth a targeted grep before implementation to confirm scope).

**SHOULD NOT CHANGE**
- `secure_bytes.dart`, `ram_lock.dart` — the zeroing/RAM-locking mechanism is sound and orthogonal to this redesign; MK and every derived KEK should simply be wrapped in `SecureBytes` the same way existing derived keys already are.
- `bip39.dart` — the wordlist itself, untouched by definition.
- `main.dart`, `navbar.dart` — no crypto logic lives here.
- Every UI-only file not listed above (`clipboard.dart` etc., unless the grep above proves otherwise) — this redesign is about the crypto/storage layer, not the UI, beyond the password-change/recovery screens already covered in `settings.dart`.

## 14. Implementation Risks, Ranked

1. **Password-change re-wrap sequencing (highest risk).** Getting the "commit local wrap before touching remote state" ordering wrong is the single most likely place to introduce a *new* data-loss bug while fixing an old one — this needs the most careful implementation and the most thorough interruption-testing (test cases 14-15).
2. **Key wrapping correctness (MK wrap/unwrap for all three paths).** Three independent wrap mechanisms (Password-KEK, Recovery-KEK, Hardware) all need to correctly wrap/unwrap the *same* MK bytes — a subtle bug in any one of the three (e.g., an off-by-one in envelope parsing) could silently corrupt MK on unwrap without an obvious symptom until decryption fails.
3. **Recovery flow (device_key.json schema change).** This touches the GitHub-synced format, meaning a mistake here is harder to quietly fix later than a purely-local bug — worth extra scrutiny before the schema is considered final, precisely because you've said there's no legacy-user migration burden today, meaning this is the one chance to get the schema right without a v2→v3 migration for it too.
4. **Hardware protection integration.** Reusing `getOrCreateHwKey` for a new alias is low-novelty, but StrongBox-availability edge cases are inherently hard to test comprehensively without a wide range of physical devices — moderate risk mostly from limited testability, not from design complexity.
5. **Multi-device behavior.** The design itself removes most of today's cross-device KDF-mismatch risk by construction (Section 8), which *lowers* this item's risk relative to where it'd otherwise sit — flagged as moderate rather than high specifically because the architecture is designed to make this the easy part, not despite it being hard.
6. **GitHub token migration.** Structurally identical to note encryption (same MK-direct-encrypt mechanism) — low incremental risk once note encryption itself is correctly implemented and tested, since it's the same code path with different payload content.
7. **Encrypted envelope parsing/versioning.** Mechanical, well-specified (Section 5), and testable in isolation with fixed byte arrays — lower risk than the stateful flows above precisely because it doesn't depend on timing, interruption, or multi-step coordination.
8. **Data-loss scenarios generally.** Listed last not because it's unimportant, but because it's the *outcome* the other seven risk categories feed into, not an independent risk source of its own — every test in Section 12, especially 4, 5, 14, and 15, exists specifically to catch this outcome before it reaches a real user.

## 15. Decisions Requiring Your Approval

1. **Naming/reuse of `system_crypto_pin`'s key name.** Should the new Password Verifier reuse the exact Hive key name `system_crypto_pin` (simpler, but slightly misleading now that "pin" historically implied more than just a verifier), or a new name (clearer, but touches one more place in the code)? No functional difference either way.
2. **Whether to re-wrap the Hardware wrap on every password change** (Section 6 noted this is likely an unnecessary no-op step) — confirm whether to skip it for efficiency or always refresh it for hygiene/consistency.
3. **Whether Recovery-KEK's wrap should always be refreshed alongside Password-KEK on every password change**, or only refreshed when the user explicitly opts to ("update my recovery phrase's protection too") — the design above defaults to "always," but this has a UX cost (it may require briefly re-deriving using the mnemonic, or could be deferred by keeping the *old* password usable for the Recovery-KEK path until the user explicitly re-confirms their mnemonic) that only you can weigh.
4. **Title handling: authenticated-but-visible (recommended) vs. fully encrypted.** Section 5 recommends the former; this is exactly the kind of product/privacy tradeoff the instructions say shouldn't be silently decided.
5. **Whether `keyVersion` (supporting future MK rotation) is worth building now versus deferred entirely**, given you've said no migration work for current data is needed — I've recommended including the field now since it's a single extra byte with no functional cost today, but confirm this isn't unwanted scope creep for a feature (MK rotation) that isn't otherwise being built.
6. **Exact typed-exception names/structure for Section 11's failure taxonomy** — I've proposed a shape (`WrongPasswordFailure`, `CorruptedWrapperFailure`, etc.) but haven't designed the actual Dart exception hierarchy/class structure, since that's closer to implementation than architecture — confirm you want this level of failure-mode granularity versus a simpler two-or-three-way split.
7. **Whether `migrateEncryptedNotes` should be deleted outright or left in place but unused**, given it becomes dead code under this design (Section 13) — deleting reduces confusion but touches a file path that currently has real, working logic; leaving it risks a future maintainer assuming it's still load-bearing.

This concludes the design review. No files were modified. Awaiting your approval before any implementation begins.

# PROMPT

# Architectural Specification #4 (Revised): Maximum-Security Master-Key Target Architecture

> **Mandatory Directive:** **DO NOT implement anything yet.** Do NOT modify code, create commits, or rewrite files. This document is strictly an architectural design revision pass.

## Core Guiding Principle: Maximum Cryptographic Correctness

The overarching priority for this architecture is to **maximize REAL security and cryptographic correctness**.

### Primary Non-Goals

Do **NOT** optimize primarily for:

* Convenience or minimum code changes
* Minimizing user prompts or interaction loops
* Backwards compatibility with legacy v1 flaws
* Implementation simplicity when that simplicity degrades security

*If a stronger, standard security design requires additional files, increased user interaction, or greater implementation effort, the stronger design **must** be selected and its trade-offs explicitly documented. Every security mechanism must serve a concrete, non-theatrical cryptographic purpose.*

## 1. Mandatory Recovery Requirement: Dual-Secret Authentication

The recovery model is strictly defined as:

$$\mathbf{\text{Password}} + \mathbf{\text{Recovery Mnemonic}} = \mathbf{\text{Required to Recover Master Key}}$$

### Non-Negotiable Constraints

* **Unacceptable Paths:** Mnemonic-only recovery, password-only recovery on a new device, alternative bypass paths, or remote secret escrow.
* **Failure Condition:** If **either** the password **OR** the recovery mnemonic is lost, the remote recovery path **must fail closed**.
* **Existing-Device Local Path:** An existing device may still unlock via its local hardware/password-wrapped Master Key payload without prompting for the mnemonic.

```
[ User Password ] ──────► Password-KEK  ┐
                                         ├─► Recovery-KEK ──► Unwraps Master Key
[ Recovery Mnemonic ] ──► Mnemonic Salt  ┘

```
## 2. Master-Key Architecture & Key Separation

### Core Key Isolation

* **Random 256-bit Master Key (MK):** Generated via CSPRNG, completely independent of the user password, never deterministically derived, and never stored in plaintext.
* **Separation of Concerns:** Cryptographic authentication is strictly decoupled from payload encryption. The password verifier **must never** serve as an encryption secret or password equivalent.

### Domain-Separated Key Derivation

To prevent single-key reuse across unrelated data domains, the Master Key acts as a root key to derive domain-specific subkeys using a standard HKDF/KDF construction:

```
                          ┌──► [ Note Encryption Key (NEK) ]
                          │
[ Random 256-bit MK ] ──HKDF──► [ GitHub Token Encryption Key (TEK) ]
                          │
                          └──► [ Future Application-Data Keys ]

```

## 3. Trusted Context & AAD Binding

### The Stored AAD Trust Fallacy

The application **MUST NOT** trust attacker-controlled, stored AAD headers on the disk/remote payload to determine security identity.

```
[ Stored AAD Payload ] ──► DO NOT TRUST FOR DECRYPTION CONTEXT

[ Local App Engine ]   ──► Reconstructs Expected Canonical AAD ──► Authenticates Ciphertext

```

### Canonical Context Reconstruction

For every payload (e.g., a note), the application reconstructs canonical AAD at runtime prior to AEAD tag verification:

$$\text{Canonical AAD} = \text{Domain} \parallel \text{Format Version} \parallel \text{Note ID} \parallel \text{Expected Generation} \parallel \text{Record Type}$$

* **Security Guarantee:** If an attacker moves a valid ciphertext block (including its raw stored AAD) from **Note A** to **Note B**, decryption **must fail** because the local context reconstruction for Note B will yield a non-matching AAD.

## 4. Replay & Anti-Rollback Strategy

An AAD generation tag does **not** prevent rollback if an attacker replaces an entire record along with its matching historical generation tag.

### Threat Model Analysis

```
State Vector:
  Current Note State : Generation 10 (Local / Trusted)
  Attacker Overwrite : Generation 7  (Ciphertext + Matching AAD for Gen 7)

Vulnerability:
  If the decryption engine trusts the generation supplied by the remote record,
  Generation 7 will successfully authenticate, causing a silent state rollback.

```

### Trusted State Matrix

| Field | Source / Controller | Attacker Modifiable? | Authenticated via AEAD? | Usable in Reconstructed AAD? | Trusted Source of Truth |
| --- | --- | --- | --- | --- | --- |
| **Note ID** | Application Intent | No (Causes failure) | Yes | **Yes** | Local DB / UI Context |
| **Generation Number** | Sync Engine | Yes (Remote overwrite) | Yes | **Yes** | Local Trusted Metadata |
| **Key Version** | Key Manager | Yes | Yes | **Yes** | Local Keystore / Envelope |
| **Format Version** | Code Base | Yes | Yes | **Yes** | App Code Constraints |
| **Deletion / Sync State** | Sync Engine | Yes | Partial | **No** | Local Engine State |

> **GitHub Storage Boundary Note:** GitHub is an untrusted remote transport layer. Remote state cannot be intrinsically trusted. Perfect remote anti-rollback depends on maintaining a local, immutable monotonically increasing state counter or trusted generation index.

## 5. Secret Key & Derivation Specifications

### Password KEK & Verifier Separation

```
                       ┌──► Password Verifier (Authentication Only)
                       │    (Independent Salt)
[ Raw User Password ] ─┤
                       │    Argon2id KDF
                       └──► ─────────────────► Password KEK ──► Wraps Master Key
                            (Dedicated Salt)

```

### Dual-Secret Recovery KEK Construction

Derivation of the Recovery KEK mandates explicit normalization and domain separation across both input vectors:

```
Password + Mnemonic ──► Argon2id (Normalized Inputs, Unique Salt, Domain Label) ──► Recovery-KEK

```

* **Parameters:** Mandatory `Unicode NFKD` normalization on password and mnemonic strings before derivation.
* **Persistence Policy:** The raw mnemonic string must **never** be written to disk, cached in logs, or transmitted to remote storage.


## 6. Lifecycle Operations

### Password Change Protocol

Password updates operate solely on key-wrapping layers without re-encrypting the underlying note database:

1. Input old password $\longrightarrow$ Unwrap Master Key.
2. Input new password $\longrightarrow$ Derive new `Password-KEK` & fresh `Password Verifier` with unique salts.
3. Rewrap existing Master Key with new `Password-KEK`.
4. **Recovery Wrap Handling:** Prompt user to supply the recovery mnemonic during password change to re-wrap the Master Key under the new `Recovery-KEK` (Password + Mnemonic), or document the explicit security posture trade-off.

### Hardware-Backed Protection Matrix (Keystore / StrongBox)

Hardware protection acts as an isolated, device-specific wrapping layer around the root Master Key:

$$\text{Hardware Key (StrongBox / TEE)} \longrightarrow \text{Wraps / Protects} \longrightarrow \text{Master Key}$$

* **Security Role:** Defense-in-depth, local confidentiality, and user-presence enforcement. Hardware keys **must not** wrap password verifiers directly.

## 7. Self-Describing Envelope Format V2

| Envelope Field | Secret Status | Authenticated (AAD)? | Trusted Source | Modifiable by Attacker? | Operational Purpose |
| --- | --- | --- | --- | --- | --- |
| `format_version` | Public | Yes | App Runtime | Yes (Triggers Failure) | Parser Selection |
| `key_version` | Public | Yes | App Runtime | Yes (Triggers Failure) | Master Key Lifecycle |
| `cipher_algo` | Public | Yes | App Runtime | Yes (Triggers Failure) | Cryptographic Selection |
| `kdf_params` | Public | Yes | Envelope Header | Yes (Triggers Failure) | Argon2id Tuning |
| `salt` | Public | No | Envelope Header | Yes (Tag Failure) | KDF Entropy Input |
| `nonce` | Public | No | Envelope Header | Yes (Tag Failure) | AEAD Initialization |
| `ciphertext` | Secret | Yes | Remote Storage | Yes (Tag Failure) | Encrypted Payload |
| `auth_tag` | Public | N/A | Remote Storage | Yes (Tag Failure) | Integrity Proof |


## 8. Failure Behavior & Security Test Matrix

### Security Response Rules

All security-sensitive faults **must fail closed**. Silent fallbacks to reduced KDF parameters, unauthenticated algorithms, or empty states are strictly prohibited.

```
[ Failure Condition ] ──────► [ Required System Response ]
Wrong Password               ─► Deny Access / Halt Master Key Unwrapping
Invalid Mnemonic             ─► Deny Recovery / Halt Master Key Unwrapping
Ciphertext Tampering         ─► Abort Decryption / Return Authentication Error
AAD Mismatch / Moved Note    ─► Abort Decryption / Flag Context Violation
Stale Generation / Rollback  ─► Reject State Update / Alert Sync Failure
Unsupported Crypto Version   ─► Fail Closed / Block Data Processing
Hardware Keystore Failure    ─► Fall back to Password-KEK Wrap (No Plaintext)

```

### Pre-Implementation Verification Plan

```
1. Key Isolation Tests
   ├── Verify extracted Password Verifier cannot decrypt note payload or derive KEKs.
   └── Verify Note Encryption Key (NEK) cannot decrypt GitHub Token payloads.

2. AAD & Context Binding Tests
   ├── Mutate Note ID in local context -> Assert AEAD authentication failure.
   └── Copy ciphertext block from Note A to Note B -> Assert AEAD authentication failure.

3. Recovery Pipeline Tests
   ├── Valid Password + Valid Mnemonic -> Master Key successfully unwrapped.
   ├── Valid Password + Invalid Mnemonic -> Strict failure.
   └── Invalid Password + Valid Mnemonic -> Strict failure.

4. Multi-Device & KDF Tests
   ├── Hardened Device Payload -> Standard Device Decryption (Success via Envelope Params).
   └── Standard Device Payload -> Hardened Device Decryption (Success via Envelope Params).

```

## 9. Security vs. Convenience Trade-off Analysis

| Architecture Decision | Security Benefit | UX / Cost Impact | Design Selection |
| --- | --- | --- | --- |
| **Dual-Secret Recovery** | Eliminates single-factor compromise on recovery vectors. | Higher user burden during recovery (Requires Password + Mnemonic). | **Selected (Max Security)** |
| **Domain-Separated Subkeys** | Prevents key re-use cross-contamination across payloads. | Minor key-derivation overhead via HKDF. | **Selected (Max Security)** |
| **Contextual AAD Enforcement** | Prevents ciphertext transposition between notes. | Requires rigid local state tracking for Note IDs and versions. | **Selected (Max Security)** |
| **Envelope-Driven KDF** | Allows cross-tier multi-device decryption without global flags. | Slower parsing step per envelope header. | **Selected (Max Security)** |

## 10. Required Final Deliverables Checklist

When returning the full architectural design review, address the following **20 required components**:

1. Corrected Current Architecture Trace
2. Proposed Maximum-Security Architecture Specification
3. Complete Key Hierarchy Diagram & Specification
4. Recovery Key Hierarchy & Derivation Spec
5. Hardware Key Boundary Specification
6. Trust Boundaries & Threat Model Analysis
7. Encrypted Envelope V2 Binary/JSON Layout
8. Canonical AAD Construction Engine Spec
9. Anti-Replay / Rollback Protocol and Limitations
10. Password-Change Protocol & State Machine
11. Dual-Secret Recovery Execution Flow
12. Multi-Device Interoperability & Sync Flow
13. Decoupled `_isHardened()` Realignment Strategy
14. Comprehensive Fail-Closed Failure Behavior Matrix
15. Non-Negotiable Security Test Suite Matrix
16. Comprehensive File Impact Analysis (`MUST`, `MAY`, `SHOULD NOT`)
17. Implementation Order & Dependency Sequence
18. Security-vs-Convenience Trade-off Ledger
19. Unresolved Risks & Threat Model Boundaries
20. Explicit Architectural Decision Approval Requests

# AUDIT

## Rocen Master-Key Architecture v2 — Maximum-Security Design Review

No code modified. Design only.

Before proceeding, I need to flag one genuine tension in your requirements rather than silently resolve it, per your own instruction: **Section 9 mandates "do not re-encrypt every note merely because the password changed," but Section 1's mandatory dual-factor recovery, combined with "the raw mnemonic must never be persisted," creates a real question about what happens to the Recovery-KEK wrap during a password change if the mnemonic isn't available at that moment.** I resolve this explicitly in Section 9 below rather than leaving it ambiguous — but I want it on record as a place where two of your stated priorities (no unnecessary re-encryption vs. no persisted mnemonic vs. mandatory dual-factor recovery) genuinely interact, and I chose the resolution that keeps security strongest rather than the one that's most convenient.



## 1. Corrected Current Architecture

Unchanged from my first pass in its factual claims (already traced to exact file/function/line), restated with one correction: I previously called the device-key-wrap construction "correctly separated." Under this stricter review, I need to be more precise — it's separated from the note/token key derivation, but it is **not** domain-separated in the standards sense (Section 3 below), and its recovery model today is **effectively single-factor in practice** despite requiring both inputs nominally, because `wrapDeviceKeyWithParams`'s `combinedSecret = 'password|mnemonic'` is a bare string concatenation, not a construction with defined normalization, encoding, or domain separation — a genuine gap Section 8 must fix, not just inherit.

**Trace, unchanged from before:** password → `hashPinWithSaltUsingParams` → `system_crypto_pin` (verifier, but reused as key material) → `encryptProcess(payload, pinHash)` directly encrypts notes and token → no master key exists → password change requires full re-encryption via `migrateEncryptedNotes` → recovery via `wrapDeviceKeyWithParams`'s raw string concatenation of password+mnemonic.

## 2. Proposed Maximum-Security Architecture

```
                              ┌───────────────────────────────┐
                              │   MASTER KEY (MK)               │
                              │   256-bit, CSPRNG, generated once│
                              │   NEVER derived from password    │
                              │   NEVER stored unwrapped          │
                              └────────────────┬────────────────┘
                                                │
                          HKDF-Expand(MK, info=domain-context)
                                                │
                    ┌───────────────────────────┼───────────────────────────┐
                    ▼                           ▼                           ▼
         Note Encryption Key (NEK)     Token Encryption Key (TEK)   (future domain keys,
         HKDF(MK, "rocen:v2:notes")    HKDF(MK, "rocen:v2:token")    derived the same way,
                    │                           │                    no architecture change
                    ▼                           ▼                    needed to add one)
            AES-256-GCM                  AES-256-GCM
         (per-note, AAD-bound)         (AAD-bound to "github_token")


   MK's only persisted forms are wrapped copies:

┌────────────────────────────┐  ┌─────────────────────────────────┐  ┌──────────────────────────┐
│ MK wrapped by Password-KEK  │  │ MK wrapped by Recovery-KEK        │  │ MK wrapped by Hardware key│
│ (local; everyday unlock)    │  │ (local device_key.json AND on     │  │ (local only; convenience/ │
│                              │  │  GitHub; cross-device recovery)   │  │  UX layer, see Section 10)│
└─────────────┬────────────────┘  └────────────────┬──────────────────┘  └────────────┬─────────────┘
              │                                     │                                  │
   Argon2id(password, saltKEK)          HKDF-then-Argon2id composition        Android Keystore/
   = Password-KEK                        of NORMALIZED password +              StrongBox AES key
              │                          NORMALIZED mnemonic                    (see Section 10 for
   unlocks MK when the device            = Recovery-KEK (Section 8)             exactly what this
   already has this local wrap                     │                            protects and doesn't)
                                          unlocks MK ONLY when BOTH
                                          password AND mnemonic are
                                          supplied together, at the
                                          same time, in the same
                                          operation — never separately


   Completely separate, never touching the above:

   Password Verifier = Argon2id(password, saltVerifier)
        → verifyPin() ONLY
        → cryptographically unrelated to Password-KEK (different salt, different
          declared purpose — a stolen verifier requires a full offline password
          attack, and even after winning that attack, produces nothing that
          unwraps MK, because Password-KEK's derivation was never computed or
          stored anywhere the verifier's derivation touches)
```

**Note on domain-separated subkeys (responding to Section 3 directly, evaluated honestly rather than assumed):** I initially proposed direct MK reuse across notes and the token in my first design pass. Under this stricter review, **I conclude that was the wrong choice, and domain separation via HKDF is the stronger, standards-correct design.** Reasoning:

- **Why direct reuse is weaker in principle, even if no concrete attack is demonstrated today:** using the identical 256-bit key for two cryptographically unrelated purposes (encrypting arbitrary user note content vs. encrypting a fixed-structure GitHub token) violates the standard cryptographic hygiene principle of key separation — the same key should not simultaneously protect data with different formats, different attacker-controllable structure, and different exposure contexts. Concretely: note content is partially attacker-influenced in a subtle way (a malicious note-import path, or content pasted from an untrusted source, ends up encrypted under the same key that also protects the token) — if any future bug or chosen-plaintext-adjacent scenario ever let an attacker influence note plaintext in a way that could be leveraged against AES-GCM under specific misuse conditions (e.g., a nonce-reuse bug introduced in a future refactor, which cross-domain key sharing would make *more* consequential, not less), the blast radius of that mistake would extend to the token too, when it need not.
- **Why HKDF-based derivation is the correct standard tool:** HKDF (RFC 5869) is specifically designed for exactly this — expanding one high-entropy secret into multiple independent-looking subkeys via a domain-separation `info` string, with the cryptographic property that compromising one derived subkey does not help an attacker derive or predict any other subkey from the same source, as long as the underlying PRF (HMAC-SHA256, the standard HKDF construction) holds.
- **Cost of adding this:** one additional, well-understood, already-implementable primitive (HKDF is directly available via the `cryptography` package already in use — `Hkdf` class exists in `package:cryptography`, no new dependency needed). This is a small implementation cost for a real, standards-justified security improvement, not security theater — it directly limits blast radius between two data classes with materially different sensitivity and exposure profiles (Section 12 elaborates specifically on why the token's exposure profile differs from notes').

**I am not treating this as free/costless, per your Section 19 instruction — stated explicitly:** SECURITY BENEFIT: cross-domain compromise containment, standards-conformant key hygiene. UX COST: none (invisible to the user). PERFORMANCE COST: negligible (HKDF-Expand is a single HMAC operation, not a full KDF re-run — orders of magnitude cheaper than Argon2id). IMPLEMENTATION COST: small — one new function, applied at two call sites today, extensible to more without further architecture change.

## 3. Complete Key Hierarchy

| Key/Value | Derivation | Independent random or derived? | Wraps/protects | Wrapped/protected by | Stored where | Exportable |
|---|---|---|---|---|---|---|
| **Master Key (MK)** | `Random.secure()`, 256 bits | Independent random | NEK, TEK (via HKDF-Expand) | Password-KEK-wrap, Recovery-KEK-wrap, Hardware-wrap | Never stored unwrapped, anywhere | Only in wrapped form |
| **Note Encryption Key (NEK)** | `HKDF-Expand(MK, info="rocen:v2:notes", length=32)` | Derived, deterministic from MK | Note bodies (AES-256-GCM) | Nothing separately — protected transitively by whatever protects MK | Never stored — re-derived from MK every session | No — re-derived, never persisted |
| **Token Encryption Key (TEK)** | `HKDF-Expand(MK, info="rocen:v2:github_token", length=32)` | Derived, deterministic from MK | GitHub token (AES-256-GCM) | Same as NEK | Never stored | No |
| **Password-KEK** | `Argon2id(normalizedPassword, saltKEK, params)` | Derived from password | One wrap of MK | Password strength + Argon2id cost | Never stored; only `saltKEK` + wrapped-MK blob persist | No |
| **Password Verifier** | `Argon2id(normalizedPassword, saltVerifier, params)` | Derived from password, **different salt from Password-KEK** | Nothing — pure authentication oracle | N/A | `base64(saltVerifier):base64(hash)`, `rocen_settings_box` | Stored locally; never travels to GitHub |
| **Recovery-KEK** | Section 8's full construction (HKDF-based composition of normalized password + normalized mnemonic) | Derived from **both** password and mnemonic, jointly, in one operation | Second, independent wrap of MK | Both factors' combined strength | Never stored; `saltRecovery` + wrapped-MK blob persist (locally and on GitHub) | No |
| **Hardware key** | `MainActivity.kt`'s `getOrCreateHwKey(masterKeyAlias)`, StrongBox-first | Independent, hardware-generated, never leaves Keystore | Third, device-local wrap of MK | Android hardware security boundary | Wrapped-MK blob local only; raw key never leaves Keystore | No, by Keystore design |

**Explicit confirmation per your Section 2 requirement:** MK is never deterministically derived from the password under any code path in this design — every path to MK is either "generate it randomly, once" or "unwrap an existing wrapped copy." There is no function anywhere in this architecture that takes a password (alone) and produces MK.

## 4. Recovery Hierarchy — Mandatory Dual-Factor, Explicit

Per your Section 1 requirement, restated as the binding design constraint:

```
Password ────────────────► Password-KEK ────► unwraps LOCAL wrap of MK
  (alone, on a device that already has a local Password-KEK wrap)

Password + Mnemonic (BOTH, together, in one operation) ────► Recovery-KEK ────► unwraps
  the Recovery-KEK wrap of MK (on GitHub, or locally if cached)

Mnemonic ALONE ─────────────► FAILS. No code path exists that derives anything
  usable from the mnemonic without the password also being supplied in the
  same derivation call.

Password ALONE, on a NEW device with no local wrap ─────────────► FAILS. The
  only way to obtain MK on a device that has never locally cached a
  Password-KEK wrap is via the Recovery-KEK path, which mandatorily requires
  the mnemonic too.
```

**Why this is enforced structurally, not just procedurally:** Recovery-KEK's derivation function (Section 8) takes both `normalizedPassword` and `normalizedMnemonic` as **required, non-nullable parameters of the same single function call** — there is no overload, no default, no code path that calls this derivation with only one of the two present. This isn't a UI-level "ask for both fields" convention that could be bypassed by calling a lower-level function directly; the cryptographic operation itself has no mathematical meaning with only one input, since both inputs are concatenated into the same context string *before* the KDF ever runs (Section 8's exact construction).

**Existing-device password-only path, exactly as you specified is acceptable:** if a device already has a local Password-KEK-wrapped copy of MK (because it was previously unlocked/recovered there), the password alone continues to unlock MK on *that specific device* — this is not a bypass of the dual-factor requirement, because the local wrap's existence is itself evidence that dual-factor recovery (or original setup) already occurred on that device at some point. A brand-new device, or a device whose local wrap was deleted/never created, has no such shortcut.

## 5. Hardware Hierarchy

**What exactly the hardware key protects (your direct question, answered precisely):** the hardware key wraps **MK directly** — never a password verifier, never anything that could become "indirectly" usable as encryption material. This matches your preferred model exactly, and is a genuine strengthening versus my first draft's phrasing, which described the same target but didn't emphasize the distinction as sharply as you're now requiring.

**What hardware protection actually provides, classified honestly (not overclaimed):**
- **Confidentiality protection:** partial, and tier-dependent. On StrongBox-backed devices, genuine additional confidentiality — the wrapping key cannot be extracted even by a rooted/compromised OS, since it never leaves a physically separate secure element. On TEE-only devices, weaker: the key is isolated from normal app/OS code but a sufficiently privileged attacker (Attacker C, already documented) may be able to *invoke* the key even without extracting it — this is a narrower guarantee than StrongBox provides, and must not be described as equivalent.
- **Convenience:** yes, substantially — this is its primary practical purpose in this design. Without it, every unlock requires re-running Argon2id at the hardened tier (deliberately slow, by design, to resist offline attack) — hardware-wrapping lets a *known* device skip that cost for routine unlocks.
- **User-presence/authentication:** **not by default in this design as specified.** `getOrCreateHwKey` today does not request `setUserAuthenticationRequired(true)` on the generated key (confirmed absent from the reviewed `MainActivity.kt`), meaning the hardware wrap currently provides no biometric/PIN-gate binding — any code running as the app's own UID can invoke the wrap without a fresh user-presence check. **This is a real, honest limitation to state rather than let the word "hardware-backed" imply more than it delivers.** If you want genuine user-presence binding, that requires `setUserAuthenticationRequired(true)` plus a biometric prompt flow — currently absent from Rocen entirely (confirmed no `local_auth`-equivalent package), and out of scope for *this* redesign unless you want it added (flagged as a decision item, Section 20).
- **Defense in depth:** yes, this is the honest, accurate framing — an additional layer that raises the bar for a subset of attackers (non-StrongBox: raises it somewhat; StrongBox: raises it substantially) without being load-bearing for the system's core security guarantee, which rests on Password-KEK/Recovery-KEK regardless of hardware availability.

**Device lock state, biometric changes, key invalidation:** if the hardware key's generation parameters ever include `setInvalidatedByBiometricEnrollment(true)` (a decision, not currently made either way in the existing code) or the device's lock-screen credential changes in a way Android treats as key-invalidating, the wrapped-MK-via-hardware blob becomes permanently unusable — the design must treat this as an expected, non-catastrophic failure mode (Section 17): fall back to Password-KEK, and silently regenerate a *fresh* hardware wrap of the already-unwrapped MK on next successful password-based unlock, rather than treating hardware-key invalidation as data loss.

**Rooted-device limitations:** unchanged from the audit's existing, already-correct Attacker-C analysis — StrongBox meaningfully resists even root; TEE-only does not fully. This design doesn't change that ceiling; it only ensures the fallback (Password-KEK/Recovery-KEK) is never weaker than the hardware path would have been, so hardware unavailability is a UX regression, never a security regression.

## 6. Trust Boundaries — Field-by-Field, No Field Assumed Trusted by Default

Per your explicit instruction not to call a GitHub-supplied value trusted merely because Rocen wrote it:

| Field | Who controls it | Can an attacker with GitHub write access modify it? | How is authenticity verified? | Usable in AAD construction? |
|---|---|---|---|---|
| **Note ID** | Assigned locally by the device that created the note (`CaptureItem.id`, currently a timestamp-derived string) | Yes — it's a JSON field in a file the attacker can freely rewrite | **Not by anything remote.** Authenticity must come from the *decrypting device's own local record* of what note it believes it is decrypting — i.e., the app decides "I am decrypting note X" *before* fetching/reading the remote file, from its own local database, and uses *that* locally-sourced ID to build the expected AAD, never the ID read out of the fetched JSON's own fields. | **Yes, but only the locally-sourced value, never the remote-file-embedded copy of the same field even if present for human/debug readability.** |
| **Generation/revision number** | Intended to be monotonically incremented by whichever device last wrote the note | Yes, entirely — an attacker can set this to any value, including a smaller (rolled-back) one | **Not fully verifiable from GitHub content alone** — this is the crux of Section 9's rollback analysis below. The best available anchor is the *decrypting device's own last-known generation for that note*, not anything read from the current remote file. | Yes, but with the critical caveat proven in Section 9: this alone does not prevent rollback, only detects *some* rollback attempts (specifically, rollback below what the decrypting device itself already remembers). |
| **Key version** | Set by whichever device encrypted the data, reflecting which MK generation was in use | Attacker can modify it in the stored file | Not independently verifiable from the file itself; trusted only insofar as the decrypting device knows which key versions it has ever possessed a wrap for — an unrecognized key version fails closed (Section 17) rather than being trusted at face value | Yes — authenticating the *claimed* key version means a downgrade-to-old-key-version attempt is at least detectable if the app also tracks its own key-version history and rejects claims for versions it never used |
| **Crypto format version** | Set at encryption time by the app's own current code | Attacker-modifiable in the stored bytes | Verified only by "does the running app recognize and support this version" — this is inherently a property the app checks about *itself*, not something GitHub can attest to | Yes — this is exactly what Section 13 already includes, and it's a case where authenticating an attacker-modifiable field is still valuable, because the *check* (do I support this version) is evaluated locally regardless of what value is claimed |
| **Deletion state** | Whichever device most recently issued a delete | Fully attacker-controllable (a delete can be "undone" by simply re-adding the file, or a live file's deletion can be suppressed by reverting a commit) | **Not verifiable at all from repository state alone** — this is a genuine, structural gap: GitHub, as a mutable, attacker-writable store, cannot itself attest to "this really was deleted and should stay deleted." A full solution would require a separate, append-only, signed deletion log — out of scope for this pass, flagged as a real unresolved risk in Section 19. | No — deletion state is not a field to authenticate via note AAD; it's a separate, currently-unsolved integrity problem |
| **Sync state (`pendingReviewAfterSync`, etc.)** | Local, per-device bookkeeping | Not typically synced to GitHub as a security-relevant field in the reviewed code — mostly a local-only flag | N/A — not a remote trust question | No — purely local UI-state bookkeeping, never security-relevant |

**The overriding principle this table enforces, stated plainly per your Section 4 requirement:** **the canonical AAD is built from the decrypting device's own trusted local expectations (which note it's decrypting, what generation it last knew about, what format/key version its own code supports) — never from any field read out of the ciphertext's own accompanying metadata, even when that metadata happens to look correct.** The stored/transmitted AAD-shaped fields inside the envelope (Section 13) exist for **debugging/serialization convenience and human readability only** — they are explicitly *not* the trust source, and decryption never uses "read the stored AAD, then authenticate against what was just read," since that construction is circular and provides zero security (an attacker who moves an entire envelope, stored AAD included, to a different note would pass such a check trivially).


## 7. Password-KEK and Verifier — Explicit Separation, Stated Accurately

```
Password
   │
   ├────────────────────────────────► Argon2id(password, saltVerifier, params)
   │                                    = Password Verifier
   │                                    → verifyPin() comparison ONLY
   │                                    → cryptographically dead-ends here
   │
   └────────────────────────────────► Argon2id(password, saltKEK, params)
                                        = Password-KEK
                                        → AES-256-GCM-wraps MK
                                        → this is the ONLY password-derived
                                          value that ever touches MK
```

**`saltVerifier ≠ saltKEK`, always, non-negotiably** — generated independently, stored independently, no code path ever reuses one for the other's purpose.

**Accurate statement of what a stolen verifier requires, exactly as your Section 7 asks me to state precisely:** an attacker who extracts the stored verifier (`base64(saltVerifier):base64(hash)`) must run a **full offline password-guessing attack** — trying candidate passwords, deriving `Argon2id(candidate, saltVerifier, params)`, and comparing against the stolen hash — to determine the actual password. **Succeeding at this attack recovers the password itself** (which is the real prize — a person's actual password is often reused elsewhere, is itself sensitive), but **does not, by itself, hand the attacker Password-KEK**, because Password-KEK uses a *different salt*. However — and this must be stated with full honesty, not glossed over — **once an attacker has recovered the actual password via the verifier attack, they trivially compute Password-KEK themselves** (it's `Argon2id(recoveredPassword, saltKEK, params)`, and `saltKEK` is public/stored data), **if they also have `saltKEK` and the wrapped-MK blob**, which — per Section 6/Finding B in the original audit — they would, from the same local-storage extraction that yielded the verifier in the first place.

**This is the correct, accurate, non-oversold claim: the separation does not make password-cracking pointless — nothing can, since the attacker still ends up needing the real password either way. What the separation achieves is narrower and precise: it removes the ability to skip the cracking step entirely**, which is exactly what Finding 3A's original vulnerability allowed (using the stored verifier *directly* as decryption key material, with zero cracking required at all). Post-redesign, an attacker with only local storage — no cracking attempted — has cryptographically nothing usable against MK; they must successfully brute-force the actual password first, same as any properly-built password-based system, and Argon2id's cost parameters are the only thing standing between them and success, exactly as intended.

## 8. Recovery-KEK — Full, Explicit Construction

Your Section 8 correctly identifies that "just concatenate password and mnemonic" (today's `combinedSecret = '$password|${mnemonicWords.join(' ')}'`) is under-specified. Full construction:

**Normalization:**
- **Password:** Unicode NFC normalization applied before use (prevents two visually-identical passwords typed on different keyboards/input methods, which could produce different Unicode byte sequences for the same intended password, from silently failing to match). Dart's `String` comparison/hashing is code-point-based, not normalization-aware by default, so this must be an explicit step (`package:characters` or manual NFC normalization) rather than assumed.
- **Mnemonic:** lowercase, single-space-joined, in the exact word order presented — matching standard BIP-39 normalization convention (BIP-39 itself specifies NFKD normalization of the mnemonic sentence before use in its own reference `PBKDF2` construction; this design should follow that same convention for consistency with the standard, even though Rocen's checksum/wordlist logic is BIP-39-*inspired* rather than a full BIP-39 implementation per the earlier audit's finding).

**Domain/context string:** `"rocen:v2:recovery-kek"` — a fixed, versioned, application-specific string, preventing this derivation from ever colliding in purpose with any other derivation in the system even if (hypothetically) the same raw password+mnemonic pair were ever reused as input to some other function.

**Construction, precisely:**
```
recoveryInput = normalize(password) || 0x00 || normalize(mnemonic) || 0x00 || "rocen:v2:recovery-kek"
Recovery-KEK = Argon2id(recoveryInput, saltRecovery, memory, iterations, parallelism=1, hashLength=32)
```

The `0x00` separators and the trailing domain string are the specific fix for concatenation ambiguity (Section 8's own concern) — without them, `password="ab" + mnemonic="c..."` and `password="abc" + mnemonic="..."` starting the same way could theoretically produce related inputs if a weaker joining scheme were used; null-byte separation plus a fixed domain suffix removes this class of ambiguity cleanly, using only primitives already in the codebase (no new dependency).

**Salt:** `saltRecovery`, 16 bytes, `Random.secure()`, generated once at initial setup, stored as public metadata (locally and in `device_key.json`).

**KDF parameters:** same tier logic as Password-KEK (`_authParamsStandard`/`_authParamsHardened`-equivalent, chosen per Section 14's revised `_isHardened()` scope) — recorded explicitly in the wrap envelope (Section 13), not assumed from device state.

**Output length:** 32 bytes (256 bits), matching AES-256-GCM's key requirement for wrapping MK.

**Storage of public parameters:** `saltRecovery` and the KDF parameters used are stored in plaintext alongside the wrapped-MK-via-Recovery-KEK blob, both locally (if cached) and in `device_key.json` on GitHub — this is standard, expected practice (a KDF salt is public data by cryptographic convention; it is not a secret and doesn't need protecting, only the *output* of combining it with the secret input does).

**Raw mnemonic persistence:** never — matches the existing, already-correct behavior (confirmed in the original audit, Part 1 Section 3G) of generating, displaying once, and letting the `List<String>`/`String` values fall out of scope, subject to Dart's GC. This design doesn't change that property; it only changes what the mnemonic's *derived output* protects.

## 9. Password Change — Resolving the Stated Tension Explicitly

**Master Key: unchanged.** Non-negotiable per your Section 2/9 instruction, and structurally guaranteed since nothing in this flow ever regenerates MK.

**Standard flow:**
```
old password → unwrap MK via old Password-KEK (requires the OLD password)
new password → derive new Password-KEK (fresh saltKEK)
             → wrap the SAME MK bytes under the new Password-KEK
             → commit locally
new password → derive new Password Verifier (fresh saltVerifier)
             → replace stored verifier
```

**No note re-encryption** — confirmed, since NEK (and therefore every note's ciphertext) never depends on Password-KEK at all; only the *wrapper* around MK changes, and MK itself, NEK, and every note's ciphertext are all completely unaffected.

**The Recovery-KEK problem, addressed honestly per your explicit instruction not to assume the mnemonic is available:**

Recovery-KEK's derivation requires **both** the new password and the mnemonic, computed together. At the moment of a password change, the app has the new password (the user just typed it) but **does not have the mnemonic in memory** (per Section 8, it's never persisted — it only ever exists transiently, during the one moment it was originally generated-and-displayed, or during an explicit recovery operation).

**Three honestly-evaluated approaches, per your instruction to evaluate rather than assume:**

**(a) Require mnemonic re-entry during every password change, immediately re-wrapping Recovery-KEK with the new password.** SECURITY BENEFIT: the Recovery-KEK wrap is always current — a lost/leaked *old* password combined with the (unchanged) mnemonic can never unwrap MK after a password change, since the Recovery-KEK wrap now requires the *new* password too. UX COST: real and immediate — every password change now requires the user to locate and re-type their 12-word phrase, a meaningfully heavier flow than today's password-change UX. PERFORMANCE COST: negligible (one more Argon2id run). IMPLEMENTATION COST: moderate — the password-change UI needs a mnemonic-entry step added, reusing the existing `_promptMnemonicRecovery` dialog infrastructure already built and tested this session.

**(b) Leave the Recovery-KEK wrap keyed to the *old* password, unchanged, until the user separately, explicitly chooses to "update my recovery protection."** SECURITY BENEFIT: none — this is strictly worse than (a). UX COST: lower immediately, but creates a **standing, silent security liability**: an attacker who obtains the *old* (changed-away-from) password, combined with the mnemonic (which hasn't changed and was never invalidated), retains a live path to MK indefinitely, even though the user believes they "changed their password" specifically to invalidate old-password-based access. This directly contradicts the entire purpose of a password change. **I reject this option outright** — it is exactly the kind of "convenience over correctness" choice your instructions explicitly forbid me from silently choosing, and I want to be unambiguous that this is not a viable option under your stated priorities, not merely a less-preferred one.

**(c) Defer the Recovery-KEK re-wrap, but track it as a mandatory-pending operation (reusing this session's already-built `PendingReason`/`deviceKeyNotReady` mechanism) that blocks further password changes until resolved, exactly as today's actual deviceKeyNotReady flow already does for a conceptually similar gap.** SECURITY BENEFIT: nearly as strong as (a) — the window during which the old password could still combine with the mnemonic is bounded to "until the user next completes the pending mnemonic step," not indefinite, and the app actively surfaces this as unfinished/blocking rather than silently leaving it stale. UX COST: lower than (a) for the common case (user isn't forced to have the mnemonic *at that exact moment*) but not zero — they're still blocked from a *further* password change until they do provide it, and the system should also proactively warn "your recovery protection is not yet updated" rather than wait for a user-initiated re-attempt. IMPLEMENTATION COST: lowest of the three, since it reuses existing, already-tested infrastructure from this session almost unchanged.

**Decision, given your stated priority to maximize real security over convenience — I am choosing (a), not (c), and explaining why the "reuse existing infrastructure" appeal of (c) does not override the security difference:** (c) leaves a real, non-zero window — however bounded — where the old password remains a valid recovery factor after the user explicitly acted to invalidate it. Your instructions state plainly: *"If either the password OR mnemonic is lost, the recovery path must fail"* and *"Do not weaken this requirement for UX."* (c)'s pending-window is a genuine, if temporary, weakening of exactly that guarantee — the old password isn't yet fully retired as a recovery factor the instant the user believes they've changed it. **(a) is the design that actually delivers what Section 1 demands at every moment, not just eventually.** This is stated as the recommended default; it remains listed in Section 20 as a decision requiring your explicit sign-off, precisely because it's the one place in this document where I'm recommending the UX-heavier path specifically because your instructions told me to prefer it when security and convenience conflict.

**Interruption safety:** local Password-KEK re-wrap and verifier update commit first (as in my first draft); the Recovery-KEK re-wrap (now happening in the *same* user-facing operation under option (a), not deferred) either completes as part of the same atomic local transaction or the whole password-change operation is treated as not-yet-complete and re-promptable — never partially applied in a way that leaves the verifier updated but Recovery-KEK stale.

## 10. GitHub Token — Domain-Separated, Per Section 3's Conclusion

**Decision: Token Encryption Key (TEK), not raw MK.** Per Section 2/3's HKDF conclusion, applied concretely here: `TEK = HKDF-Expand(MK, info="rocen:v2:github_token", 32)`. The token is encrypted with TEK, AAD-bound to a fixed context string `"rocen:v2:github_token:${deviceId}"` (device-bound, since each device stores its own token-adjacent credentials independently — there's no cross-device "generation" concept for the token the way there is for notes, since the token itself isn't collaboratively edited).

**Why the token's exposure profile genuinely differs from notes', justifying separate treatment (not just theoretical hygiene):** the GitHub token's ciphertext is **never** synced to or stored on GitHub itself (confirmed, original audit) — its only storage location is the local `rocen_settings_box`. Its confidentiality requirement is therefore purely a **local-extraction** concern (Attacker B), whereas notes' ciphertext is also exposed to **GitHub-repository-access-only** attackers (Attacker D) who never touch local storage at all. Using the same key for both means an Attacker-D-only scenario (repo access, no local device access) — which today reveals only note ciphertext, appropriately — could, under key reuse, theoretically have its risk profile entangled with the token's if any future cross-context leak ever occurred. Domain separation keeps these two genuinely distinct threat exposures architecturally distinct too.

## 11. Note Encryption — Authenticated Context, and the Title Question Re-Evaluated

**Authenticated context (canonical AAD), reconstructed from trusted local state only, never from the envelope's own stored fields:**

```
AAD = "rocen:v2:note" || 0x00 || noteId || 0x00 || recordType || 0x00 || 
      utf8(expectedGeneration) || 0x00 || utf8(keyVersion) || 0x00 || 
      utf8(formatVersion)
```

Where `noteId`, `recordType` ("note" vs "encrypted_note" — evaluated below), `expectedGeneration`, `keyVersion`, and `formatVersion` are **all sourced from the decrypting device's own local database record for that note**, per Section 6's trust-boundary table — never from the fetched ciphertext blob's own metadata fields, even when present for debugging.

**Should record type be authenticated?** Yes — binding `recordType` into the AAD prevents an attacker from taking an `encrypted_note`'s ciphertext and metadata and relabeling it as if it were a different record type the app might process differently, even though this is a narrower, more speculative attack surface than note-ID substitution; the cost of including it is one more field concatenated into an already-necessary construction, essentially free.

**Title: re-evaluated under the maximum-security instruction, not performance convenience.** My first draft recommended "visible but authenticated" primarily reasoning from UI list-rendering cost. Under this stricter review, I need to directly answer your question: **does a plaintext title leak unacceptable sensitive metadata?**

Evaluated honestly: **yes, it can, and the product's own stated threat model (a user explicitly choosing to "lock" a note) is direct evidence that the user considers *something* about that note sensitive enough to protect — a title like "Divorce lawyer consultation notes" or "Account recovery codes for X" leaks the *category and specificity of the sensitive content* even with the body fully encrypted, to anyone with local storage access or GitHub repo access (both are firmly in-scope attackers per the existing threat model, Attacker B and Attacker D).** Given your instruction to prefer the stronger design and accept implementation cost, I am **revising my recommendation from the first draft: titles for `encrypted_note` records should be encrypted, not merely authenticated-visible.**

**Trade-off, stated per Section 19's format:** SECURITY BENEFIT: closes a real, demonstrated metadata-leak vector consistent with the product's own stated intent for the "lock this note" feature. UX COST: real — list rendering for locked notes can no longer show a human-readable title without decrypting first; the practical mitigation is to show a placeholder (e.g., "LOCKED NOTE" or a generic icon) for locked-note tiles in the list view, only revealing the real title once the user actually opens/unlocks that specific note — this is a legitimate, common pattern (many password managers and encrypted-note apps do exactly this) and is not a "fundamentally unusable" cost, so per your Section 19 instruction ("choose the stronger security design unless it makes the product fundamentally unusable"), it does not meet the bar for reverting to the weaker option. PERFORMANCE COST: negligible — title strings are short; encrypting them costs microseconds, and the list view no longer needs to decrypt titles individually since it's showing a placeholder instead, which is actually *cheaper* than my first draft's "authenticate on every list render" approach in practice. IMPLEMENTATION COST: encrypt title alongside body (either as a second field in the same envelope or concatenated with body before encryption, separated by a length-prefix so both can still be retrieved independently after one decrypt) — small-to-moderate, mostly UI work to build the placeholder-tile pattern.

**This directly reverses my first design's recommendation, and I'm stating that reversal explicitly rather than quietly changing my answer** — the first draft optimized for list-rendering convenience; this draft, per your explicit override, optimizes for not leaking sensitive title content, and accepts the resulting UX cost as justified.

## 12. Anti-Replay / Rollback — The Section You Specifically Asked Me Not to Wave Away

**Your exact scenario, worked through precisely, not glossed over:**

> Current note: generation 10. Attacker restores generation 7's ciphertext and matching AAD for generation 7.

**Why this authenticates successfully if the app trusts the remote generation:** if the decrypting device's AAD-construction logic reads "what generation should I expect" from **anything present in the fetched remote data** (e.g., "the file I just downloaded says generation 7, so I'll authenticate against generation 7"), then the attacker's restored generation-7 envelope is **internally self-consistent** — its ciphertext, its embedded generation claim, and the AAD constructed from that claim all match perfectly, because the attacker didn't need to forge anything cryptographic at all; they only needed to restore a **previously-legitimately-produced, fully-valid** older envelope wholesale. AES-GCM's authentication tag proves "this ciphertext+AAD pair was produced by someone holding NEK," which the generation-7 envelope genuinely was, by the legitimate device, at generation-7 time. The tag says nothing about *when* that pairing was produced relative to anything else. **This is precisely why generation-in-AAD, by itself, does not solve rollback — it only proves internal consistency of a record, never its recency relative to other records.**

**The five concepts you asked me to separate, done explicitly:**

1. **Cryptographic authenticity** — "was this ciphertext+AAD pair produced by someone holding the correct key, unmodified since." **Solved** by AES-GCM's tag, robustly, regardless of rollback concerns.
2. **Record identity binding** — "does this ciphertext actually belong to the note I think I'm decrypting." **Solved** by binding `noteId` into AAD, sourced from local trusted state (Section 6), which is exactly why a ciphertext moved from Note A to Note B fails: the decrypting device, believing it is decrypting Note B, constructs AAD containing Note B's ID; the moved ciphertext's tag was computed over AAD containing Note A's ID; these don't match; GCM's tag verification fails; decryption is rejected. **This part is fully and correctly solved by AAD, exactly as Section 4 requires — demonstrated concretely, not asserted.**
3. **Freshness** — "is this the most recent version." **Not solved by AAD alone**, per the worked scenario above — this requires an independently-trustworthy source of "what is the true latest generation," which is exactly the crux of the problem.
4. **Synchronization integrity** — "did all devices converge on a consistent view of the note's history." Partially addressed by the existing `password_state_manager.dart`-style fast-forward/generation-comparison mechanism *for password-state coordination specifically*, but that mechanism, as it exists today, coordinates *password* generations, not *per-note* generations — extending an equivalent mechanism to *every individual note* is a materially larger scope than this redesign's password/master-key focus, and is flagged honestly below as only partially addressed.
5. **Rollback prevention** — the actual goal, and where I must be direct with you per your explicit instruction: **given the stated threat model (GitHub is an external, mutable store; an attacker with write access to the repository is explicitly in-scope per the original audit's Attacker D), perfect rollback prevention is not achievable using only client-side cryptography against a mutable remote store you don't independently attest to.** This is not a Rocen implementation gap — it is a structural property of "the source of truth for 'what's current' is the same mutable store the attacker can write to." Any purely-local check ("does this match what I last saw") only protects the *specific device* that already saw the later generation; it does nothing for a device that's seeing this note for the first time, or a device that was offline during the legitimate generation-10 write and has no prior memory to compare against.

**The strongest practical defense achievable within this constraint, stated honestly as "detection for previously-seen state," not "prevention":**

- Each device maintains a **local, tamper-evident record** of the highest generation number it has ever legitimately seen for each note (a simple local Hive-stored `lastKnownGeneration` map, keyed by `noteId`).
- On every fetch, **if the remote generation is lower than the device's own locally-remembered highest generation for that note, treat this as a detected rollback attempt** — refuse to decrypt/accept it automatically, and surface a distinct, explicit "POTENTIAL ROLLBACK DETECTED" state to the user rather than silently accepting the older content or silently discarding it. This is real, valuable protection **for any device that has previously synced that note at its true latest generation** — which, in practice, covers the common case (a user's own primary device would almost always have seen the legitimate generation-10 write before an attacker could restore generation-7).
- **The genuinely unresolved gap, stated without hedging:** a device that has *never* seen this note before (a brand-new device, or a device restoring from scratch) has no local baseline to compare against, and **cannot distinguish a legitimately-old note that was simply never updated from a maliciously-rolled-back one**, using cryptography alone. This is the honest limit of what's achievable without either (a) a separate, append-only, cryptographically-signed audit log that isn't itself stored in the same mutable repository (a meaningfully larger architectural addition, likely requiring a separate trusted service or a Git-native mechanism like signed commits with a verified, pinned list of authorized signing keys per device — real, standards-based, but substantial new scope), or (b) accepting that first-sync trust-on-first-use is the practical ceiling for a design of this size.

**I am not claiming this is solved. Per your explicit instruction, I am stating plainly: full rollback prevention for a first-time-syncing device is not achievable within this design's scope, and the mitigation above (local highest-generation tracking) is a genuinely strong, real, standards-consistent detection mechanism for the *already-seen* case, while leaving the *first-sync* case as an acknowledged, unresolved risk** — carried forward explicitly into Section 19.

## 13. Self-Describing Envelope v2 — Field-by-Field Justification

| Field | Secret? | Authenticated? | Trusted (at decrypt time)? | Modifiable without detection? | Why it exists |
|---|---|---|---|---|---|
| `formatVersion` | No | No (read before AAD reconstruction is even attempted — see below) | Only insofar as "the running app either supports this exact value or refuses" | Yes, but modification only ever leads to a refusal, never misinterpretation | Lets the app immediately reject anything it doesn't understand, before attempting any cryptographic operation |
| `keyVersion` | No | Yes (part of canonical AAD, sourced from local expectation, not this field) | Only if it matches what the decrypting device's own local record expects for this key generation | Yes, but modification causes AAD mismatch → tag failure | Supports future MK rotation (Section 16) without redesign |
| `algorithmId` | No | No | Trusted only as "which algorithm to attempt" — if it doesn't match what the app implements, refuse | Yes, modification just causes a refusal | Self-description; avoids hardcoding one algorithm forever |
| `recordType` | No | Yes (in AAD, from local record) | Sourced locally, not from this field, at decrypt time | Yes, mismatch → tag failure | See Section 11 |
| `nonce` | No (nonces are never secret) | Implicitly authenticated as part of AES-GCM's construction (any nonce tampering changes the effective decryption and fails the tag) | Yes — this one genuinely must be trusted as-transmitted, since it's mathematically required for decryption to even be attempted | Modifying it causes decryption failure (not a security hole — GCM is designed so nonce integrity matters for correctness, and tampering here simply breaks decryption, it doesn't enable a bypass) | Required by AES-GCM's construction; must be unique per key, never reused |
| **`salt` (wrap envelopes only)** | No | No | Trusted as public KDF input | Modifying it changes the derived KEK, causing a benign decryption failure (not a security bypass) | Required to re-derive Password-KEK/Recovery-KEK |
| **`kdfMemory`/`kdfIterations` (wrap envelopes only)** | No | No | Trusted as "which cost parameters to use for this specific wrap" — bounded-checked against a sane maximum before use (Section 17) | Modifying to an absurd value is caught by the bounds check; modifying to a *smaller*, weaker value than originally used would make the KDF cheaper, but since Password-KEK/Recovery-KEK must still exactly match what was used to originally wrap MK, a mismatched value simply fails to unwrap correctly (wrong derived key), it does not create a "weaker but successful" unwrap path | Enables cross-device KDF-tier independence (Section 15) — this exact field's absence is what caused the original audit's Finding 3C |
| **Ciphertext** | Yes (this is the actual secret payload) | Authenticated as a unit with AAD via GCM's tag | N/A — this is the thing being protected, not a trust input | No, without detection — any modification fails the tag | The actual protected data |
| **Authentication tag** | No (tags aren't secret, they're a MAC) | This IS the authentication mechanism | Trusted only as "the value to check against," never bypassed | Modifying it directly causes verification failure by definition | Core AES-GCM output |
| **Canonical AAD** | **Not stored in the envelope at all, per Section 4/6 — reconstructed fresh from local trusted state at decrypt time** | This is the thing ciphertext is authenticated against | Fully trusted, because it's built locally, not read from anything attacker-reachable | N/A — it's never transmitted or stored as a field to modify | This is the entire fix for Section 4's critical correction |
| *(Debug-only, non-security field)* Human-readable copy of noteId/generation for troubleshooting | No | No — explicitly and deliberately NOT authenticated, NOT trusted, exists purely so a developer inspecting a raw envelope dump can see what it *claims* to be, with a clear comment stating it must never be used for any decision | N/A | Freely, by design — this is why it must never be confused with the real, locally-reconstructed AAD | Debugging convenience only, per your Section 4 allowance ("may contain AAD-related metadata for serialization/debugging") |

**Fields deliberately excluded, per your instruction not to add fields "just because they look useful":** I considered and rejected including a stored "signature of AAD" field, a stored "expected next generation hint," and a stored "device that created this" field inside the envelope itself — all three would either duplicate what local trusted state already provides better (the first two) or introduce exactly the "trust remote-stored metadata" anti-pattern Section 4/6 forbid (the third, since "which device created this" read from the file itself is just as attacker-forgeable as everything else in Section 6's table).

## 14. `_isHardened()` Strategy — Final, Precise Scope

Direct answers:

**Should it interpret existing note ciphertext?** **No, never, under any circumstance in this design** — note/token decryption uses NEK/TEK derived from MK, with zero KDF step at decrypt time at all. `_isHardened()` is structurally unreachable from that code path entirely (not merely "shouldn't be consulted" — there is no parameter, no branch, nothing in the note-decrypt function signature that could even accept a KDF-tier input).

**Should it only determine parameters for new wrapping operations?** **Yes, precisely this, and only this** — it influences what parameters are chosen when a device is *creating a new* Password-KEK wrap or Recovery-KEK wrap (at setup, password change, or first-time device enrollment). It never influences reading back an *existing* wrap, since existing wraps carry their own recorded parameters (Section 13's `kdfMemory`/`kdfIterations` fields) that decryption reads directly, never re-deriving from current device state.

**When can its fail-closed behavior safely change from `false` to `true`?** **Only after the v2 wrap-envelope format (with embedded KDF parameters) is fully in place and is the only format wrap operations produce.** Before that point (i.e., under today's still-deployed v1-equivalent behavior, where `_isHardened()`'s output directly gates note/token encryption with no format-recorded fallback), flipping this to fail-closed-true carries the exact cross-operation-mismatch risk we correctly deferred last session. **Once this redesign ships, that coupling is severed entirely** — `_isHardened()`'s only remaining consumer is "choose parameters for a brand-new wrap," and a transient failure there, defaulting to `true` (hardened), produces at worst a slightly-slower-than-necessary new wrap, never a mismatch with anything previously encrypted, because nothing previously encrypted depends on `_isHardened()`'s *current* answer anymore. **This confirms and sharpens my first draft's conclusion: the fix to `_isHardened()` ships bundled with this redesign, not before it, and becomes unconditionally safe once the redesign lands** — no remaining caveat.

## 15. Multi-Device Model

Unchanged in substance from my first draft's Section 8, strengthened by this pass's domain-separation and AAD corrections. Explicit confirmation against your specific concern: **MK is generated exactly once, at first setup, on the first device — every subsequent device obtains the identical MK bytes via the Recovery-KEK unwrap path (Section 4), never generates its own.** There is no code path in this design where a second device calls the MK-generation function — that function should be gated to only ever run when *no* wrapped-MK-of-any-kind exists anywhere reachable (local or, after checking, remote), preventing an accidental "Device B thinks it's first-time setup and generates a second, different MK" scenario, which would silently fork the user's data into two incompatible encryption domains. This gating check is itself a required, explicit implementation safeguard, not an incidental detail — flagged in Section 20 as needing careful implementation attention, not just design mention.

**Device-specific, confirmed:** Password-KEK parameters (via that device's own `_isHardened()` reading), hardware wrap (device-local Keystore entry, never shared), local `lastKnownGeneration` cache (Section 9's rollback-detection state — genuinely device-specific by necessity, since it represents "what has *this device* observed").

**Shared, confirmed:** MK (identical bytes everywhere), NEK/TEK (deterministically re-derivable from MK on any device, so trivially identical without needing to be separately synced), note ciphertext, the crypto format version understanding, Recovery-KEK's construction (same algorithm everywhere, though each device re-derives it fresh from the same password+mnemonic rather than sharing a derived value).

## 16. Future Key Rotation — Capability, Not Implementation

Per your instruction, not building rotation now, but confirming the architecture doesn't block it later:

`keyVersion` (Section 13) is the load-bearing field for this. A future MK rotation would: generate MK-v2 (new random key), re-derive NEK-v2/TEK-v2 from it, and — critically, because NEK/TEK are HKDF-derived per-domain rather than being MK itself — **re-encrypting existing data under MK-v2 is the only way old ciphertext becomes MK-v2-compatible; there is no shortcut.** This is an honest, necessary cost of rotation in general (true of essentially any master-key rotation scheme, not a weakness specific to this design) — the architecture's job is only to make this *possible* atomically (decrypt-under-v1, re-encrypt-under-v2, update `keyVersion`, confirm success before ever discarding the v1-wrapped copies) rather than requiring a structural redesign to add the concept later. Confirmed: nothing in this design prevents that future work; `keyVersion`'s presence from day one is exactly what avoids a second breaking envelope-format change purely to add rotation support later.

## 17. Failure Behavior — Full Table, Including Every Combination You Specified

| Failure | Behavior |
|---|---|
| Wrong password (existing-device path) | Password-KEK unwrap of local MK-wrap fails tag check → `WrongPasswordFailure`. No partial MK ever produced. |
| Wrong mnemonic (recovery path, correct password) | Recovery-KEK derivation succeeds mechanically (it's just a KDF, it always "succeeds" at producing *some* output), but the resulting Recovery-KEK fails to correctly unwrap the Recovery-KEK-wrapped MK (tag check fails, since the derived key is wrong) → `RecoveryFailure`. |
| Wrong password + correct mnemonic | Same outcome as above — Recovery-KEK's derivation takes both jointly; a wrong password produces a wrong Recovery-KEK regardless of the mnemonic being correct → `RecoveryFailure`. This is the direct proof that mnemonic-alone provides nothing: even with the *entire* correct mnemonic, a wrong password still fails, because both feed the same single derivation. |
| Correct password + wrong mnemonic | Symmetric to the above → `RecoveryFailure`. Directly proves password-alone (in the recovery/new-device context) provides nothing either. |
| Both wrong | `RecoveryFailure`, same mechanism. |
| Corrupted wrapped MK (any of the three wrap types) | Tag check fails on the wrap envelope → `CorruptedWrapperFailure`, distinct from `WrongPasswordFailure`/`RecoveryFailure` so the UI can differentiate "this looks broken" from "check your credentials." |
| Modified ciphertext (note/token) | Tag check fails → `CorruptedDataFailure`. Original local copy never altered. |
| Modified AAD | Not directly possible to "modify," since AAD is never stored/transmitted (Section 6/13) — but a decrypting device with an *incorrect local expectation* (e.g., stale `expectedGeneration`) will construct the wrong AAD itself and fail its own decrypt → surfaced as `StaleLocalStateFailure`, prompting a re-sync of local metadata before retry, distinct from an actual tamper detection. |
| Moved ciphertext (Note A's blob presented as Note B) | Demonstrated in Section 12 — decrypting device constructs AAD for Note B (its own trusted `noteId`), the moved ciphertext's tag was computed over Note A's AAD, mismatch, tag verification fails → `TamperDetectedFailure`. |
| Invalid generation (e.g., negative, absurdly large) | Rejected by a sanity bound before use in AAD construction at all → `MalformedRecordFailure`. |
| Stale generation (lower than local `lastKnownGeneration`) | Per Section 12's mitigation → `PossibleRollbackDetectedFailure`, distinct category, surfaced to the user explicitly rather than silently accepted or silently discarded. |
| Rollback attempt (first-sync case, no local baseline) | Per Section 12's honest limitation — **cannot be detected**; decrypts successfully as if legitimate, because it genuinely is a validly-produced-at-some-point record and the device has no prior state to compare against. This is documented as an accepted, unresolved risk, not silently glossed over. |
| Unsupported format version | `UnsupportedEnvelopeVersionException`, checked before any cryptographic operation is attempted at all. |
| Malformed KDF parameters (wrap envelopes) | Bounds-checked against a hardcoded sane maximum (matching or exceeding `_authParamsHardened`'s values) before use; out-of-bounds → `MalformedRecordFailure`, refuses to even attempt the (potentially OOM-inducing) derivation. |
| Keystore failure | Fall back to Password-KEK/Recovery-KEK path, exactly as `hardwareWrap`/`hardwareUnwrap` already correctly do today — never silently stores MK unwrapped as a "workaround." |
| StrongBox unavailable | Fall back to TEE-only hardware wrap, exactly as `getOrCreateHwKey` already does — unchanged, already correct. |
| Recovery failure (general) | Covered above by the four password/mnemonic combination rows. |
| GitHub repository tampering | Detected per-field per Section 6's trust-boundary analysis — cryptographic fields (ciphertext, tags) fail closed via GCM; non-cryptographically-verifiable fields (deletion state, first-sync generation) are the documented, honest residual risk from Section 12/19. |
| Incomplete sync | Never blocks local MK availability (MK, once unwrapped this session, doesn't depend on sync completion) — only affects freshness of *other* devices' view of specific notes, an availability/staleness concern, not a decryption-failure risk. |
| Interrupted password change | Per Section 9's now-mandatory-mnemonic-reentry flow: if interrupted before the new Password-KEK wrap, new verifier, AND new Recovery-KEK wrap all commit as one atomic local unit, the *entire* password-change operation is treated as not-yet-applied, and the *old* password/mnemonic pairing remains the valid recovery state until a complete, successful re-attempt — never a partial state where some factors are updated and others aren't. |

**Global principle, restated for this final pass:** every failure category produces a **distinct, named exception type** — no ambiguous shared string anywhere in this design, and no failure path that could be mistaken for, or silently treated as, success.

## 18. Security Tests

Organized under your exact category headers:

**Key isolation**
1. Extracted Password Verifier, fed directly into the note-decrypt path → fails (structurally impossible, since note-decrypt only accepts NEK, never a verifier-shaped input).
2. Password Verifier's derived output, fed into the Password-KEK-wrap-unwrap function → fails (different salt, produces an unrelated value that doesn't match the stored wrap's expected key).
3. NEK, used to attempt decrypting a token-encrypted blob → fails (TEK ≠ NEK, HKDF domain separation confirmed via distinct `info` strings producing cryptographically distinct outputs — testable directly by deriving both from the same test-fixture MK and asserting inequality).
4. Confirm HKDF domain separation generally: derive two subkeys from the same MK with different `info` strings, assert they differ; derive twice with the *same* `info` string, assert they're identical (determinism check).

**Password**
5. Correct password unwraps MK — assert recovered MK matches the original test fixture.
6. Wrong password fails — assert `WrongPasswordFailure`, no MK-shaped output.
7. Changing password preserves MK — encrypt a note, change password, decrypt same note with new password, assert success.
8. Changing password does not re-encrypt note ciphertext — assert byte-identical ciphertext before/after (instrumented to fail the test if any note-encryption function is called during password change).

**Recovery — full four-combination matrix**
9. Correct password + correct mnemonic → recovers MK, matches fixture.
10. Wrong password + correct mnemonic → `RecoveryFailure`.
11. Correct password + wrong mnemonic → `RecoveryFailure`.
12. Both wrong → `RecoveryFailure`.
13. Mnemonic alone (function called with only mnemonic, password parameter empty/null where the type system allows testing this edge) → fails, or ideally, is a compile-time impossibility if the function signature makes both parameters non-nullable and required — test should assert this is *not callable* with only one argument, if the language allows expressing that as a test at all, or assert failure if a sentinel "empty password" is passed.
14. Password alone for the recovery/new-device path → fails, since Recovery-KEK requires both by construction.

**AAD / identity binding**
15. Changing note ID (decrypting device believes it's Note B, ciphertext was produced under Note A's AAD) → tag failure.
16. Moving ciphertext to another note → tag failure (this is test 15 restated as your explicit worked scenario — both should exist, testing the same mechanism from slightly different angles).
17. Changing record type → tag failure.
18. Changing key version (where the decrypting device's local expectation differs from what a given wrap was actually made under) → tag failure.
19. Changing generation → tag failure when the local expected generation doesn't match what the ciphertext was actually produced under.

**Replay**
20. Old valid ciphertext (generation 7) cannot silently replace newer trusted generation (10) **on a device that has previously observed generation 10** — assert `PossibleRollbackDetectedFailure`.
21. Explicitly test and document the **known limitation**: a fresh device with no `lastKnownGeneration` baseline, presented with generation-7 content that was never followed by an observed generation-10 on *that device*, decrypts successfully — this test exists to **document the accepted risk**, not to assert desired behavior, and should be clearly commented as such so a future engineer doesn't mistake it for an oversight.

**KDF independence**
22. Standard-tier device decrypts hardened-tier-encrypted note → success (trivial once NEK has no KDF step; this test mostly exists to prove the *absence* of any lingering KDF dependency in the note-decrypt path).
23. Hardened-tier device decrypts standard-tier-encrypted note → success, same reasoning.
24. Changing current device's `_isHardened()` value between two decrypt attempts of the *same already-encrypted* note → no change in outcome (proves the coupling is fully severed).

**Migration/versioning**
25. v2 encrypt/decrypt round trip, full envelope, all fields populated correctly.
26. Unsupported `formatVersion` → `UnsupportedEnvelopeVersionException`, no attempted interpretation.
27. Malformed envelope (each field independently corrupted, one at a time) → fails safely per Section 17's table, never a crash, never a plausible-wrong-plaintext.

**Hardware**
28. StrongBox path available → hardware wrap succeeds, MK recoverable via it.
29. TEE-only path (StrongBox unavailable, simulated via forcing `StrongBoxUnavailableException`) → falls back correctly, MK still recoverable via TEE wrap.
30. Hardware entirely unavailable (both throw) → falls back to Password-KEK/Recovery-KEK, MK still recoverable, **and explicitly assert MK is never written to any storage location in unwrapped form during this fallback** (the specific test your Section 18 calls for: "fallback never stores Master Key plaintext").
31. Hardware key invalidation (simulated biometric-enrollment-change scenario) → wrapped-via-hardware blob correctly detected as unusable, app falls back to Password-KEK without treating this as data loss, and correctly regenerates a fresh hardware wrap on next successful unlock.

## 19. Security vs. Convenience — Every Major Choice, Stated Per Your Required Format

| Decision | Security benefit | UX cost | Performance cost | Implementation cost | Chosen? |
|---|---|---|---|---|---|
| Domain-separated NEK/TEK via HKDF vs. direct MK reuse | Blast-radius containment between genuinely different exposure profiles (Section 12's justification) | None (invisible) | Negligible (one HMAC op) | Small | **Yes** |
| Mandatory mnemonic re-entry on every password change vs. deferred/pending Recovery-KEK update | Closes the old-password-still-works-via-recovery window entirely, immediately, matching Section 1's literal requirement | Real — heavier password-change flow | Negligible | Moderate (reuses existing dialog infra) | **Yes** |
| Encrypted titles vs. authenticated-but-visible titles | Closes a real, product-consistent metadata leak for locked notes | Real — list view needs a placeholder-tile pattern for locked notes | Negligible, arguably better (no per-render title decrypt needed with the placeholder approach) | Small-to-moderate (title encryption + UI placeholder work) | **Yes** |
| Local highest-generation tracking for rollback detection vs. no rollback mitigation at all | Real, meaningful protection for the common "device has seen the real latest state before" case | None user-facing until an actual rollback is detected, at which point a clear warning is shown (appropriate cost for a genuine security event) | Trivial (one small local map) | Small | **Yes** |
| Hardware wrap without `setUserAuthenticationRequired` vs. adding biometric-gated hardware keys | The added option would provide genuine user-presence assurance beyond what exists today | Would require a biometric prompt flow, currently entirely absent from the app | N/A | Larger (new package, new UI flow) | **Not included in this pass — flagged as a separate, optional future enhancement in Section 20, since it's genuinely new scope beyond "fix the master-key architecture," not a deferral for convenience** |
| Full signed-audit-log anti-rollback (closing the first-sync gap) vs. accepting the documented residual risk | Would close Section 12's one remaining honest gap | Significant new complexity, likely a new trusted-signing infrastructure | Meaningful | Large — a genuinely separate architectural project | **Not included — explicitly documented as an unresolved risk (Section 20) rather than silently accepted as "good enough" without your sign-off** |

## Remaining Unresolved Risks

1. **First-sync rollback detection gap (Section 12)** — cannot be closed within this design's scope; requires either a signed append-only log or accepting trust-on-first-use as the practical ceiling.
2. **Deletion-state integrity (Section 6)** — GitHub cannot attest that a deletion "should stay deleted"; a determined attacker with write access can resurrect deleted content. Not addressed by this redesign at all; flagged as a separate, currently-unsolved problem.
3. **Hardware wrap lacks user-presence binding** — provides convenience and (tier-dependent) confidentiality, but not authentication-at-time-of-use, unless biometric-gating is separately added.
4. **TEE-only devices (no StrongBox) remain vulnerable to a sufficiently privileged Attacker C** invoking the hardware-wrapped key without full extraction — an inherent platform limitation this redesign doesn't change, consistent with the original audit's already-honest framing.
5. **Password/mnemonic normalization edge cases** (Section 8) — NFC/NFKD normalization closes the common cross-keyboard/cross-locale mismatch case, but exhaustive Unicode edge-case testing (e.g., unusual combining characters, right-to-left text in a password) is not something this design pass can fully guarantee without dedicated test fixtures covering those specific cases.

## Decisions Requiring Your Approval

1. **Mandatory mnemonic re-entry on every password change (Section 9)** — I've recommended this as the only option consistent with Section 1's literal requirement, but it is a real, ongoing UX cost you should explicitly sign off on, not just accept by default.
2. **Encrypting titles for locked notes, with a placeholder-tile list-view pattern (Section 11)** — reverses my first draft's recommendation; confirm this UX pattern (generic placeholder until unlocked) is acceptable versus any alternative you might prefer.
3. **Whether to pursue biometric/user-presence-gated hardware keys** as a follow-on enhancement (Section 19) — explicitly out of this pass's scope; confirm whether it should be scheduled separately or considered unnecessary for now.
4. **Whether to pursue a signed-audit-log solution to the first-sync rollback gap**, given it's a substantial separate project — confirm whether this residual risk is acceptable to carry, or whether it should be scoped as a follow-on piece of work.
5. **Exact placeholder UX/copy for locked-note list tiles** and for the newly-distinct failure states (`PossibleRollbackDetectedFailure`, `StaleLocalStateFailure`, etc.) — these are product/wording decisions, not purely architectural ones.
6. **The MK-generation gating safeguard (Section 15)** — confirming explicitly that a second device must never independently generate a new MK, only ever recover the existing one — this needs to be a hard, tested invariant, and I want your explicit acknowledgment that this is understood as critical before implementation begins, since a bug here would silently fork user data in a way that's very difficult to detect after the fact.

No code has been modified. Awaiting your review and approval before any implementation begins.

# PROMPT

## Architectural Specification #4 (Final Refinement): Resolved Cryptographic Directives

> **Mandatory Directive:** Do NOT implement anything yet. Do NOT modify code or create commits. After this final architectural review, STOP and wait for explicit approval.

## 1. Hardware User Authentication

Re-evaluate the decision to omit `setUserAuthenticationRequired(true)` / equivalent user-presence protection from the core hardware key path. Determine whether the hardware-wrapped Master Key (MK) path must require device/user authentication before the Keystore/StrongBox key can unwrap the MK.

### Architectural Options Comparison

| Dimension | Option A: Hardware Key WITHOUT User Authentication | Option B: Hardware Key WITH User Authentication |
| --- | --- | --- |
| **Attacker Protection** | Protects key material against physical flash dumps and off-device extraction. Vulnerable to local malware/unlocked physical access. | Protects key material against flash dumps, local malware execution, and unauthorized physical device access (requires biometric/PIN). |
| **UX Cost** | Zero friction after initial setup; background unwrapping. | Requires explicit biometric scan or device PIN entry whenever the MK is unwrapped. |
| **Device Compatibility** | Universally supported across Android TEE / StrongBox hardware modules. | Requires device lock screen (PIN/Pattern/Biometrics) to be enabled on the host OS. |
| **StrongBox / TEE Behavior** | Hardware module executes unwrap without requiring an OS-level authentication token. | Hardware module enforces key authorization via an OS-signed auth token (e.g., Gatekeeper/LDF). |
| **Rooted-Device Implications** | Kernel/root compromised OS can request the TEE to unwrap keys freely without user knowledge. | Hardware module enforces user auth token presence; root cannot forge hardware-backed auth tokens without exploiting the TEE/StrongBox boundary. |

### Recommendation for Rocen

Recommend the stronger design (**Option B**) for Rocen. Detail the security justification, failure modes, and hardware lock enforcement behavior.

## 2. Recovery-KEK Construction

Evaluate the explicit primitive pipeline for generating the `Recovery-KEK`:

* **Pipeline 1 (Proposed):** `Normalized Password + Normalized Mnemonic` $\rightarrow$ `HKDF` $\rightarrow$ `Argon2id` $\rightarrow$ `Recovery-KEK`
* **Pipeline 2 (Standard):** `Normalized Password + Normalized Mnemonic` $\rightarrow$ `Argon2id` $\rightarrow$ `Recovery-KEK`

### Required Technical Clarifications

* **HKDF Necessity Analysis:** State precisely what cryptographic property the HKDF pre-processing stage provides that standard Argon2id with proper salt and encoding does not.
* **Decision Rule:** If HKDF provides a concrete security benefit (e.g., uniform entropy distribution or domain separation prior to memory-hard hashing), specify how and why. If it adds no meaningful security benefit, explicitly prefer the simpler standard Argon2id construction.

## 3. Exact Canonical Encoding

Define the exact byte representation used for the `Recovery-KEK` input vector to guarantee cross-device deterministic key derivation.

### Encoding Specifications

* **Password Normalization:** Explicit Unicode Normalization Form (e.g., Unicode `NFKD`).
* **Mnemonic Normalization:** BIP-39 standard whitespace/lowercase normalization and Unicode `NFKD`.
* **Character Encoding:** Strict `UTF-8` byte array conversion.
* **Field Separation:** Explicit, non-ambiguous delimiter byte or length-prefixed encoding (e.g., `Length(Password) || Password || Delimiter || Length(Mnemonic) || Mnemonic`).
* **Domain / Context Binding:** Unique prefix string (e.g., `rocen.recovery-kek.v2`).
* **Test Vectors:** Provide test vectors covering unusual Unicode characters, combining diacritics, and trailing spaces.

## 4. HKDF Implementation & Dependencies

For `Note Encryption Key` (NEK) and `GitHub Token Encryption Key` (TEK) domain separation:

* **Dependency Verification:** Verify against actual Dart/Flutter dependencies in `pubspec.lock` (e.g., `cryptography` package).
* **API Parameters Specification:**
* **Input Key Material (IKM):** 256-bit Master Key.
* **Salt:** Domain-specific static salt or salt vector.
* **Info Context String:** UTF-8 encoded domain tags (e.g., `rocen-note-encryption-v2`, `rocen-github-token-v2`).
* **Output Key Length:** 256 bits (32 bytes).

## 5. AAD and Trusted Local State

Maintain the rule: **Never trust stored AAD or generation metadata from the remote envelope as the security identity.**

### Trusted Local Source Mapping

| AAD Field | Local Source of Truth |
| --- | --- |
| `note_id` | Local Database / UI Context |
| `generation` | Local Trusted State Store |
| `record_type` | Hardcoded Application Intent |
| `crypto_format_version` | Local Runtime Constant |

### Edge Case Protocols

* **Remote Note Exists, No Local Record:** First-time sync context handling.
* **Missing Local Generation:** Initial bootstrap and record creation semantics.
* **Android Cloud Backup Restoration:** Device transition and state integrity rules.
* **Potentially Tampered Local Database:** Verification and corruption handling.

## 6. Anti-Replay Strategy & Trust Boundaries

Clearly distinguish the mathematical capabilities and constraints of replay protection under a remote-untrusted GitHub transport model:

* **Already-Seen Generation:** Cryptographically and statefully bound to local state $\rightarrow$ Deterministic rollback detection.
* **First-Sync / New Device Generation:** Cannot be cryptographically proven as "current" solely from untrusted remote data without a secondary trusted anchor.
* **Constraint Statement:** Do NOT claim complete remote rollback prevention unless a separate trusted integrity mechanism exists.

## 7. Master Key Invariants

Enforce the fundamental system invariant:

$$\mathbf{\text{ONE USER DATA SET}} = \mathbf{\text{ONE MASTER KEY}}$$

* **Multi-Device Safety Rule:** A secondary device must **never** generate an independent Master Key when connecting to an existing encrypted repository.
* **Enforcement:** Code assertions, flow checks, and dedicated integration tests preventing dual-MK state creation.

## 8. Note Title Privacy

* **Strict Privacy Policy:** Note titles must be encrypted alongside note bodies (`encrypted_note` format).
* **UI Representation:** Unauthenticated list views display generic lock indicators (`"Locked Note"`) until the Master Key / NEK is unwrapped in memory.

## 9. Final Key Hierarchy Specification

Provide a unified architectural diagram and specification detailing:

```
[ Password ] ────────────► Argon2id ──────────────► Password-KEK ┐
                                                                 ├─► Wraps/Unwraps Master Key
[ Password + Mnemonic ] ─► Argon2id / Encoding ──► Recovery-KEK ┘
                                                                 ▲
[ Biometric / PIN ] ────► Hardware Key (TEE/StrongBox) ─────────┘

                                ┌──► HKDF ──► Note Encryption Key (NEK)
[ Unwrapped 256-bit MK ] ───────┤
                                └──► HKDF ──► Token Encryption Key (TEK)

```

Distinguish:

* **Authentication Secrets:** Password, Mnemonic, Hardware Authentication Token.
* **KEKs / Wrappers:** Password-KEK, Recovery-KEK, Hardware Wrapping Key.
* **Root Keys:** Master Key (MK).
* **Domain Encryption Keys:** Note Encryption Key (NEK), Token Encryption Key (TEK).

## 10. Staged Implementation Plan

Break implementation into small, independently testable phases. For each stage, specify:

1. **Files Affected:** Complete file paths (`MUST`, `MAY`).
2. **New Security Tests:** Unit, integration, and failure-injection tests.
3. **Established Security Property:** The cryptographic guarantee locked in by the stage.
4. **Dependencies on Previous Stages:** Stage dependency sequence.
5. **Rollback / Recovery Risk:** Mitigation strategies for data loss or migration failure.

> **STOP Directive:** Do NOT modify code. Do NOT create commits. Do NOT implement anything yet. Wait for explicit approval after this final review.

# AUDIT

## Rocen Master-Key Architecture v3 — Final Design Review

No code modified. This resolves the ten outstanding points before implementation.

## 1. Hardware User Authentication — Re-Evaluated Under Maximum-Security Priority

**Option A: Hardware key without user authentication (my prior recommendation)**
- Attacker protection: any code running as the app's own UID can invoke the wrap the instant the process is alive — no fresh proof of physical user presence required.
- UX cost: none — fully transparent.
- Device compatibility: universal — no biometric hardware required.
- StrongBox/TEE behavior: identical either way at the key-isolation level; this flag doesn't change where the key lives, only what's required to invoke it.
- Rooted-device implications: a sufficiently privileged attacker (Attacker C) who can execute code as the app's UID can invoke the wrap with zero additional barrier.

**Option B: Hardware key with `setUserAuthenticationRequired(true)`**
- Attacker protection: meaningfully stronger against exactly the attacker class most relevant to a mobile note/password app — someone with **transient physical access to an unlocked-but-unattended device**, or a malicious app running silently in the background. Android enforces the authentication check **inside the Keystore/TEE/StrongBox boundary itself**, not in app code — meaning even a fully compromised app process (a bug, an injected library, a malicious dependency) cannot invoke the key without a fresh biometric/PIN check happening through the OS's own trusted UI, which app-level code cannot spoof or intercept. This closes a real, distinct threat: Attacker A (an ordinary malicious app, no root) gains nothing from having compromised Rocen's own process if the hardware key still demands a fresh authentication the malicious code cannot itself satisfy.
- UX cost: real — every hardware-wrap-based unlock now requires a biometric/PIN prompt, not a silent background operation. This is a genuine, felt cost, not a theoretical one.
- Device compatibility: near-universal on modern Android (any device with a configured lock-screen credential satisfies this; biometric hardware specifically is not required — Android's `BiometricPrompt`/`KeyguardManager`-backed authentication also accepts a device PIN/pattern/password as a fallback authenticator).
- StrongBox/TEE behavior: **StrongBox enforces this at the secure-element level** — the authentication-required flag is honored by the secure element itself, meaning even direct hardware-level attacks against the AP (application processor) cannot bypass it. TEE-only enforcement is a step weaker (enforced by the TEE, not a physically separate chip) but still meaningfully stronger than Option A, since it still requires going through Android's own authentication flow rather than a bare API call.
- Rooted-device implications: this is the single most important distinction. **A rooted device can bypass in-app checks but generally cannot forge a successful biometric/`KeyguardManager` authentication result to the Keystore/TEE/StrongBox boundary itself** — this is specifically what `setUserAuthenticationRequired` is designed to resist, unlike a root-detection heuristic (which a sophisticated attacker can spoof) or an app-level PIN check (which a sufficiently privileged attacker can patch out). This is a genuine, qualitatively different security property from anything else in this architecture, because it's the **one mechanism in the entire design that resists a fully root-compromised process**, rather than merely raising the cost.

**Recommendation: Option B.** Per your explicit instruction to choose the stronger design unless it makes the product fundamentally unusable, and given a biometric/PIN prompt on unlock is a completely standard, well-understood UX pattern (used by essentially every password manager and secure-notes app), this does not meet the "fundamentally unusable" bar. **I am reversing my prior "optional future enhancement" framing — this belongs in the core architecture, not a follow-on.**

**Concrete design consequence:** `getOrCreateHwKey`'s `KeyGenParameterSpec.Builder` must add `.setUserAuthenticationRequired(true)` and `.setUserAuthenticationParameters(timeout = 0, KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL)` (the modern, non-deprecated API — `setUserAuthenticationValiditySeconds` is deprecated since API 30). Every `hwEncrypt`/`hwDecrypt` invocation must now be wrapped in a native `BiometricPrompt` flow before the Cipher operation can proceed — this is new UI/native work beyond what exists today (confirmed: no `local_auth`-equivalent or native `BiometricPrompt` integration exists anywhere in the current codebase), and is scoped explicitly as its own implementation stage (Section 10, Stage 6).

**Fallback behavior when biometric auth is unavailable/fails/is cancelled:** falls through to Password-KEK exactly as any other hardware-wrap failure does (Section 17's existing behavior) — never a security regression, only a convenience one.


## 2. Recovery-KEK Construction — HKDF's Actual Role Re-Examined, Not Assumed

You're right to push on this, and I need to be precise rather than defensive about my prior answer.

**What HKDF actually is:** a two-stage construction — `HKDF-Extract` (compress a possibly-non-uniform input into a uniform pseudorandom key using an HMAC with a salt) followed by `HKDF-Expand` (stretch that into one or more output keys bound to context-specific `info` strings). Its designed purpose is **taking an already-adequate-entropy secret and safely deriving multiple independent-looking subkeys from it** — exactly what I used it for correctly in Section 3 (MK → NEK, MK → TEK).

**Does a password+mnemonic combination need HKDF's extract-then-expand structure before Argon2id?** No — and I was wrong to imply otherwise by including it in that stage. Here's the precise reasoning: **Argon2id itself already performs the role HKDF-Extract would perform** — it takes an input (of essentially any structure or entropy distribution) and a salt, and produces a uniform, high-entropy output. Prepending an HKDF-Extract stage before Argon2id adds no property Argon2id doesn't already provide on its own; Argon2id **is** the appropriate single-stage KDF for "turn a human-provided secret into a cryptographic key," precisely because (unlike HKDF, which assumes its input already has adequate entropy and is comparatively cheap/fast) Argon2id is specifically designed to be *slow and memory-hard*, resisting offline brute-force against a low-entropy human input — which is exactly the property a password+mnemonic combination needs, and exactly what HKDF does **not** provide (HKDF is fast by design, since it assumes its input is already a good key).

**Direct answer to your question: HKDF's extract-then-expand structure adds no meaningful security benefit here, and I should not have proposed layering it in front of Argon2id. The simpler, standards-correct construction is:**

```
recoveryInput = canonicalEncode(normalizedPassword, normalizedMnemonic, domainString)
Recovery-KEK = Argon2id(recoveryInput, saltRecovery, memory, iterations, parallelism=1, hashLength=32)
```

**One HKDF stage does remain correctly justified elsewhere, and I want to be precise about the distinction rather than remove HKDF entirely:** MK → NEK/TEK (Section 3) is a genuinely different scenario — there, the input (MK) is **already** a uniform, high-entropy 256-bit random value with no brute-forcing concern at all; the *only* goal is domain separation of an already-good key into multiple independent-looking subkeys, which is precisely HKDF-Expand's designed purpose (and where a slow KDF like Argon2id would be actively wrong to use — needlessly slow for no security benefit, since there's no low-entropy secret to protect against guessing). **These are two different problems requiring two different tools, and I conflated them in my prior draft by treating "HKDF" as generically stronger without asking what specific property it contributes in each specific case.** Corrected:
- **Password/mnemonic → Recovery-KEK: Argon2id alone**, no HKDF stage.
- **MK → NEK/TEK: HKDF-Expand alone** (no Argon2id — MK doesn't need brute-force resistance, it needs domain-separated expansion).

## 3. Exact Canonical Encoding for Recovery-KEK Input

```
1. normalizedPassword = NFC(rawPasswordString)
2. normalizedMnemonic = NFKD(rawMnemonicWords.join(" "))
   — NFKD specifically, matching BIP-39's own reference normalization convention,
     applied to the space-joined 12-word phrase as a single string
3. domainString = "rocen:v2:recovery-kek" (fixed ASCII literal, never localized/varied)

4. Canonical byte encoding, using explicit length-prefixing (not bare
   null-byte separation as I proposed in v2 — length-prefixing is the more
   rigorous, ambiguity-free standard construction, since a null byte could
   theoretically appear inside a UTF-8-encoded password containing unusual
   code points, whereas a length prefix is unambiguous regardless of content):

   passwordBytes = utf8.encode(normalizedPassword)
   mnemonicBytes = utf8.encode(normalizedMnemonic)
   domainBytes   = utf8.encode(domainString)

   recoveryInput = 
       uint32BE(passwordBytes.length) ++ passwordBytes ++
       uint32BE(mnemonicBytes.length) ++ mnemonicBytes ++
       uint32BE(domainBytes.length)   ++ domainBytes

   (uint32BE = 4-byte big-endian unsigned length prefix, applied before each
   field — this is a standard, unambiguous canonical-encoding technique
   directly borrowed from TLS/protocol-buffer-style length-prefixed field
   encoding, chosen specifically because it makes "where does field A end
   and field B begin" independent of the field contents, closing the
   ambiguity concern you correctly flagged.)
```

**Test vectors** (illustrative byte-length arithmetic, since I cannot execute NFC/NFKD normalization or UTF-8 encoding in this text-only response — these must be generated and verified by actually running Dart's/ICU's normalization implementation before being trusted as real vectors, and I want to be explicit about that limitation rather than fabricate output bytes I haven't actually computed):

| Case | Raw input | Why it's a meaningful test |
|---|---|---|
| 1 | Password: `"café"` (composed, single U+00E9) vs. `"café"` (decomposed, `e` + U+0301 combining acute) | Both must normalize to the **identical** NFC byte sequence — this is the exact cross-keyboard/cross-input-method scenario NFC normalization exists to fix. Test: assert `NFC(composed) == NFC(decomposed)` byte-for-byte. |
| 2 | Password containing an emoji with a variation selector (e.g., a base emoji + U+FE0F) | Confirms NFC normalization handles variation selectors consistently — some normalization forms can behave unexpectedly around emoji sequences; this must be explicitly verified against Dart's actual ICU-backed normalizer, not assumed. |
| 3 | Mnemonic with mixed case input (`"Abandon Ability Able..."`) vs. lowercase (`"abandon ability able..."`) | Must produce identical `normalizedMnemonic` bytes after the explicit lowercase step — this is a normalization-*procedure* test (confirming the lowercase step runs before NFKD, not after, since order matters if any word contains case-sensitive Unicode edge cases). |
| 4 | Password of exactly 0 bytes (empty string, if the UI ever permitted it — should be rejected upstream, but the encoding function itself should not crash) | Confirms `uint32BE(0)` followed by zero content bytes is well-formed and doesn't corrupt the following field's boundary. |
| 5 | Password containing a right-to-left (RTL) Unicode string (e.g., Arabic or Hebrew characters) | Confirms UTF-8 byte-encoding (not visual/display order) is what's used — RTL rendering must never affect the underlying byte sequence, and this test exists specifically to catch a bug where some naive "reverse for display" logic accidentally leaks into the encoding path. |

**Same credentials → identical bytes on every device:** guaranteed by (a) using Dart's own `String` NFC/NFKD normalization (available via `package:characters` or Dart's built-in Unicode-aware string handling — needs confirming which exact API call is used, flagged for Stage 1 implementation, not invented here), which is deterministic across platforms since it's ICU-backed and Flutter ships a consistent ICU version per Flutter SDK release, not per-OS; and (b) the explicit length-prefixed encoding removing any ambiguity from variable-length UTF-8 sequences.

## 4. HKDF Implementation — Verified Against Actual `cryptography` Package API

Per `pubspec.lock` (confirmed this session): `cryptography: 2.9.0`. Let me verify the actual API surface rather than assume.Confirmed, real API, version-matched to `2.9.0` (which is `>= 2.7.0`, the version that introduced the cross-platform Argon2id support this codebase already depends on for everything else — so `Hkdf` and `Argon2id` are both available in the exact dependency already pinned, no version bump needed).

**Important finding from the docs directly:** the `Hkdf` class's `deriveKey({secretKey, nonce})` signature does **not** expose a separate `info` parameter in its public `deriveKey` call shape shown in the official example — it takes `secretKey` and `nonce` only. This means **RFC 5869's `info` parameter, which is exactly what I need for domain separation, must be passed via a different mechanism than I assumed.** I should not guess at an unverified secondary API surface; let me check precisely how `info` is actually supplied in this package's `Hkdf` class before specifying anything as final.Confirmed, from the actual method signature listing (not the abbreviated example): `deriveKey({required SecretKey secretKey, List<int> nonce = const <int>[], List<int> info = const <int>[]})` — **`info` is a genuine, real, documented named parameter**, just omitted from the abbreviated code sample. This maps directly onto RFC 5869's construction: `secretKey` = the input keying material (IKM, here MK), `nonce` = the HKDF `salt` parameter (RFC 5869 calls it `salt`; this package names the parameter `nonce`, worth flagging precisely since it's an easy naming mix-up against AES-GCM's own unrelated "nonce"), `info` = the domain-separation context string.

**Exact, verified specification for NEK/TEK derivation:**

```dart
final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

final nekSecretKey = await hkdf.deriveKey(
  secretKey: SecretKey(masterKeyBytes),      // MK, as raw bytes wrapped in SecretKey
  nonce: <int>[],                             // RFC 5869 salt: empty is valid per spec when
                                               // no independent salt is available; MK's own
                                               // high entropy makes an empty extract-salt
                                               // cryptographically acceptable here (RFC 5869
                                               // Section 2.2 explicitly permits omitting salt)
  info: utf8.encode('rocen:v2:notes'),
);

final tekSecretKey = await hkdf.deriveKey(
  secretKey: SecretKey(masterKeyBytes),
  nonce: <int>[],
  info: utf8.encode('rocen:v2:github_token'),
);
```

**Input key material:** MK's raw 256-bit bytes, wrapped in `SecretKey`.
**Salt (`nonce` parameter):** empty list — RFC 5869 permits this when the IKM is already high-entropy (true here; MK is CSPRNG-generated, not a low-entropy password), and using a fixed empty salt across all domain derivations is standard practice specifically because `info` alone is sufficient to guarantee distinct outputs per domain when extracting from the same high-entropy IKM.
**Info:** the fixed domain strings `"rocen:v2:notes"` / `"rocen:v2:github_token"`, UTF-8 encoded — exactly the mechanism RFC 5869 designates for domain separation.
**Output length:** 32 bytes (256 bits), matching AES-256-GCM's key size, set via the `Hkdf` constructor's `outputLength` parameter.

This is not invented — it's the package's actual, documented, version-matched API, used exactly as its own constructor example demonstrates, with the `info` parameter confirmed present from the method signature listing rather than assumed from the abbreviated sample.

## 5. AAD and Trusted Local State — Every Edge Case You Specified

| Scenario | What happens |
|---|---|
| **Note exists remotely but not locally** | This is a legitimate first-sync case (a note created on Device A, being pulled by Device B for the first time). The decrypting device has **no local record at all** for this `noteId` — there is no `expectedGeneration` to compare against. The AAD must still be constructed, but `expectedGeneration` in this specific case is **not "trusted local state" in the rollback-detection sense — it's "accept whatever generation this first-observed copy claims, and immediately adopt it as the new local baseline for future comparisons."** This is the honest trust-on-first-use moment already flagged in Section 12 (unchanged) — the AAD construction itself still requires *some* generation value to bind against for the cryptographic operation to even be attempted, so the first-sync case uses the fetched value **not as an authenticated trust claim about recency, but as the necessary input to attempt decryption at all**, with the explicit, logged understanding that this specific decrypt provides no rollback protection, only ordinary tamper/substitution protection (Section 12's point 2, which *is* fully solved). |
| **Local generation is missing** (e.g., a data-model bug, or a note that predates the `generation` field's introduction) | Treated identically to "note exists remotely but not locally" above — no local baseline means no rollback-detection capability for that specific note until this decrypt succeeds and establishes one. This should be logged/surfaced distinctly (a new `NoLocalBaselineFailure`-adjacent *informational* state, not a hard failure) so it's visible in diagnostics rather than silently indistinguishable from "everything is normal and verified." |
| **Local state was restored from Android backup** | This is a genuinely important, previously-unaddressed case, and I want to be direct: **if Android's OS-level backup (per the original audit's Finding H-6, which recommended disabling `allowBackup` entirely) ever restores `rocen_settings_box` onto a device, the restored `lastKnownGeneration` map reflects whatever state existed *at backup time*, not the device's actual, current, continuous history.** If an attacker can trigger or manipulate a backup/restore cycle to roll a device's *local* rollback-detection baseline backward, the device would then fail to detect a *remote* rollback to anything at or above that stale-but-restored baseline. **This is a direct, concrete reason — beyond the confidentiality argument already made in the original audit — to disable `allowBackup` entirely**, since this redesign's rollback-detection mechanism specifically depends on local state being genuinely continuous and attacker-uninterruptible, which OS-level backup/restore does not guarantee. I'm elevating Finding H-6 from "hardening opportunity" to "a direct dependency of this redesign's anti-rollback mitigation" — it should be treated as part of this implementation, not a separate, lower-priority item. |
| **Local state itself may have been modified** (e.g., a rooted device, Attacker C, directly edits the `lastKnownGeneration` Hive value to a lower number before syncing) | **Honestly acknowledged limitation, not solved by this design.** If the attacker already has write access to the device's own local storage, they can simply lower the local baseline to whatever value they want, defeating the rollback-detection mechanism for that device entirely. This mechanism protects against a **remote-only** attacker (Attacker D — GitHub write access, no local device access) attempting to roll back what an *honest, uncompromised* device would notice — it provides no protection once the attacker also controls the local device doing the checking. This should be stated plainly in the eventual code comments and any user-facing security documentation, not implied to be stronger than it is. |
| **A new device sees a note for the first time** | Identical to "note exists remotely but not locally" above — this is the same case described from a different angle; no duplicate mechanism needed. |

## 6. Anti-Replay — Restated, Unchanged, Confirmed

Kept exactly as the honest distinction from the prior draft, now reinforced by point 5's backup-restore analysis, which actually *widens* the acknowledged gap rather than narrowing it: **already-seen-generation rollback is detectable on an honest, backup-uninterrupted device with local-storage integrity intact; first-sync generation and backup-restored/locally-compromised state are not cryptographically provable as current within the current GitHub-only trust model.** No claim of full rollback prevention is made anywhere in this design.

## 7. Master Key Generation — The Invariant, Enforced Precisely

**ONE USER DATA SET = ONE MASTER KEY.** Concrete enforcement, both procedural and testable:

**Generation gate, exact logic:**
```
Before generating a new MK, the app MUST check, in this order:
1. Does a local wrapped-MK-of-any-kind already exist in rocen_settings_box?
   → If yes: STOP. This is not first-time setup. Refuse to generate a new MK.
2. Does a device_key.json already exist in the configured GitHub repository
   (checked via a live GitHub API call, not merely "did I ever set up GitHub
   locally")?
   → If yes: STOP. This device is joining an EXISTING data set. Route to the
     recovery flow (Section 4), never the generation flow, regardless of
     what the local onboarding UI state suggests.
3. Only if BOTH checks come back negative does the app proceed to generate
   a genuinely new, first-ever MK.
```

**Why step 2 (a live remote check, not just a local one) is essential, not optional:** a purely local check (step 1 alone) would fail to catch the exact dangerous scenario this invariant exists to prevent — a user setting up Rocen fresh on Device B, pointing it at the **same GitHub repository** Device A already uses, without having gone through Device A's recovery flow first (e.g., they forgot they'd used Rocen before, or are following stale instructions). Without step 2, Device B would see no *local* wrapped-MK, conclude "first-time setup," generate an **independent, different MK**, and silently begin encrypting new notes under a key incompatible with everything Device A already wrote — a serious, silent data-fragmentation bug that would not surface as an obvious error, only as "some of my notes won't decrypt on this device," likely much later.

**Enforced in tests, exactly as required:**
- Test: local wrap absent, remote `device_key.json` absent → MK generation proceeds, exactly once.
- Test: local wrap absent, remote `device_key.json` **present** → MK generation is refused/blocked; the app routes to the recovery flow instead, and an explicit assertion confirms the MK-generation function was never invoked.
- Test: local wrap present → MK generation is refused regardless of remote state (no need to even check remote in this case, though checking anyway is harmless).
- Test (adversarial): simulate a race — two devices both perform step 1 and step 2 successfully (both see "no wrap, no remote file") and both proceed to generate independently, nearly simultaneously (a genuine, rare race condition even with correct per-device logic) → assert that whichever device's `device_key.json` write reaches GitHub first "wins" (via the existing fast-forward/conflict mechanism), and the second device's own generation attempt, upon its own subsequent publish attempt failing the fast-forward check, must **detect this specific failure mode** and re-route itself to the recovery flow using the *other* device's now-published MK, rather than proceeding with its own independently-generated, now-orphaned MK. This is a genuinely important edge case your instruction to enforce this "in code and in tests" surfaces, and I want to flag it explicitly as a real implementation requirement, not just a happy-path check.

## 8. Title Encryption — Confirmed, Unchanged

Kept exactly as the maximum-security recommendation from the prior draft: `encrypted_note` titles are encrypted (using NEK, alongside/adjacent to the body, per Section 11's prior construction), and the list UI shows a generic locked placeholder until the specific note is opened and unlocked. No change from the previous draft; restated here only for completeness per your numbered list.

## 9. Final Key Hierarchy Diagram

```
┌────────────────────────┐        ┌──────────────────────────┐        ┌───────────────────────────┐
│  AUTHENTICATION SECRETS  │        │  DEVICE AUTHENTICATION     │        │  (Nothing else authenticates│
│                          │        │  (biometric/PIN, Section 1)│        │   directly — by design)     │
│  Password (typed)         │        │                            │        │                             │
│  Mnemonic (12 words,       │        │  Verified by Android's own  │        │                             │
│  never persisted)          │        │  Keystore/BiometricPrompt   │        │                             │
└──────────┬───────────────┘        │  boundary, NOT by app code   │        └───────────────────────────┘
           │                        └──────────────┬─────────────┘
           │                                        │
           │                          gates invocation of ▼
           │                        ┌──────────────────────────┐
           │                        │  HARDWARE-BACKED WRAPPING  │
           │                        │  KEY (Keystore/StrongBox)  │
           │                        │  Never leaves secure       │
           │                        │  hardware; requires fresh  │
           │                        │  biometric/PIN per use     │
           │                        └──────────────┬─────────────┘
           │                                        │ wraps
           │                                        ▼
           │                        ┌──────────────────────────┐
           │                        │  Hardware-wrapped MK        │◄─┐
           │                        │  (device-local only,        │  │
           │                        │   never synced)              │  │
           │                        └──────────────────────────┘  │
           │                                                        │
           ▼                                                        │
┌─────────────────────────┐                                        │
│  KEKs (key-encryption keys)│                                       │
│                            │                                       │
│  Password-KEK =             │                                       │
│    Argon2id(password,       │───wraps──────────────────────────────┤
│    saltKEK)                 │                                       │
│                            │                                       │
│  Recovery-KEK =             │                                       │
│    Argon2id(canonicalEncode │───wraps──────────────────────────────┤
│    (password, mnemonic,     │                                       │
│    domain), saltRecovery)   │                                       │
│  (requires BOTH factors,    │                                       │
│   Section 4 mandatory)      │                                       │
└─────────────────────────┘                                       │
                                                                       ▼
                                                    ┌─────────────────────────────┐
                                                    │   MASTER KEY (MK)              │
                                                    │   256-bit random, independent  │
                                                    │   of password, never stored    │
                                                    │   unwrapped, ONE per user data  │
                                                    │   set (Section 7 invariant)     │
                                                    └────────────────┬───────────────┘
                                                                     │
                                            HKDF-Expand(MK, info=domain, salt=empty)
                                                                     │
                                    ┌────────────────────────────────┼─────────────────────────────┐
                                    ▼                                ▼                              ▼
                        ┌────────────────────┐         ┌────────────────────┐        ┌──────────────────────┐
                        │ DOMAIN DATA-         │         │ DOMAIN DATA-         │        │ (future domain keys,  │
                        │ ENCRYPTION KEY:       │         │ ENCRYPTION KEY:       │        │  derived identically,  │
                        │ Note Encryption Key   │         │ Token Encryption Key  │        │  no architecture       │
                        │ (NEK)                 │         │ (TEK)                 │        │  change needed)        │
                        │ AES-256-GCM            │         │ AES-256-GCM            │        │                        │
                        │ encrypts: note title +│         │ encrypts: GitHub token │        │                        │
                        │ body, per-note AAD     │         │ AAD: device-bound      │        │                        │
                        └────────────────────┘         │ context string          │        └──────────────────────┘
                                                        └────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│  SEPARATE, NEVER TOUCHING ANY OF THE ABOVE:                                │
│  Password Verifier = Argon2id(password, saltVerifier) → verifyPin() ONLY   │
└────────────────────────────────────────────────────────────────────────────┘
```

**Explicit category labels, as requested:**
- **Authentication secrets:** password (typed, never stored raw), mnemonic (never persisted), device biometric/PIN (verified entirely inside Android's own trusted boundary, never by app code).
- **KEKs:** Password-KEK, Recovery-KEK — both transient, never stored, exist only to wrap/unwrap MK.
- **Wrapping keys:** the same two KEKs, plus the hardware-backed Keystore/StrongBox key — all three are "wrapping keys" in the sense that their sole job is protecting MK, not encrypting user data directly.
- **Domain data-encryption keys:** NEK, TEK — derived, never stored, used directly for AES-GCM on actual user data.
- **Hardware keys:** the Keystore/StrongBox-resident AES key specifically, distinguished from the KEKs because it's generated and held entirely within hardware, never derived from anything the app computes.



## 10. Final Implementation Stages

Each stage independently testable, with an explicit rollback story if something goes wrong mid-stage.

### Stage 1 — Canonical encoding primitives
**Files:** new `canonical_encoding.dart` (password/mnemonic normalization, length-prefixed byte encoding per Section 3).
**Tests:** all five test vectors from Section 3; round-trip determinism (same input → same bytes, every call).
**Security property established:** none directly exploitable yet — this is a pure, side-effect-free utility layer.
**Depends on:** nothing.
**Rollback/recovery risk:** none — this stage touches no stored data and no existing code path.

### Stage 2 — Master Key generation and the one-MK invariant
**Files:** `crypto_engine.dart` (new `generateMasterKey()`, the gating logic from Section 7).
**Tests:** the four Section 7 tests (fresh generation, local-wrap-blocks-regeneration, remote-file-blocks-regeneration, race-condition re-routing).
**Security property established:** MK is generated correctly, exactly once, with the invariant enforced and tested before any wrapping/encryption logic exists to consume it.
**Depends on:** Stage 1 (for any encoding MK generation itself might need — likely none, since MK is raw random bytes, but the test harness may reuse Stage 1 utilities).
**Rollback/recovery risk:** none — MK generation in isolation, with no wrap/store logic yet wired in, cannot yet affect any real data.

### Stage 3 — Password-KEK, Verifier, and their wrap/unwrap of MK (local-only, no hardware, no recovery yet)
**Files:** `crypto_engine.dart` (Password-KEK derivation, verifier derivation with separate salt, MK wrap/unwrap envelope read/write per Section 13's wrap-envelope fields).
**Tests:** Section 18 tests 5-8 (correct/wrong password, password-change-preserves-MK, no-unnecessary-re-encryption), plus tests 1-2 (verifier isolation from Password-KEK).
**Security property established:** the core Finding-3A fix — a stored verifier can no longer be used to derive anything that unwraps MK.
**Depends on:** Stage 2 (needs a real MK to wrap).
**Rollback/recovery risk:** low — still entirely local, no GitHub interaction, no UI wired to real user flows yet (can be built and tested behind a feature flag / in isolation from the live password-setup screen).

### Stage 4 — HKDF domain separation (NEK, TEK)
**Files:** `crypto_engine.dart` (the verified `Hkdf` usage from Section 4).
**Tests:** Section 18 tests 3-4 (domain separation, determinism).
**Security property established:** notes and token are no longer protected by the same key material.
**Depends on:** Stage 2 (needs MK).
**Rollback/recovery risk:** none — purely additive derivation logic, no stored-data format change yet.

### Stage 5 — Envelope v2 (notes and token), AAD construction from trusted local state
**Files:** `crypto_engine.dart` (envelope read/write per Section 13), `database.dart` (`generation` field on `CaptureItem`, `lastKnownGeneration` local tracking map per Section 5/12), `quicknote.dart` (wire note save/load to NEK + AAD construction).
**Tests:** Section 18 tests 15-27 (the full AAD/tamper/versioning/rollback-detection suite).
**Security property established:** Findings 3D (metadata tamper) and the already-seen-generation rollback detection (Section 6/12) are both closed; the KDF-in-ciphertext problem (Finding 3C) is structurally eliminated for note/token data (no KDF step at decrypt time at all).
**Depends on:** Stages 2, 3, 4 (needs MK, needs Password-KEK wrapping to actually unlock MK for use, needs NEK/TEK to encrypt with).
**Rollback/recovery risk:** **moderate — this is the first stage that changes the actual stored note format.** Given your explicit statement that there are no real users yet, this can be done as a clean cutover with no migration logic, but the stage should still be tested end-to-end (create note → close app → reopen → decrypt) before merging, since a bug here directly risks the note data itself.

### Stage 6 — Recovery-KEK and the mandatory dual-factor recovery flow
**Files:** `crypto_engine.dart` (Recovery-KEK derivation per Section 2/3), `password_state_manager.dart` (`device_key.json` schema change to store Recovery-KEK-wrapped-MK), `settings.dart` (recovery UI flow, reusing/adapting the existing `_promptMnemonicRecovery` dialog).
**Tests:** Section 18 tests 9-14 (the full four-combination recovery matrix), plus a live "Device B joins Device A's existing data set" integration test.
**Security property established:** Section 1's mandatory dual-factor requirement, fully enforced and tested.
**Depends on:** Stages 2, 3, 4, 5 (needs a working MK/NEK/TEK/envelope pipeline to actually recover *into*).
**Rollback/recovery risk:** moderate-high — this is a GitHub-format-changing stage (`device_key.json`'s schema changes); since there's no legacy migration burden per your instruction, this is a clean replacement, but should be tested with real multi-device scenarios (two emulators/devices, not just unit tests) before considering it done.

### Stage 7 — Password-change flow with mandatory mnemonic re-entry
**Files:** `settings.dart` (password-change UI, adding the mnemonic-re-entry step per Section 1's Option (a) resolution).
**Tests:** Section 18 tests 7-8 (already covered by Stage 3, extended here to also verify Recovery-KEK is correctly re-wrapped in the same atomic operation), plus an interruption test (crash mid-change, verify old credentials remain valid until the operation fully completes).
**Security property established:** the old-password-still-works-via-recovery window (Section 9) is fully closed, not just bounded.
**Depends on:** Stages 3, 6 (needs both KEK types working).
**Rollback/recovery risk:** moderate — password change is a sensitive, user-facing flow; the interruption-safety testing here matters as much as the happy path.

### Stage 8 — Hardware wrap with mandatory user authentication
**Files:** `MainActivity.kt` (new `masterKeyAlias`, `setUserAuthenticationRequired(true)`, `BiometricPrompt` integration), `crypto_engine.dart` (wire hardware wrap/unwrap of MK through the new channel calls).
**Tests:** Section 18 tests 28-31 (StrongBox, TEE, unavailable, invalidation), plus a new test confirming a biometric-prompt cancellation correctly falls back to Password-KEK without ever exposing MK insecurely.
**Security property established:** Section 1's resolved requirement — hardware-wrapped MK now genuinely resists a compromised-app-process attacker, not just providing convenience.
**Depends on:** Stages 2, 3 (needs MK and at least one working software-only wrap path to fall back to).
**Rollback/recovery risk:** low-moderate — this is additive (a new, optional wrap path); if it fails entirely, the app should already work correctly via Password-KEK alone from Stage 3 onward, so this stage's own bugs are contained rather than blocking core functionality.

### Stage 9 — `_isHardened()` re-scoping and fail-closed fix
**Files:** `crypto_engine.dart` (narrow `_isHardened()` to only gate new-wrap-creation parameters, per Section 14; flip its fail-closed default from `false` to `true`, now safe per this session's earlier analysis).
**Tests:** confirm `_isHardened()` is never called from the note/token decrypt path at all (a static/structural check, not just a runtime test); confirm the fail-closed flip doesn't affect any already-passing test from earlier stages.
**Security property established:** the last piece of the original Finding 3C/Section-16-fail-open cluster, fully closed.
**Depends on:** Stage 5 (envelope v2 must exist for this to be safe, per this session's own earlier, correct reasoning for deferring it).
**Rollback/recovery risk:** very low — small, well-isolated change at this point in the sequence.

### Stage 10 — End-to-end migration cleanup (not user-data migration, code cleanup)
**Files:** removal of `migrateEncryptedNotes` (Section 13, now dead code), removal of the old `encryptProcess`/`decryptProcess` call sites that used `pinHash` directly, final removal of `system_crypto_pin`'s old dual-purpose role.
**Tests:** a full regression pass across every test from Stages 1-9, run together, to confirm nothing in the cleanup broke an earlier-established property.
**Security property established:** no dead/misleading code paths remain that could confuse a future maintainer into reintroducing Finding 3A by calling old, still-present-but-unused functions.
**Depends on:** all prior stages.
**Rollback/recovery risk:** low — this is subtractive (removing code), and since it's the last stage, any issue found here reflects a gap in an earlier stage's testing, not new risk introduced by cleanup itself.

No code has been modified. Awaiting your approval before implementation of Stage 1 begins.

# PROMPT

## Architectural Refinement Directives (Pre-Stage 1 Approval)

Before Stage 1 approval, resolve these final design corrections and clarifications explicitly.

## 1. Master-Key Session Lifetime

The hardware-authentication design protects the hardware-key unwrap operation, but once the Master Key (MK) is unwrapped, it resides in application memory.

Define the following memory lifecycle properties:

* **Memory Ingress:** Exact event when MK enters application memory.
* **Storage Location:** Specific location/data structure where MK lives in memory.
* **Retention Duration:** How long MK remains resident.
* **Zeroing & Cleanup:** Triggers and mechanisms for clearing/zeroing memory.
* **App Backgrounding:** Behavior when the app transitions to the background.
* **Inactivity Timeout:** Inactivity threshold and cleanup protocol.
* **Explicit Lock:** Purge behavior triggered by a manual lock action.
* **Derived Subkeys:** Whether derived keys (NEK/TEK) are cleared simultaneously.
* **Re-Authentication Trigger:** Specific events that require hardware authentication again.

*Note: Hardware authentication does not protect MK after it has been loaded into application memory. Choose the strongest practical session-lock policy consistent with the threat model.*

## 2. One-MK Generation & Initialization

The current design relies on checking whether `device_key.json` exists remotely before generating a new MK. Treat this as an untrusted remote state.

Define the following initialization rules:

* **Repository Ownership:** How repository ownership and initialization are established.
* **Untrusted File Handling:** How a malformed or attacker-created `device_key.json` is handled.
* **Race Condition Protocol:** How two fresh devices racing to initialize the same repository are handled.
* **Provisional Key Recovery:** How the losing device safely discards or recovers from its provisional MK.
* **Atomic Publication:** How conditional or atomic publication prevents a silent dataset fork.

*Note: Do not treat "file exists on GitHub" as proof that it is legitimate Rocen state.*

## 3. Recovery Mnemonic Entropy

**Mandatory Security Requirement:** The 12-word recovery mnemonic must be generated from a cryptographically secure entropy source with the intended entropy level.

Document the explicit parameters:

* **Entropy Size:** Exact bit-length of the entropy source.
* **Word-List Source:** Standard dictionary used (e.g., BIP-39).
* **Checksum Rules:** Verification algorithm and constraints.
* **Normalization:** Exact normalization scheme (e.g., NFKD, lowercasing).
* **Canonical Encoding:** Exact byte and string representation.

*Note: Do not rely on "12 words" alone as the security argument.*

## 4. HKDF Salt Strategy

The design currently uses an empty HKDF salt for the derivation step:

$$\text{Master Key (MK)} \longrightarrow \text{NEK / TEK}$$

Explain why this is the preferred design by evaluating:

| Strategy | Cryptographic Benefit | Interoperability | Implementation Complexity |
| --- | --- | --- | --- |
| **Option A:** Empty / Fixed HKDF Salt | Evaluate benefit | Evaluate compatibility | Low |
| **Option B:** Random Stored Non-Secret Salt | Evaluate benefit | Evaluate compatibility | Higher |

*Note: Select the approach based strictly on cryptographic benefit, interoperability, and complexity. Do not add complexity merely for appearance.*

## 5. First-Sync Trust Model

For a note that does not yet exist locally, define how the decryptor handles:

* `formatVersion`
* `keyVersion`
* `recordType`
* `generation`
* `noteId`

Categorize each field clearly:

1. **Untrusted Remote Value**
2. **Locally Trusted Expectation**
3. **Value Used Only to Select Parser / Key**

*Note: Do not allow attacker-controlled remote metadata to become trusted merely because it is needed to attempt the first decryption.*

## 6. Existing Development Data Assumptions

* **Current Environment:** The application developer is currently the sole user and has intentionally **not** created or stored any real notes, encrypted data, or GitHub backup data.
* **Remote Environment:** The GitHub repository contains no user data.

### Directives

* **No Public Migration:** Do **NOT** design a public-user migration system.
* **No v1 $\rightarrow$ v2 Migration:** Do **NOT** design a v1 $\rightarrow$ v2 data migration path for existing user data.
* **Clean Cryptographic Slate:** Treat the current implementation as a clean development state without data preservation constraints. Introduce the new architecture as a clean cryptographic format.
* **Future-Proof Versioning:** Maintain proper versioning schema so future cryptographic format updates can be migrated safely once production user data exists.

## 7. Final Implementation Order

Return only the corrected design sections and the final **Stage 1 $\rightarrow$ Stage N** dependency order.

> **STOP Directive:** Do NOT implement Stage 1 yet. STOP after the design review.

# AUDIT

## Rocen Master-Key Architecture v4 — Final Corrections Before Stage 1

No code modified. This corrects the six flagged gaps and restates the final stage order.


## 1. Master-Key Session Lifetime

You're right to press on this — the prior draft's Section 1 correctly designed hardware-authentication *at the point of unwrap*, but never defined what protects MK *after* that point, which is the actual, larger window of exposure. Fixing this properly requires being explicit about something the design didn't previously commit to: **an in-memory session model with an explicit lock state**, not just a one-time unlock event.

**When MK enters memory:** the instant any of the three unwrap paths (Password-KEK, Recovery-KEK, or hardware-wrap-with-fresh-biometric) succeeds. Never before, never speculatively, never pre-fetched.

**Where it lives:** wrapped in a `SecureBytes` instance (the existing, already-correct primitive), held by a single, app-lifecycle-scoped session object — not a `static` field on `CryptoEngine` (a `static` field is process-lifetime by default and has no natural hook for the lock events below; it needs to be an instance owned by a session-manager class whose lifecycle the app explicitly controls).

**How long it remains — this is the core policy decision, and I'm choosing the strongest practical option, not the most convenient one:**

**Session-lock policy: MK is cleared from memory whenever the app is not the foreground-visible, actively-used app — not on a timer, not "after inactivity," but tied directly to Android's own lifecycle signals, which are the only genuinely reliable trust boundary available.** Specifically:

| Event | MK behavior |
|---|---|
| App backgrounds (`AppLifecycleState.paused`/`inactive` in Flutter terms, or the equivalent native `onPause`) | **MK is zeroed immediately, synchronously, before the lifecycle callback returns.** Not deferred, not delayed by even a grace period — per your instruction to choose the strongest practical policy, a grace period is exactly the kind of convenience-motivated weakening your instructions tell me not to introduce by default. |
| App is killed by the OS while backgrounded | MK was already zeroed at the backgrounding event above — this is a non-event from MK's perspective, confirming the zero-at-background policy is what actually matters, not relying on process death alone (a backgrounded-but-not-killed process is a real, common Android state that must not leave MK resident). |
| App returns to foreground | MK is **not** automatically available — the app must re-unlock via one of the three unwrap paths again. This is the direct, unavoidable consequence of the zero-on-background policy, and it is the correct trade: it means **every foreground session starts locked**, exactly matching how a password manager or banking app behaves, not how a casual notes app typically behaves — a deliberate UX cost, chosen because your instructions specify security over convenience by default. |
| "Explicit lock" (a user-initiated "lock now" action, if one exists in the UI, or should be added) | Same as backgrounding — immediate zero. |
| Inactivity within an active foreground session (no timer-based auto-lock while actively in the foreground) | **Not implemented as a separate mechanism** — I considered proposing a foreground idle-timeout in addition to the background-triggered lock, but concluded it would be **security theater relative to the app's actual usage pattern**: a note-taking/clipboard app is used in short, active bursts, and a foreground idle-timer adds meaningful complexity (a timer that must survive screen-on/off, must not fire spuriously during normal typing pauses, must be cancelable) for a threat scenario (attacker has physical access to an unlocked, unattended, foregrounded device) that is already substantially covered by the device's own screen-lock — which, when it engages, **does** trigger the OS-level backgrounding event above via `onPause`, since a locked screen backgrounds the foreground app. I want to state this as a deliberate, reasoned omission per your "do not add complexity merely for appearance" instruction elsewhere in this conversation, not an oversight — but flag it as a decision item (Section "still requiring approval" below) since reasonable people could weigh this differently.

**NEK/TEK:** cleared at the exact same moment as MK, via the same zeroing call — they are cheap to re-derive (a single HMAC operation via HKDF, not a slow Argon2id run) the moment MK is available again, so there is no reason to treat their lifetime any differently or more leniently than MK's own.

**What event requires hardware authentication again:** every single transition from "locked" back to "unlocked" — i.e., every foreground-resume after a background-triggered lock — if the user's chosen unlock method is the hardware path. There is no "grace window" where a prior biometric check is considered still valid; Android's own `setUserAuthenticationRequired` combined with `timeout = 0` (as specified in the prior draft) already enforces "require fresh auth every single invocation" at the Keystore/TEE/StrongBox level — this design choice in Section 1 and this session's zero-on-background policy are mutually reinforcing, not redundant: the Keystore-level check prevents a compromised *process* from invoking the key without fresh auth even while MK might still be resident; the zero-on-background policy prevents MK from *remaining* resident at all once the app isn't actively in use, closing the gap your question correctly identified — that hardware authentication alone says nothing about what happens to MK once it's already sitting in plaintext application memory.

**Explicit statement per your instruction not to imply otherwise:** hardware authentication protects the **unwrap operation only** — the moment MK exists in `SecureBytes` in application memory, Android's Keystore/StrongBox boundary provides **zero further protection** for it; only the session-lock policy above, `mlock` (best-effort, already-documented as frequently unavailable), and prompt zeroing provide any protection for MK during its resident lifetime. This is a materially different, and more honest, claim than the prior draft implied by proximity (discussing hardware auth and MK protection in the same section without this explicit boundary).

---

## 2. One-MK Generation/Initialization — Treating `device_key.json` as Genuinely Untrusted Remote State

This is a real gap in the prior draft — I described the *check* ("does `device_key.json` exist") without ever asking whether its mere existence is trustworthy, which directly contradicts the design's own stated principle (Section 6, prior draft) that nothing remote is trusted by default.

**How repository ownership/initialization is established, correctly:** the mere *existence* of a file at the expected path is not proof of legitimate Rocen origin — a malicious actor with write access to the configured repository (or a user accidentally pointing Rocen at the wrong/a shared repository) could place an arbitrary, malformed, or maliciously-crafted `device_key.json` there. **Ownership must be established by successfully exercising the file, not by observing its presence.** Concretely: fetching `device_key.json` and finding a byte sequence there proves nothing; only a subsequent **successful, structurally-valid parse** (correct field types, correct lengths, matching the exact v2 schema) followed by an **attempted recovery unwrap that either succeeds or fails cleanly with a well-defined error** constitutes engaging with it as real Rocen state. Until that parse succeeds, the file must be treated as **unauthenticated bytes of unknown origin**, not as "this repository has an existing Rocen data set."

**How a malformed or attacker-created `device_key.json` is handled:** structural validation first (matching Section 6's original pattern for `password_state.json`'s `_decodeDevices` — reused, not reinvented): required fields present, correct types, salt/nonce/ciphertext lengths matching expected constants exactly. A structurally invalid file → `MalformedRemoteStateFailure`, and critically, **this must not be silently treated as "therefore no legitimate data set exists, proceed to generate a new MK."** A malformed file is evidence of *something* at that path — possibly attacker tampering, possibly corruption — and the correct fail-closed response is to **refuse to proceed with either generation or recovery**, surfacing this explicitly to the user ("the recovery file at this location appears corrupted or invalid — verify you're using the correct repository, or contact support/investigate before proceeding"), rather than defaulting to either extreme (blindly trusting it as real, or blindly ignoring it as if it weren't there).

**How two fresh devices racing to initialize the same repository are handled — this needs a concrete, atomic mechanism, not just "detect and re-route" as I gestured at previously:**

```
Device A and Device B both independently determine (via the ownership-
establishment check above) that no legitimate device_key.json exists yet.
Both proceed to:
  1. Generate their own MK-A and MK-B independently (both believe they are
     first).
  2. Derive their own Password-KEK-A/B and Recovery-KEK-A/B wraps.
  3. Attempt to PUBLISH device_key.json using a CONDITIONAL, ATOMIC write —
     specifically, GitHub's own conditional-commit mechanism: create the
     file ONLY IF the path does not already exist (using the Contents API's
     existing behavior — a PUT to a path with no `sha` parameter fails with
     a 422/409 if the file already exists, which the codebase's existing
     GithubBackupService already has direct experience handling, per the
     original audit's coverage of HTTP 409 on empty-repository
     initialization — this is the SAME conditional-write primitive, reused
     for a new purpose).
  4. Whichever device's PUT lands first succeeds normally.
  5. The LOSING device's PUT fails with the "already exists" conflict
     response. THIS IS THE SIGNAL, not a race-timing guess — the losing
     device does not need to detect the race via timing or polling; GitHub's
     own atomic file-creation semantics provide a definitive, unambiguous
     answer.
```

**How the losing device safely discards or recovers from its provisional MK:** upon receiving the conflict response, the losing device **must treat its own just-generated MK-B (and every wrap derived from it) as entirely provisional and discardable — it has not yet been used to encrypt any real, saved user data (per the generation-gate ordering: MK generation happens *before* any note encryption is attempted, and this initialization race is resolved before the user ever reaches a "create your first note" screen).** The losing device:
1. Zeroes MK-B and all its derived KEK/wrap material immediately (nothing is lost, since nothing was ever persisted or used to encrypt real content).
2. Fetches the now-confirmed-real `device_key.json` (Device A's).
3. Routes to the **recovery flow** (Section 4 of the prior draft) — prompting for password + mnemonic — to recover MK-A, the one true MK for this data set.

**This must be true by construction, not by convention:** the implementation must ensure the "generate MK, derive wraps" sequence and the "attempt conditional publish" step happen **before** any UI path that would let the user start creating real notes — i.e., first-time setup's happy-path UI should not present "you're all set, start taking notes" until the conditional-publish step has actually succeeded (or the recovery-reroute has completed cleanly). This is an ordering constraint on the onboarding flow, not just the crypto layer, and needs to be called out explicitly for the implementation stage that builds it (Stage 6, per the final ordering below).

**How conditional/atomic publication prevents silent dataset forking:** by making "does a `device_key.json` already exist" an atomically-resolved question **at the moment of write**, not a **check-then-act** race with a window in between (which is exactly what my prior draft's "check first, then generate" sequencing was vulnerable to) — the conditional PUT collapses the check-and-act race into a single atomic server-side operation, which is the standard, correct way to resolve exactly this class of race (analogous to SQL's `INSERT ... ON CONFLICT` or a compare-and-swap primitive), reusing infrastructure (`GithubBackupService`'s conditional-write handling) the codebase already has direct, tested experience with.

## 3. Recovery Mnemonic Entropy — Explicit Security Requirement, Not Assumed

Restating what the original audit already confirmed as correctly implemented (Part 1, Section 3G), now stated as an explicit, load-bearing **requirement** for this design rather than an incidental prior finding:

- **Entropy size:** 128 bits, sourced from `Random.secure()` (Dart's CSPRNG, backed by the platform's own secure random source — `/dev/urandom`-equivalent on Android). This must remain 128 bits specifically because it's what makes the 12-word/2048-word-list math work out to a correctly-checksummed phrase (below) — this is not an arbitrary choice to preserve, it's the one value that keeps the whole construction internally consistent.
- **Word-list source:** the standard BIP-39 English wordlist, exactly 2048 entries, confirmed byte-for-byte present and unmodified in `bip39.dart` (verified this session). **Requirement, stated explicitly for the first time:** this wordlist must never be silently substituted, reordered, or regionalized in a future change without re-deriving the entire checksum-validation logic, since BIP-39's checksum construction is wordlist-index-dependent.
- **Checksum rules:** SHA-256 of the 128-bit entropy; the **top 4 bits** of that hash are appended as a checksum, producing 132 total bits = exactly 12 × 11-bit word indices. This must be independently re-verified (not merely trusted from a prior read) at both generation time (constructing a valid phrase) and validation time (`validateMnemonicChecksum`, confirmed present and correctly implemented in the original audit) — **a mnemonic that fails checksum validation must never be accepted as input to Recovery-KEK derivation**, since accepting an unchecksummed 12-word string would silently and dramatically widen the effective input space beyond the intended 128 bits of designed entropy (an attacker-supplied or corrupted 12-word sequence that happens to parse as valid word indices, but fails the checksum, is not a value this system should treat as ever having been legitimately generated).
- **Normalization:** NFKD, per Section 3 (v3 draft) — restated here as this is exactly where that normalization requirement's justification lives: BIP-39's own reference specification mandates NFKD normalization of the mnemonic sentence before use, and this design follows that convention precisely so the recovery mechanism remains consistent with the standard it's based on, not merely "BIP-39-inspired" as the original audit's more cautious phrasing put it.
- **Encoding:** UTF-8, length-prefixed, exactly as specified in the v3 canonical-encoding section — restated here as the concrete encoding step that turns the normalized mnemonic string into the bytes Recovery-KEK's Argon2id call actually consumes.

**The security argument, stated correctly (not "12 words" as an assertion, but the actual math):** the security of the recovery path rests on **128 bits of genuine, CSPRNG-sourced entropy**, independently of and in addition to whatever entropy the password itself contributes — the "12 words" figure is merely the human-readable encoding of that entropy, not the security claim itself. An attacker attempting to brute-force the Recovery-KEK path must search a space bounded below by 128 bits (mnemonic) even in the (implausible) scenario where the password contributes negligible additional entropy — this is the actual, defensible security argument, and it should be documented as such (in code comments, and in any future user-facing security documentation) rather than left as an implicit assumption.

## 4. HKDF Salt for MK → NEK/TEK — Compared Explicitly, Not Asserted

**Option A: empty/fixed HKDF salt (my prior recommendation)**
- Cryptographic benefit of adding a random salt here: **none, specifically because of what HKDF's extract stage is for.** RFC 5869's own security analysis states plainly that when the input keying material (here, MK) is *already* a uniformly-random, high-entropy value — which a CSPRNG-generated 256-bit key definitionally is — the extract stage's salt provides no additional security benefit, because the extract step's entire purpose is converting a *possibly-weak-or-structured* input into a uniform pseudorandom key, a step that is already unnecessary when the input is already uniform. This isn't my own judgment call; it's HKDF's documented, standard behavior as specified in RFC 5869 Section 3.1, which explicitly notes salt is optional and its absence is safe under exactly this condition.
- Interoperability: irrelevant here — MK never leaves this application, so there's no cross-implementation interoperability concern to weigh (unlike, say, a KDF whose salt must match a value another independent system also computes).
- Implementation complexity: minimal either way — a fixed empty list versus a stored random salt is a trivial difference in code, but Option A requires storing and threading through **one fewer piece of state** (no `saltNekTek` value to generate, store, and retrieve correctly on every derivation).

**Option B: random, stored, non-secret salt**
- Cryptographic benefit: **none beyond Option A, per the reasoning above** — a random extract-salt on an already-uniform 256-bit input does not meaningfully strengthen anything, since the "weakness" a salt exists to compensate for (a structured, non-uniform, possibly-predictable-in-part input) doesn't apply to MK at all.
- Cost: an additional piece of public metadata to generate once, store correctly, and never lose (losing `saltNekTek` would make NEK/TEK unrecoverable even with a perfectly intact MK — a new failure mode with no compensating benefit).

**Decision, and why this is not "adding complexity merely for appearance" in the other direction either:** **Option A (empty/fixed salt) is the correct, standards-justified choice here, not merely the easier one.** This is a case where the *simpler* construction is also the *more correct* one, because RFC 5869 itself says so for exactly this input-entropy condition — I am not choosing it for implementation convenience; I am choosing it because Option B would add a stored value that provides no cryptographic benefit while introducing a new, unnecessary way for the system to fail (a lost or corrupted salt value). This is the same reasoning, applied honestly in the opposite direction, as my Section 2 correction regarding HKDF-before-Argon2id for the Recovery-KEK — in that case, added complexity provided no benefit and should be removed; here, added complexity (a stored salt) would likewise provide no benefit, so it should not be added in the first place.

## 5. First-Sync Trust Model — Categorized Precisely, Per Field

For a note not yet present locally, every field's status, exactly as you've asked me to separate them:

| Field | UNTRUSTED REMOTE VALUE | LOCALLY TRUSTED EXPECTATION | VALUE USED ONLY TO SELECT A PARSER/KEY |
|---|---|---|---|
| **formatVersion** | The byte as fetched — could claim any value, including one the app doesn't support, or a deliberately misleading one | None exists yet (first sync) — there is no local expectation to compare against | **This is its actual, correct role.** The fetched value is used *exclusively* to decide "which parsing/decryption code path to attempt," never treated as an authenticated claim about anything. If the app doesn't recognize it, it refuses (Section 17, prior draft) — the value's untrustworthiness is fully contained by the fact that using it only ever selects among the app's own known-safe code paths, never causes the app to trust a claim *made by* that value. |
| **keyVersion** | Same — an attacker-controlled claim | None yet, for a genuinely new note ID never seen before | Same role as formatVersion — selects which MK/wrap generation to attempt using, from the *local* device's own known key-version history (Section 16's rotation design), never trusting the claim itself as proof that version was legitimately used. |
| **recordType** | Attacker-controlled claim | None yet | Selects parsing logic (e.g., "treat this as an encrypted_note structure, not a plain note") — again, only ever used to pick among the app's own pre-defined handling paths, and this selection is *itself* re-verified by AAD authentication (below) rather than trusted outright. |
| **generation** | Attacker-controlled claim; for first-sync specifically, this is the field with the most direct rollback-relevance | None yet — this is precisely the honest gap from Sections 5/6/12 of the v3 draft, restated: there is no local baseline to compare against | **Used to construct the AAD attempted for THIS decrypt only** — critically, this is *not* the same as "trusted as the true current generation of this note in any absolute sense." It's used because *some* generation value must be bound into the AAD for the cryptographic operation to be attempted at all, and if decryption succeeds under that value, the note becomes readable — but this must be logged/flagged internally as "first-observation, no rollback-verification performed," never silently indistinguishable from a rollback-checked decrypt. |
| **noteId** | Could theoretically be omitted or mismatched in a malformed file, but for a first-sync scenario the noteId is typically what the sync/listing mechanism used to *locate* this file in the first place (e.g., derived from the filename in GitHub's directory listing, which is a slightly different trust path than a value embedded *inside* the file's JSON body) | None locally by definition (first sync) | **This is the one field where I need to correct my own v3 draft's implicit assumption.** The "locally trusted noteId" claim in the prior design assumed an *existing* local record to source it from — for first-sync, there is no such record. The correct handling: the noteId used in AAD construction must come from **the sync/listing mechanism's own determination of which file this is** (i.e., which path/filename Rocen's own sync logic decided to fetch), **not from a `noteId` field read out of the fetched file's own JSON content**, even if such a field is present. This is a subtle but important distinction — the trusted source for "which note is this" on first sync is *Rocen's own traversal logic deciding what to fetch next*, never a self-declared identity value inside the fetched payload itself, precisely because a self-declared value inside attacker-reachable content is exactly the kind of thing Section 4 (v2 draft) already established must never be trusted. |

**The overriding rule, restated precisely for the first-sync case specifically:** **no remote metadata field ever becomes "trusted" merely by virtue of being needed to attempt a first decryption.** Every field above that participates in AAD construction on first-sync does so in the narrow "value used only to select a parser/key" sense — used to *attempt* an operation, with success or failure of that attempt (via AES-GCM's tag check) being the actual, only source of assurance, never the field's mere presence or plausibility.

## 6. Existing Development Data — Confirmed, No Change to the Design's Substance

Your clarification removes an ambiguity from my own phrasing in prior drafts more than it changes the actual architecture — I had already avoided designing user-data migration per your original instruction, but had hedged some language around "no real users yet" without fully committing to treating the current repository/local state as disposable. Restated cleanly:

- **No public-user migration system is being designed** — confirmed, unchanged from the original instruction, now further confirmed by your statement that even the *current* development-phase data (local app state and the GitHub repository) contains nothing worth preserving.
- **No v1→v2 migration for existing data** — the clean cutover approach (Stage 5 in the prior draft's numbering) is correct as designed; existing local Hive data and the existing GitHub repository's contents can simply be discarded/reset as part of adopting the new format, rather than requiring any read-old-write-new compatibility code.
- **Versioning for future migrations remains fully designed** — nothing in Sections 1-5 of the v3 draft (`formatVersion`, `keyVersion`, the explicit failure behavior for unsupported versions) is weakened or removed by this clarification; it all remains exactly as designed, since its purpose was always "protect against *future* format changes once real user data exists," which your instruction explicitly asks me to continue doing.

## Final Stage 1 → Stage N Dependency Order

The v3 draft's ten stages are restructured slightly to reflect this pass's corrections — specifically, the initialization-race handling (point 2 above) and session-lifetime management (point 1 above) each need their own stage, since both are substantial enough pieces of logic to test independently rather than folding into an existing stage.

```
Stage 1  — Canonical encoding primitives
             (unchanged from v3; no dependencies)

Stage 2  — Master Key generation + one-MK invariant, INCLUDING the
             conditional-atomic-publish race resolution from Section 2
             above (expanded from v3's Stage 2 — the race-handling logic
             is substantial enough to belong here, not bolted on later)
             (depends on: Stage 1)

Stage 3  — Password-KEK, Verifier, MK wrap/unwrap (local-only)
             (depends on: Stage 2)

Stage 4  — HKDF domain separation (NEK, TEK), using the empty-salt
             construction confirmed correct in Section 4 above
             (depends on: Stage 2)

Stage 5  — MK session-lifetime manager: the zero-on-background policy,
             the single session-scoped holder object, NEK/TEK
             co-invalidation (NEW STAGE, from Section 1 above — this is
             foundational enough to establish before envelope work
             begins, since envelope encrypt/decrypt logic needs to query
             "is MK currently available" against a well-defined session
             object from the start, not have that concept retrofitted later)
             (depends on: Stage 3, Stage 4 — needs real MK/NEK/TEK to have
             something to hold a session over)

Stage 6  — Envelope v2 (notes and token), AAD construction from trusted
             local state, INCLUDING the first-sync trust categorization
             from Section 5 above
             (depends on: Stage 2, 3, 4, 5)

Stage 7  — Recovery-KEK and the mandatory dual-factor recovery flow,
             INCLUDING the malformed/untrusted-remote-file handling from
             Section 2 above
             (depends on: Stage 2, 3, 4, 5, 6)

Stage 8  — Password-change flow with mandatory mnemonic re-entry
             (depends on: Stage 3, Stage 7)

Stage 9  — Hardware wrap with mandatory user authentication, wired into
             the Stage 5 session model (a successful hardware-authenticated
             unwrap populates the same session object Stage 5 defined,
             and is subject to the identical zero-on-background policy —
             no special-cased lifetime for the hardware path)
             (depends on: Stage 2, 3, 5)

Stage 10 — `_isHardened()` re-scoping and fail-closed fix
             (depends on: Stage 6)

Stage 11 — Clean cutover: remove `migrateEncryptedNotes` and every
             old direct `encryptProcess(payload, pinHash)`-style call
             site; no data-preservation migration logic is written,
             per Section 6's confirmation above — this is pure code
             removal plus a fresh-start reset of local/remote state
             (depends on: all prior stages)
```

**One dependency change from the v3 draft worth flagging explicitly:** Stage 5 (session lifetime) now sits *before* Stage 6 (envelope) rather than being an afterthought bolted onto password-change/hardware stages later — this is a direct, structural consequence of your Section 1 correction: the envelope/decrypt logic needs a well-defined answer to "do I currently have MK available, and under what session-lock rules" from the moment it's written, not retrofitted after the fact, since retrofitting a session-lock policy onto already-written decrypt logic risks exactly the kind of "protection implied but not actually wired in" gap your Section 1 question identified in the first place.

No code has been modified. Awaiting your approval before Stage 1 implementation begins.

# PROMPT

## Final Architectural Consistency Pass: Cryptographic Directives

> **Mandatory Directive:** Do **NOT** implement Stage 1 yet. Do **NOT** modify code or create commits. This is the final consistency pass prior to freezing the design.

## 1. Resolution of Hardware Authentication Contradictions

Ensure mandatory user-authenticated hardware key wrapping is applied consistently across all sections of the design document:

* **Core Policy:** User-authenticated hardware key wrapping (`setUserAuthenticationRequired(true)` / StrongBox / TEE) is an explicit, mandatory component of the v4 core architecture—not an optional future enhancement.
* **Consistency Re-alignment:** Remove all lingering statements in *Unresolved Risks* or *Decisions Requiring Approval* that label hardware authentication as optional or deferred.
* **Cascade Updates:** Fully align the following sections with mandatory hardware authentication:
* **Unresolved Risks & Decision Ledger:** Mark user-authenticated hardware wrapping as an active, mandatory core design decision.
* **Implementation Stages & Security Tests:** Include explicit test cases for hardware key invalidation (e.g., biometric changes), auth token expiration, and hardware unavailability fallbacks.
* **Threat Model:** Formally state that local malware or unauthorized physical access cannot unwrap the Master Key (MK) without OS-verified user presence/biometric authentication.

## 2. First-Sync Metadata & Key Trust Engine

Define strict first-sync trust semantics for a new device with no existing local database records:

### Field-by-Field Trust Rules

| Field | Classification | Usage Boundary | Post-Decryption Action |
| --- | --- | --- | --- |
| **`formatVersion`** | Untrusted Remote Input | Selects parser and decryption algorithm version. | Verified against application-supported maximum version. Downgrades are rejected. |
| **`keyVersion`** | Untrusted Remote Input | Selects Master Key version. *(Simplified to static `v1` until key rotation is introduced)*. | Validated against locally active Master Key version. |
| **`recordType`** | Untrusted Remote Input | Evaluated as a parser selector. | Reconstructed into expected local context; bound to AAD during AEAD verification. |
| **`generation`** | Untrusted Remote Input | Evaluated ONLY as candidate AAD input during initial unwrapping attempt. | **Not trusted as state.** Established locally as the trusted initial baseline generation only after AEAD tag verification succeeds. |
| **`noteId`** | Untrusted Remote Input | Selected from payload envelope to construct target context. | Formally bound to AAD. Once verified, established as the local canonical entity ID. |

### First-Sync Handling Principles

* **No Trust on Parse:** A remote envelope field is **never** treated as trusted state simply because parsing or AEAD authentication succeeded.
* **Downgrade Defense:** Unsupported or deprecated `formatVersion` values fail closed immediately before attempting cryptographic processing.
* **Key Versioning Simplification:** Because active key rotation is out of scope for this phase, `keyVersion` must remain a static constant (`v1`) to avoid unnecessary first-sync state complexity.

## 3. Strict One-Master-Key (MK) Invariant

Enforce a hard cryptographic system invariant:

$$\mathbf{\text{NO user data may be encrypted, persisted, or synced using a provisional/newly-generated MK}}$$

$$\mathbf{\text{until dataset initialization has successfully completed and ownership has been atomically established.}}$$

```
Device B Initialization Flow:
  1. Generate Provisional MK
  2. Attempt Repository Initialization
       ├── Success  ──► Provisional MK becomes Authoritative MK
       └── Conflict ──► Provisional MK is securely zeroed & discarded
                        └── Fetch & unwrap existing Authoritative MK

```

### Mandated Test Requirement

Include a dedicated automated integration test verifying that:

* **"Note creation and payload encryption are impossible prior to successful repository initialization completion."**

## 4. Memory Lifetime & Best-Effort Zeroization

Define precise, realistic memory security claims for managed runtimes (Dart/Flutter):

```
[ Unwrapped MK / NEK / TEK ] ──► Resides in Memory (SecureBytes / Uint8List)
                                           │
  ┌────────────────────────────────────────┴────────────────────────────────────────┐
  │ Triggers for Memory Purge:                                                      │
  │   • Application transition to background                                       │
  │   • Inactivity timeout threshold reached                                        │
  │   • Explicit user lock action                                                   │
  └────────────────────────────────────────┬────────────────────────────────────────┘
                                           ▼
                       [ Overwrite Memory Buffer with Zeros ]
                       [ Nullify References & Force Re-Auth ]

```

### Memory Management Rules

* **Lifetime:** Subkeys (NEK, TEK) and the MK exist in memory strictly during an active, foreground user session.
* **Purge Scope:** Backgrounding the app, reaching an inactivity timeout, or triggering an explicit lock **purges MK, NEK, and TEK simultaneously**.
* **Re-Authentication:** Returning to the foreground or restoring a session requires hardware-backed user re-authentication.
* **Realistic Boundary Claims:** Do **not** claim complete RAM erasure guarantees in a managed runtime. Instead, enforce:
* Best-effort byte overwrite (`SecureBytes` zeroization) on memory release.
* Minimal allocation lifetime and minimal copy creation.
* Prevention of key material exposure to immutable string/char objects.

## 5. Comprehensive Cross-Section Consistency Scan

Cross-check all core architectural subsystems to eliminate structural contradictions:

* **Recovery vs. Password Change:** Password changes preserve the underlying Master Key and require re-wrapping under the `Recovery-KEK` (demanding user re-entry of the mnemonic or explicit confirmation).
* **Hardware Auth vs. Memory Lifetime:** Hardware user authentication gates the initial key unwrapping step; once in memory, session lifetime controls protection until zeroization is triggered.
* **`_isHardened()` Realignment:** `_isHardened()` strictly dictates parameters for *new* key generation and wrapping operations, rather than legacy payload parsing. Envelope parameters dictate decryption rules.
* **AAD vs. First-Sync:** Remote AAD parameters are never trusted implicitly; local reconstructed context drives authentication before any state update.

## Final Deliverable & Phase Transition Rules

Provide the following outputs in the response:

1. **Corrected Architecture Sections**
2. **Final Architecture Summary**
3. **Final Stage 1 $\rightarrow$ Stage N Implementation Sequence**
4. **Out-of-Scope Remaining Risks**

If no material contradictions remain across the design specifications, conclude the response with the explicit freezing statement:

> **ARCHITECTURE FROZEN — READY FOR STAGE 1 IMPLEMENTATION**

*Then STOP. Do NOT modify code, create commits, or execute Stage 1.*

# AUDIT

# Rocen Master-Key Architecture v5 — Final Consistency Pass

No code modified. This is the last review before implementation.

## 1. Hardware Authentication Contradiction — Resolved, Final and Consistent

You've caught a genuine inconsistency, and I want to name exactly how it happened rather than just patch over it: in the v3 draft, my "Remaining Unresolved Risks" and "Decisions Requiring Approval" sections were carried forward from the *v2* draft with only partial editing — I updated the core architecture section (then-Section 1) to make hardware-authentication mandatory, but failed to propagate that decision into the summary sections written earlier in the same response. That's a real editing failure on my part, not a deliberate hedge, and it's exactly the kind of thing this consistency pass exists to catch.

**Final, singular decision, stated once and applied everywhere below: mandatory user-authenticated hardware wrapping (`setUserAuthenticationRequired(true)`, `AUTH_BIOMETRIC_STRONG or AUTH_DEVICE_CREDENTIAL`, `timeout = 0`) is part of the core architecture, not an optional enhancement. This is final.**

Corrected throughout:

- **Unresolved risks (v4 draft, point 3):** "Hardware wrap lacks user-presence binding" is **removed as a listed risk** — it was resolved by the v4 draft's own Section 1, and its earlier persistence in a "remaining risks" list was the exact contradiction you've identified. It should never have remained listed as unresolved once Section 1 mandated the fix.
- **Decisions requiring approval (v4 draft, point 3):** "Whether to pursue biometric/user-presence-gated hardware keys as a follow-on enhancement" is **removed from the decisions list** — this was resolved, not deferred, as of the v4 draft. There is nothing left to approve on this specific point; it's already decided.
- **Implementation stages:** Stage 9 (v4 numbering) already correctly specified `setUserAuthenticationRequired(true)` and `BiometricPrompt` integration as mandatory build work, not optional — no change needed there; it was already consistent with the correct decision, which is precisely why the contradiction was confusing rather than obviously wrong throughout.
- **Security tests:** Section 18/28-31 (hardware tests) already assumed the authenticated-hardware-key design (StrongBox path, TEE path, unavailable, invalidation) — these remain correct and unchanged, but I'm adding one explicitly missing test that the mandatory-authentication decision requires and that wasn't previously listed: **a test confirming that hardware-wrap creation itself fails closed if `setUserAuthenticationRequired(true)` cannot be honored** (e.g., attempting to generate the key on a device with no lock-screen credential configured at all — Android will refuse to create a key with this flag under that condition). This must route to "hardware wrap unavailable, fall back to Password-KEK" — never to "silently create the key without the authentication requirement," which would be exactly the kind of silent-downgrade-to-weaker-security your instructions forbid throughout this whole design process.
- **Threat-model statements:** the original audit's Attacker-A analysis (an ordinary malicious app with no root) should be updated to state definitively: **"a compromised Rocen process cannot invoke the hardware-wrapped MK without a fresh, OS-mediated biometric/PIN check that app-level code cannot forge or bypass — this closes the specific gap where Attacker A gains nothing from process compromise alone with respect to the hardware-wrap path."** This is now a settled architectural property, not a hoped-for future improvement.

## 2. First-Sync Version/Key Trust — Exact Rule, Per Field

**On `keyVersion` specifically — addressing your direct question first, since it changes the shape of the rest of this answer:** you're right to ask whether it creates unnecessary complexity given key rotation isn't being built now. Evaluated honestly: **`keyVersion`'s only actual consumer in this design is a future rotation mechanism that doesn't exist yet.** Carrying it through every envelope, every AAD construction, and every first-sync trust decision **today**, for a capability with zero current call sites, is exactly the kind of complexity-for-appearance your instructions have repeatedly told me to avoid when it doesn't serve a present, concrete purpose.

**Decision: simplify `keyVersion` for the current implementation.** Concretely: the envelope's `keyVersion` byte field **remains present in the wire format** (so a future rotation doesn't require another breaking format change — this part of the original justification still holds), but **its value is hardcoded to `1` everywhere, is never read as a meaningful branch condition anywhere in the current codebase, and is excluded from AAD construction entirely until rotation is actually implemented.** This removes an entire dimension of first-sync trust complexity (there is no "which key version should I expect" question to answer at all, since there's only ever one) while preserving the wire-format compatibility Section 16 (v3 draft) correctly wanted to protect. When rotation is eventually built, that work will need to introduce the AAD-binding and trust-handling for `keyVersion` at that time, as part of that future project — not now, not speculatively.

**Final per-field table, with `keyVersion` simplified accordingly:**

| Field | Untrusted (remote claim) | Used only to select a parser/key | Allowed to influence AAD | Locally established after first successful decrypt | Downgrade handling |
|---|---|---|---|---|---|
| **formatVersion** | Yes — could claim any byte value | Yes — this is its only role; selects which decode/decrypt code path to attempt | **No** — format version is a wire-compatibility signal, not a security-identity signal; binding it into AAD would only protect against an attacker changing which *parser* runs, which is already fully covered by "the app either supports this exact value or refuses before attempting any cryptographic operation" (a version-mismatch simply never reaches the point where AAD/tag-checking matters) | The device records "I have successfully decrypted at least one envelope of formatVersion N" as a general capability fact, not per-note | An unrecognized/unsupported version → `UnsupportedEnvelopeVersionException`, full refusal, before any decrypt attempt. A recognized-but-**lower**-than-what-this-device-has-ever-produced version is **not, by itself, treated as a downgrade attack** for a first-sync note — it's simply an older, still-supported format the app can correctly read (formats don't "expire" the way generations can go stale) — **unless** a future format deprecation explicitly retires an old version, at which point that version moves into the "unsupported" category above. |
| **keyVersion** | Technically still a remote claim, but now **inert** per the simplification above | **No longer used for anything** until rotation exists — hardcoded to `1`, read only for forward-compatibility field-presence, never branched on | **No** (per the simplification decision above — explicitly excluded from AAD for now) | Nothing — there's nothing to establish when there's only one possible value | N/A until rotation exists |
| **recordType** | Yes | Yes — selects which structural parser (plain note vs. encrypted note) to apply | **Yes** — this remains authenticated, unchanged from v3/v4, because unlike formatVersion (a wire-compatibility concern) recordType is a genuine security-relevant claim about *what this data represents*, and binding it prevents a relabeling attack (Section 4, original v2 draft's worked example) | The device records the recordType it has now confirmed, authoritatively, for this specific noteId | A recordType mismatch on re-sync (a note previously confirmed as `encrypted_note` now claiming to be plain `note`) is a genuine tamper signal — this should fail the AAD/tag check outright (since the locally-established recordType, not the newly-claimed one, is what's used to construct the expected AAD on any *subsequent* sync of an already-known note), not merely a "first-sync, trust it" scenario, which only applies to a note ID the device has truly never seen before. |
| **generation** | Yes | No — this one genuinely does influence AAD, it's not merely a parser-selector | **Yes, but only as "the value used to attempt this specific decrypt," never as an authenticated claim of recency** — exactly the distinction the v4 draft already established and unchanged here | **Yes — this is the single most important "locally established after first decrypt" fact in the whole design.** The moment a first-sync decrypt succeeds, the device must immediately and durably record this generation as `lastKnownGeneration[noteId]`, so that *any future* sync of this same note — even moments later — is now subject to full rollback-detection (Section 6/12, v3 draft), no longer benefiting from "first-sync" leniency. | A "stale generation" (lower than a *locally-established* baseline) is a detected rollback attempt (unchanged from v3/v4). A first-sync generation has, by definition, no baseline to be "stale" against — this is the honest, unresolved gap already documented, restated here rather than re-litigated, since your instruction is to consistency-check, not redesign what's already correctly and honestly scoped. |
| **noteId** | Only in the narrow sense described in the v4 correction — a self-declared `noteId` field *inside* the fetched JSON body is untrusted | **The value Rocen's own sync/listing logic used to locate and fetch this file is what's actually used** — this is not "trusting a remote value," it's "trusting Rocen's own local traversal decision," a source-of-truth distinction already established in the v4 draft and unchanged here | Yes — this is the primary AAD-binding field, sourced as above | The device establishes a full local record for this `noteId` (content location, current known generation, recordType) immediately after first successful decrypt | A "downgrade" concept doesn't meaningfully apply to `noteId` itself — it either matches what Rocen's own logic expected to fetch, or the fetch/decrypt simply targets a different note entirely; there's no intermediate "old but valid" state for an identifier. |

**Restating the overriding rule once more, since this is exactly what you're asking me to hold the line on:** **no field in this table becomes trusted merely because it parsed successfully or because the app needed *some* value to attempt a first decryption.** "Successfully parsed" and "structurally well-formed" are necessary preconditions for *attempting* an operation — they are never treated as evidence of *security-relevant truth* about that value's claims, in this table or anywhere else in the design.

## 3. One-Master-Key Invariant — Hard Implementation Invariant, With the Explicit Sequencing You've Specified

Restating your required sequence as the binding, non-negotiable implementation contract — this is now a **hard invariant**, not a best-effort design goal:

```
INVARIANT: No user data may be encrypted, persisted, or synced using a
provisional/newly-generated MK until dataset initialization has
successfully, atomically completed.

Device B, first-time setup:
  1. Ownership-check (v4, Section 2): does a legitimate device_key.json
     already exist? (structural validation, not mere presence)
     → If yes: STOP. Route directly to recovery flow (Section 4-equivalent).
       No MK is generated by Device B at all in this branch.
  2. If no legitimate device_key.json exists: generate a PROVISIONAL MK.
     This MK is held ONLY in memory (Section 4/session-lifetime manager,
     v4 Section 1) and is NOT YET considered authoritative.
  3. AT THIS POINT — and this is the hard gate — the application UI MUST
     NOT expose any note-creation, note-editing, or token-storage affordance.
     The "provisional" state is not merely a naming convention; it is an
     enforced UI/application-state gate: the note-creation screen, the
     "add a note" action, and any code path that would call
     encryptWithNEK(...) must check "is MK currently AUTHORITATIVE" (a new,
     explicit boolean/enum state on the session object from Stage 5) and
     refuse — not silently queue, not silently proceed — if MK is still
     only provisional.
  4. Device B attempts the conditional/atomic publish of device_key.json
     (v4, Section 2's conditional-PUT mechanism).
  5. SUCCESS: the provisional MK is now promoted to AUTHORITATIVE. The
     session object's state transitions from `provisional` to
     `authoritative`. Only now does the note-creation UI become available.
  6. CONFLICT (another device won the race): the provisional MK and every
     KEK/wrap derived from it are immediately zeroed (SecureBytes.zero()).
     Device B fetches the now-confirmed-real device_key.json and routes to
     the recovery flow to obtain the true, authoritative MK. No data was
     ever encrypted under the discarded provisional MK, so "discarding" it
     has zero data-loss consequence by construction — this is exactly why
     step 3's gate matters: it's what makes step 6 safe.
```

**Dedicated test, exactly as required:** `test('note creation is impossible before dataset initialization succeeds')` — construct a session in the `provisional` state (mocking the conditional-publish step to never resolve, simulating an in-flight or stalled initialization), then assert that **every** note-creation/note-save/token-store code path throws a specific `DatasetNotInitializedException` (or returns an explicit "unavailable" state the UI is required to check) rather than silently succeeding, silently queuing, or — critically — silently falling through to some default/no-op behavior that a less careful implementation might produce. This test must also assert the **inverse**: once the session transitions to `authoritative` (simulating a successful conditional-publish), the identical note-creation call that previously threw now succeeds — proving the gate is a real, functioning state check, not a permanently-closed door.

## 4. Memory Lifetime / Zeroization — Precise Claim, No Overclaiming

You're right to require this precision, and I want to correct language from earlier drafts that came close to overclaiming. The exact, defensible claim:

**What this design does NOT and cannot claim:** that managed-runtime (Dart VM/ART) memory is guaranteed free of residual copies of MK, NEK, TEK, the password, or the mnemonic at any point after they've been used. This is not achievable in a garbage-collected runtime without kernel-level or hardware-level memory protection guarantees this application does not have and cannot practically obtain (Dart's GC may move, copy, or leave stale-but-unreferenced byte patterns in heap pages during normal compaction; `mlock`, even when successful, prevents swap-to-disk but says nothing about copies the runtime itself makes internally before or during a `SecureBytes` operation).

**What this design DOES claim, precisely:**

- **Minimum key lifetime:** MK/NEK/TEK are held in `SecureBytes`-wrapped form for the shortest span the design can practically achieve — from the moment of unwrap/derivation to the moment of the background/lock event (Section 1) or the completion of the specific operation needing them, whichever comes first for NEK/TEK (since they're cheap to re-derive, there is no reason to hold them any longer than the single encrypt/decrypt call that needs them, even within an unlocked session — **NEK/TEK should be derived fresh from MK for each operation or short batch of operations, not held resident for the full session duration merely because MK is available**, further minimizing their own exposure window independent of MK's).
- **Minimum number of copies:** exactly one live `SecureBytes`-wrapped copy of MK is intended to exist at any time (the session-held instance) — the design must avoid patterns that create incidental additional copies, most importantly:
  - **No unnecessary conversion to `String`.** MK/NEK/TEK must never be represented as a Dart `String` at any point — `String`s are immutable and cannot be zeroed (this is precisely why the redesign uses `Uint8List`/`SecureBytes` throughout for these values, never the password-verifier-style string-formatting pattern the *original*, pre-redesign code used for `pinHash`). Where the underlying `cryptography` package's own APIs require a `SecretKey` wrapper (as HKDF's `deriveKey` and AES-GCM's `encrypt`/`decrypt` do), that wrapping is accepted as a necessary, minimal-lifetime intermediate copy the package itself manages — not an additional *application-level* copy this design introduces gratuitously.
  - **No premature byte-array duplication.** Passing MK's bytes into HKDF, then discarding the intermediate `SecretKeyData` returned for NEK/TEK once the AES-GCM operation completes, rather than caching multiple derived-key copies "just in case" they're needed again soon.
- **Use of `SecureBytes`/best-effort zeroization:** every key-shaped value in this design (MK, Password-KEK, Recovery-KEK, NEK, TEK) is wrapped in the existing `SecureBytes`/`RamLockedBytes` primitives, with explicit `.zero()` calls at every session-end/background/lock event (Section 1) and at the natural end of any short-lived derived-key's use. This is **best-effort**, honestly labeled as such — `mlock`'s own documented, evidenced-this-session failure mode (frequently unavailable on real tested devices) means the RAM-pinning half of this protection is not universally active, but the **zeroing** half (overwriting the buffer with zero bytes before releasing it) functions independently of `mlock`'s success and is unconditionally performed.
- **Behavior on lock/background:** restated from Section 1 for completeness in this specific framing — `SecureBytes.zero()` is called synchronously on MK, and on any currently-held NEK/TEK instances, at the exact moment the app-backgrounding lifecycle event fires, before that event handler returns.

**The precise, non-overclaiming summary sentence for documentation purposes:** *"Rocen minimizes the lifetime and number of copies of key material in memory, using explicit zeroing on lock/background events and avoiding immutable string representations of secrets. This reduces, but cannot eliminate, the window during which key material could theoretically be recovered from a live memory dump of a compromised process — a residual risk inherent to managed runtimes that this design does not claim to fully close."*

## 5. Final Contradiction Scan

Checked pairwise, as requested, across every listed dimension:

- **Recovery requirements ↔ Password change:** consistent — Section 9 (v2 draft)'s mandatory mnemonic re-entry on password change is exactly what Section 1 (v2 draft)'s dual-factor requirement demands be maintained continuously, not just at initial setup. No contradiction.
- **Hardware authentication ↔ Session locking:** consistent, and now explicitly reconciled by this pass's Section 1 correction — hardware auth protects the *unwrap event*; session locking protects the *post-unwrap residency*. These are complementary, addressing different windows, not overlapping or contradicting claims. Stated correctly now in both places.
- **`_isHardened()` ↔ AAD/envelope design:** consistent — `_isHardened()`'s re-scoping (v3, Section 14) to "only gates new wrap-creation parameters" was specifically designed around, and depends on, the envelope's self-describing KDF parameters (Section 13) — the dependency ordering (Stage 10 depends on Stage 6, per v4's final ordering) correctly reflects this, no contradiction found.
- **First-sync behavior ↔ Key versioning:** this is exactly where this pass's Section 2 simplification resolves a real tension that existed in v4 — carrying full `keyVersion` trust-handling into first-sync logic for a feature (rotation) that doesn't exist yet was unnecessary complexity, now removed. No remaining contradiction.
- **One-MK invariant ↔ Failure handling:** consistent — Section 3 (this pass)'s hard gate produces a new, specific exception type (`DatasetNotInitializedException`) that fits cleanly into the existing typed-failure taxonomy (v3, Section 17) without overlapping or conflicting with any existing failure category.
- **One-MK invariant ↔ Implementation stage order:** consistent — v4's Stage 2 already scoped the conditional-publish race-handling; this pass's Section 3 makes the UI-gating requirement explicit within that same stage's scope, not a new stage, and doesn't disturb the dependency chain.
- **Session locking ↔ Memory lifetime claims:** this pass's Section 4 correction (no overclaiming perfect RAM erasure) doesn't weaken or contradict Section 1's zero-on-background *policy* — the policy (when zeroing happens) and the claim (what zeroing actually guarantees) are properly separated now, whereas earlier drafts risked conflating "we zero on lock" with an implied "and therefore nothing is ever recoverable," which this pass correctly walks back to an honest claim.
- **Recovery requirements ↔ First-sync trust model:** consistent — recovering MK onto a new device (Section 4, v2 draft) is a distinct operation from a new device's *first sync of an individual note* after MK is already available; the two "first-time" concepts (first-device-enrollment vs. first-note-sync) don't share logic or trust assumptions that could conflict, confirmed by re-reading both sections side by side for this pass.

**No remaining material contradictions found.** The `keyVersion` simplification (Section 2, this pass) and the hardware-authentication consistency fix (Section 1, this pass) were the two real issues; both are now resolved without requiring any new architectural concept beyond what v2-v4 already established.

## Final Architecture Summary

One Master Key, generated once via CSPRNG, never derived from a password, protected by three independent wrap mechanisms (Password-KEK, Recovery-KEK requiring both password and mnemonic jointly, and mandatory-user-authenticated hardware wrap), with HKDF-derived domain-separated subkeys (NEK, TEK) for actual data encryption, a self-describing v2 envelope whose AAD is always reconstructed from locally-trusted state and never from remote-supplied claims, an honestly-scoped rollback-detection mechanism that protects the already-synced case and explicitly does not claim to solve first-sync trust, a session-lifetime policy that zeros all key material on backgrounding without overclaiming perfect memory erasure, and a hard, tested invariant preventing any user data from ever being encrypted under a not-yet-authoritative provisional key.

## Final Stage 1 → Stage N Order

Unchanged from the v4 draft's eleven stages — no stage additions, removals, or reordering were required by this consistency pass, since both corrections (hardware-auth consistency, `keyVersion` simplification) fit within the scope of stages already defined (Stage 9 and Stage 6 respectively) rather than requiring new ones:

```
Stage 1  — Canonical encoding primitives
Stage 2  — Master Key generation + one-MK invariant + conditional-atomic
             publish race resolution + provisional/authoritative UI gate
             (Section 3, this pass, folded into this stage's existing scope)
Stage 3  — Password-KEK, Verifier, MK wrap/unwrap (local-only)
Stage 4  — HKDF domain separation (NEK, TEK), empty-salt construction
Stage 5  — MK session-lifetime manager (zero-on-background, precise
             non-overclaiming memory-lifetime behavior per Section 4,
             this pass)
Stage 6  — Envelope v2, AAD from trusted local state, first-sync trust
             categorization WITH keyVersion simplified/inert per Section 2,
             this pass
Stage 7  — Recovery-KEK, mandatory dual-factor recovery flow, malformed/
             untrusted-remote-file handling
Stage 8  — Password-change flow with mandatory mnemonic re-entry
Stage 9  — Hardware wrap with MANDATORY user authentication (confirmed
             final, non-optional, per Section 1, this pass), wired into
             the Stage 5 session model
Stage 10 — `_isHardened()` re-scoping and fail-closed fix
Stage 11 — Clean cutover: remove `migrateEncryptedNotes` and old direct
             encrypt/decrypt call sites; fresh-start reset, no data
             migration
```

## Remaining Risks Genuinely Outside This Design's Scope

Only two, and both were already honestly identified in prior drafts as structural limitations, not oversights this pass could resolve:

1. **First-sync rollback detection** — a device seeing a note for the first time cannot cryptographically distinguish a legitimately-old, never-updated note from a maliciously-rolled-back one. Closing this would require a separate, signed, append-only integrity mechanism independent of the mutable GitHub store itself — explicitly out of scope, as previously stated.
2. **Deletion-state integrity** — GitHub, as a mutable, attacker-writable store, cannot attest that a deletion "should stay deleted." Same class of limitation as above, requiring the same kind of separate trusted-log mechanism to close.

Neither is resolvable by anything in the #4/hardware-authentication decision or by any further tightening of this specific design's scope — both require genuinely new infrastructure (a trusted, append-only attestation mechanism) that is a separate project from "fix the master-key architecture."

**ARCHITECTURE FROZEN — READY FOR STAGE 1 IMPLEMENTATION**

# PROMPT

**Do NOT implement Stage 1 yet.**

The v4 architecture is now very close to final. Perform ONE final consistency pass only.

Resolve these specific points:

### 1. Hardware Authentication Contradiction

Section 1 says user-authenticated hardware wrapping is part of the core maximum-security architecture.

However, the later "Remaining Unresolved Risks" / "Decisions Requiring Approval" sections still say hardware user authentication is not included in this pass and may be a future enhancement.

This is contradictory.

For Rocen's maximum-security goal, make the final decision explicit and consistent throughout the document.

If mandatory user-authenticated hardware wrapping remains part of #4, update:

* Unresolved risks
* Decisions list
* Implementation stages
* Security tests
* Threat-model statements

so there is no remaining contradiction.

### 2. First-Sync Version / Key Trust

Define the exact rule for a brand-new device that has no local record yet.

For:

* `formatVersion`
* `keyVersion`
* `recordType`
* `generation`
* `noteId`

State exactly:

* What is untrusted
* What is used only to select a parser
* What is allowed to influence AAD
* What is locally established after the first successful decrypt
* How supported-version downgrade attempts are handled

Do not silently treat a GitHub-provided value as trusted simply because it successfully parses.

Because key rotation is NOT being implemented now, evaluate whether `keyVersion` creates unnecessary first-sync complexity and whether it should be simplified until rotation actually exists.

### 3. One-Master-Key Invariant

Make this a hard implementation invariant:

**NO user data may be encrypted, persisted, or synced using a provisional/newly-generated MK until dataset initialization has successfully completed and ownership/initialization has been atomically established.**

In particular, explicitly cover:

Device B generates provisional MK
$\rightarrow$ Before any note can be created
$\rightarrow$ Initialization attempt
$\rightarrow$ **Success:** MK becomes authoritative
$\rightarrow$ **Conflict:** Provisional MK is securely discarded
$\rightarrow$ Recover existing authoritative MK

Add a dedicated test for: *"Note creation is impossible before initialization succeeds."*

### 4. Memory Lifetime / Zeroization

Keep the strongest session policy:

* MK cleared on background/lock
* NEK/TEK cleared with MK
* Re-unlock required after returning

State the memory-security claim precisely: do **NOT** claim that managed-runtime memory can be guaranteed to contain no residual copies.

Instead, define:

* Minimum key lifetime
* Minimum number of copies
* Use of `SecureBytes` / best-effort zeroization
* Avoidance of unnecessary conversions to immutable `String`s or byte arrays
* Behavior on lock/background

The design should minimize exposure without making an unverifiable claim of perfect RAM erasure.

### 5. Final Contradiction Scan

Re-read the entire v4 design and check specifically for contradictions between:

* Recovery requirements
* Password change
* Hardware authentication
* Session locking
* `_isHardened()`
* AAD
* First-sync behavior
* Key versioning
* One-MK invariant
* Failure handling
* Implementation stage order

Do not introduce new architecture unless required to resolve an actual contradiction.

### Deliverables Required

This is the **FINAL DESIGN REVIEW**.

* **Do NOT modify code.**
* **Do NOT create commits.**
* **Do NOT implement Stage 1.**

Return only:

1. Corrected sections
2. Final architecture summary
3. Final Stage 1 $\rightarrow$ Stage N order
4. Remaining risks that are genuinely outside #4

If there are no material contradictions remaining, explicitly state:

> **"ARCHITECTURE FROZEN — READY FOR STAGE 1 IMPLEMENTATION"**

Then **STOP**.

# AUDIT

## Rocen Master-Key Architecture v6 — Final Four-Point Check

No code modified. Scoped strictly to the four points requested.


## 1. Format Version Authentication — Real Risk Once Multiple Formats Coexist

**Re-examining my own prior reasoning rather than defending it:** in v5 I concluded `formatVersion` didn't need AAD-binding because "a version mismatch simply never reaches the point where tag-checking matters." That reasoning holds **only as long as exactly one format version is ever in active use at a time** — which is true today (only v2 exists) but stops being true the moment a future v3 ships alongside still-valid v2 data. I need to re-examine specifically for that future condition, since freezing this architecture now means the AAD decision has to be right for the multi-version world it's explicitly designed to eventually support (Section 16, key rotation capability — the same forward-looking principle applies here).

**The concrete risk, once v2 and v3 coexist:** if `formatVersion` is read and used *only* to select a parser, with no cryptographic binding, an attacker with GitHub write access could take a genuinely valid v3 envelope (ciphertext, tag, everything correct for v3) and **relabel its `formatVersion` byte to claim v2**, then supply it to a device. If v2's parser is more lenient in any way v3 tightened (a different AAD construction, a different set of authenticated fields, a weaker algorithm identifier that v3 deprecated for a reason), the device would attempt v2-style decryption against genuinely-v3-produced ciphertext. Whether this *succeeds* depends on the specific differences between the two formats' AAD/key derivation — but the structural risk is real and general: **an unauthenticated format identifier is a downgrade vector by definition, the same class of problem TLS version downgrade attacks exploit**, and I should not have dismissed it as fully closed based only on today's single-format state.

**Recommendation, correcting the prior conclusion: `formatVersion` (and `algorithmId`) must be included in AAD, not excluded.** This is a small, low-cost change — one more field concatenated into the already-necessary AAD construction (Section 5/11 of prior drafts) — and it converts "format selection" from a purely-advisory hint into a claim that must match what the ciphertext was actually authenticated under. Concretely: if an attacker relabels a v3 envelope's `formatVersion` to `2`, the AAD the decrypting device constructs (correctly including `formatVersion=2`, since that's what it read) will not match the AAD the ciphertext was actually produced under (`formatVersion=3`), and the GCM tag check fails — the relabeling is caught by the exact same mechanism that already catches note-ID substitution, with no new mechanism needed.

**Why this doesn't reintroduce the "trust remote-supplied metadata" problem Section 4/6 forbid:** the field is still *read from the untrusted envelope* to decide which parser to even attempt (that role is unchanged and correct) — but its value is *also* fed into AAD reconstruction, meaning a mismatch between "what this byte claims" and "what the ciphertext was actually authenticated under" is caught cryptographically, not trusted at face value. This is the same pattern already correctly applied to `recordType` and `generation` in prior drafts — `formatVersion` was the one field I'd inconsistently carved out an exception for, and that inconsistency is what created the risk.

**Corrected envelope field table entry:** `formatVersion` moves from "Authenticated? No" to "Authenticated? Yes" in the Section 13 (v2 draft) table. `algorithmId` should be authenticated for the identical reason (an attacker relabeling which algorithm was claimed, once more than one is ever supported, is the same downgrade shape).

## 2. First-Sync Record Type — Trusted Source, Explicitly Defined

You're right that I applied the "don't trust self-declared identity" principle to `noteId` but left `recordType`'s first-sync trust source implicit rather than explicit. Fixing that gap precisely:

**The trusted source of `recordType` during first sync must be the same category of source as `noteId`: Rocen's own sync/listing logic's *a priori knowledge of what it expected to find at that location*, never a field read from inside the fetched payload.**

Concretely, this requires the sync/listing mechanism itself to carry type information **before** fetching content — e.g., if Rocen's GitHub layout separates encrypted-note files from plain-note files by directory or filename convention (or, if it doesn't today, this becomes a required design element: the file listing/manifest step must declare "this path is an encrypted_note" as part of *locating* the file, not as part of *decrypting* it). The decrypting device then constructs AAD using **the type it expected to fetch, based on its own traversal decision**, and if the fetched content fails to decrypt/authenticate under that expected type, this is a detected mismatch — never a case where the device asks "well, what type does this file's own JSON body claim to be" and trusts that answer.

**Why this closes the specific attack you're describing:** if an attacker takes a valid `encrypted_note` ciphertext and its accompanying metadata, and attempts to present it at a path/location Rocen's traversal logic associates with plain, unencrypted `note` records (or vice versa) — **while also editing the embedded metadata to claim a matching, consistent `recordType`** — this still fails, because the decrypting device never consults that embedded claim for AAD construction at all. It only ever uses **what it expected to find at that specific location, per its own prior traversal/listing decision.** An attacker can make the *content* internally consistent with a relabeled type, but cannot make Rocen's own *local, pre-fetch expectation* agree with the relabel, since that expectation was formed before the attacker-controlled content was ever read.

**This is not a new mechanism — it is the direct, correct application of the `noteId` principle already established, extended to `recordType`, closing exactly the gap you've identified without introducing any new architectural concept.**

## 3. Password-Change / Old Recovery-Wrapper Replay — Analyzed Precisely, No False Claims

Working through your exact numbered scenario:

**Steps 1-7 as given. Question: can the restored P1 wrapper recover the same MK?**

**Yes.** I need to state this plainly rather than hedge: **the old P1-derived Recovery-KEK wrapper, if restored by an attacker with GitHub write access, still correctly unwraps to the identical MK it always did — because MK itself never changes on a password change (this is the entire, deliberate point of the master-key architecture, per Section 2's non-negotiable requirement).** If the attacker genuinely knows P1 and the mnemonic (your stated preconditions), and can restore the P1-wrapped blob to the location Rocen's recovery flow reads from, **Recovery-KEK derivation from P1+mnemonic succeeds exactly as it did before the password change, and unwraps the same MK that is still, today, protecting the user's actual data.**

**What security guarantee is, and is not, possible here — stated without overclaiming:**

- **NOT possible, under the current GitHub-mutable-store threat model:** "changing the password invalidates every historical remote snapshot of the recovery wrapper." This would require either (a) MK itself changing on every password change — which directly contradicts your own Section 2 requirement and would reintroduce the exact re-encrypt-everything cost this whole architecture exists to eliminate — or (b) a trusted, tamper-proof remote mechanism that can definitively and permanently invalidate an old wrapper's *usability*, independent of whether an attacker can restore its *bytes*. Neither exists in this design, and I want to be explicit: **I cannot claim password-change achieves this, because it doesn't, and claiming otherwise would be exactly the false security assurance your instruction warns against.**
- **IS possible, and already provided:** the *current, live* `password_state.json`/`device_key.json` correctly reflects the P2 wrapper as of the moment of the legitimate change — an attacker who does **not** already possess a previously-captured P1 wrapper (i.e., didn't have GitHub write/read access *before* the password change occurred) gains nothing from the password change having happened, since they never had the old artifact to restore in the first place. The protection this design *does* provide is against an attacker who **only** compromises the repository **after** the password change — for that attacker, the P1 wrapper simply isn't there to find. The scenario you've constructed specifically assumes the attacker **already had a valid, previously-captured P1 wrapper before the change** — and against *that specific* attacker, this design provides no additional protection beyond what already existed before the password change was ever made.

**Is this the same structural limitation as first-sync rollback? Yes — precisely, and worth stating exactly why:** both are instances of the same underlying, already-honestly-documented structural gap: **GitHub, as a mutable store an in-scope attacker (Attacker D) can write to, cannot itself attest to "this artifact is retired/superseded and should never be accepted again."** First-sync rollback is "an attacker restores an old *note* generation and a device with no prior baseline cannot tell it's stale." This scenario is "an attacker restores an old *recovery wrapper* and the recovery flow — which is, by necessity, exactly the kind of first-contact operation a genuinely-new device performs — has no prior baseline to compare the restored wrapper's provenance against either." **These are the same root cause, not two separate problems requiring two separate closing mechanisms:** any solution that closes one (a signed, append-only, remotely-unspoofable attestation of "current, valid state") would close the other too, and the converse is equally true — neither can be closed independently within the current GitHub-only trust model.

**Strongest practical protection available without redesigning the trust model:** the same local-highest-generation tracking mechanism (Section 12, v3/v4/v5 drafts), applied to the recovery-wrapper's own implicit "generation" — specifically, **a device that has previously completed a password change should locally remember that it did so, and should treat a subsequent recovery attempt that succeeds using an *older* wrapper than the one it last knew about as suspicious**, surfaced explicitly (e.g., "this recovery used older credentials than expected — verify this is intentional") rather than silently accepted. This provides the identical, already-honestly-scoped protection class as generation-rollback detection: **strong for a device with continuous local memory of the legitimate history; structurally unable to help a genuinely first-time recovery, which by definition has no such memory to compare against.** I am not proposing a new mechanism here — I am applying the *existing* local-baseline-tracking principle to one more artifact type it already generalizes to, which resolves this as a restatement of an already-scoped limitation, not a new architectural gap requiring new design work.

## 4. Memory-Lifetime Wording — Corrected to a Defensible Implementation Requirement

You're right to push back on "zeroed synchronously before the lifecycle callback returns" — that phrasing implies a stronger, more deterministic guarantee than Flutter's actual app-lifecycle model can provide. Let me be precise about what Flutter/Android actually guarantees here, rather than assume.

**The honest limitation in the prior wording:** Flutter's `AppLifecycleState` transitions (`paused`, `inactive`, `detached`) are delivered via the `WidgetsBindingObserver` callback mechanism, which is **asynchronous relative to the actual OS-level backgrounding event** — there is no guarantee that Dart code executing inside that callback completes before the OS considers the app fully backgrounded, and critically, **there is no guarantee the callback fires at all before the process is killed** in a low-memory or aggressive-OS-scheduling scenario (some Android OEM skins are known to kill backgrounded processes without reliably delivering all expected lifecycle callbacks first). Claiming zeroing happens "before the lifecycle callback returns" implies a completion guarantee the platform doesn't actually provide.

**Corrected, defensible requirement:** *"MK and all currently-held derived key material (NEK, TEK, any active KEK) must be zeroed as the first action taken inside the `didChangeAppLifecycleState` handler upon receiving `AppLifecycleState.paused` or `AppLifecycleState.inactive` — this is the earliest reliable lifecycle signal Flutter exposes for 'the app is leaving the foreground.' This is a best-effort, prompt-as-possible response to the earliest available signal, not a guarantee that zeroing completes before the OS has fully backgrounded the app or before any possible process termination, since Flutter/Android provide no such completion guarantee to application code."*

This changes the claim from "guaranteed synchronous completion relative to an OS event" to "correctly wired to fire at the earliest point the framework tells the app anything is happening, done first, done promptly, with no artificial delay introduced by the app itself" — which is the actual, honest, and fully verifiable requirement an implementation can be held to and tested against (a test can assert "the zero call happens as the first statement in the handler," which is a real, checkable property; a test cannot meaningfully assert "this completed before the OS finished backgrounding the process," since that's not an observable boundary from within the app at all).

**Everything else in the Section 1 (v4 draft) memory policy remains correctly stated and requires no further softening:** "clear MK on background/lock," "clear derived key material," "require re-unlock after returning," "minimize copies," "best-effort zeroization" are all policy statements about *what the app does*, not claims about *what the underlying runtime guarantees* — the only phrase that overstepped into an unverifiable platform guarantee was the "synchronously before the callback returns" wording, now corrected above.

## Contradiction Re-Check, Scoped to These Four Points Only

- **Format-version authentication ↔ `_isHardened()`/envelope design:** no contradiction — adding `formatVersion` to AAD is purely additive to the existing envelope construction (Section 13, v2 draft) and doesn't alter `_isHardened()`'s already-correctly-narrowed scope (v3, Section 14) at all, since that scope was about KDF-parameter interpretation, not format-version authentication.
- **First-sync `recordType` trust source ↔ first-sync `noteId` trust source:** now fully consistent — both derive from Rocen's own pre-fetch traversal/listing knowledge, stated identically in principle, no divergence remains.
- **Recovery-wrapper replay ↔ password-change flow (Section 9, v2 draft):** no contradiction — Section 9's mandatory mnemonic re-entry on password change remains exactly as valuable as previously stated (it correctly updates the *live, current* recovery state and closes the "old password still works going forward" gap for any attacker who *doesn't* already possess a pre-change wrapper); this point 3 analysis only clarifies what that mechanism does **not** additionally provide (retroactive invalidation of already-exfiltrated old artifacts), which is a scope clarification, not a contradiction of Section 9's actual, more limited, correctly-stated claim.
- **Memory-lifetime wording ↔ session-lifetime manager stage (Stage 5) ↔ hardware-authentication stage (Stage 9):** no contradiction — Stage 9's hardware-auth design already correctly stated that hardware authentication protects only the unwrap event, with Stage 5's session policy handling everything after; this point 4's wording correction doesn't change *when* zeroing happens (still on the earliest backgrounding signal) or *what* gets zeroed (still MK + all derived material) — only the precision of what completion guarantee is claimed, which doesn't ripple into either stage's actual design or dependency ordering.

**No new speculative architecture was introduced.** Point 1's fix reuses the existing AAD mechanism with two additional fields. Point 2's fix is a direct extension of an already-established principle to one more field. Point 3's analysis concludes with an honest limitation restated using the *already-existing* local-baseline-tracking mechanism, not a new one. Point 4 is a wording correction with no architectural change at all.

**No material contradictions remain.**

**ARCHITECTURE FROZEN — READY FOR STAGE 1 IMPLEMENTATION**

## Final Stage 1 → Stage N Order

Unchanged from v5 — none of this pass's four corrections altered stage scope, dependencies, or count:

```
Stage 1  — Canonical encoding primitives
Stage 2  — Master Key generation + one-MK invariant + conditional-atomic
             publish race resolution + provisional/authoritative UI gate
Stage 3  — Password-KEK, Verifier, MK wrap/unwrap (local-only)
Stage 4  — HKDF domain separation (NEK, TEK), empty-salt construction
Stage 5  — MK session-lifetime manager (earliest-reliable-lifecycle-event
             zeroing, per corrected wording, this pass)
Stage 6  — Envelope v2, AAD from trusted local state, first-sync trust
             categorization, keyVersion inert/simplified, formatVersion
             and algorithmId now included in AAD (per this pass, point 1),
             recordType's first-sync trust source from traversal logic
             (per this pass, point 2)
Stage 7  — Recovery-KEK, mandatory dual-factor recovery flow, malformed/
             untrusted-remote-file handling, local recovery-wrapper
             generation/history tracking for replay-detection (per this
             pass, point 3)
Stage 8  — Password-change flow with mandatory mnemonic re-entry
Stage 9  — Hardware wrap with mandatory user authentication, wired into
             the Stage 5 session model
Stage 10 — `_isHardened()` re-scoping and fail-closed fix
Stage 11 — Clean cutover: remove `migrateEncryptedNotes` and old direct
             encrypt/decrypt call sites; fresh-start reset, no data
             migration
```

#### THE FIXING IS STARTED -- NEXT FIXING AUDIT COMING SOON.