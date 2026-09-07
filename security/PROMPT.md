# Rocen — Deep Security Audit, Threat Analysis & Hardening Review

_I’ve completed the UI/UX enhancements, but our next priority is a comprehensive source code audit. Once the scan is finished, I will share the findings from our AI security analysis and systematically resolve every vulnerability and bug identified. Please do not download older builds in the meantime, as this upcoming release will comprehensively address all flagged issues._

You are performing a **defensive security review** of the Rocen Flutter/Dart + Android application.

Your job is NOT to praise the project and NOT to assume that the existing README, CHANGELOG, comments, or developer claims are correct.
Treat the **actual source code and build configuration as the source of truth**.
Do not modify the code during this audit unless explicitly asked later.

Your review must distinguish between:

* actual security vulnerabilities
* privacy weaknesses
* integrity/data-loss weaknesses
* availability/reliability problems
* hardening opportunities
* normal engineering behavior that is NOT a security issue
* false positives caused by misunderstanding the code

Do not call something a vulnerability without showing the concrete code path and a realistic attack scenario.



# 1. First: Build the actual security model

Before finding bugs, explain what Rocen is actually trying to protect.

Identify:

* what data exists
* where plaintext exists
* where ciphertext exists
* where passwords exist
* where derived keys exist
* where recovery words exist
* where GitHub tokens exist
* where device keys exist
* where metadata exists
* what is stored locally
* what is stored on GitHub
* what is sent over the network
* what survives app restarts
* what survives device loss
* what can be recovered after backup restore

Create a simple trust-boundary diagram:

Device UI
→ application logic
→ local storage
→ crypto layer
→ Android Keystore/StrongBox/TEE
→ GitHub API
→ GitHub repository

Identify every place where the security boundary changes.

 

# 2. Threat model

Explicitly evaluate protection against:

### Attacker A — ordinary malicious app

A different non-root Android application attempts to access Rocen's files, logs, clipboard, intents, screenshots, etc.

### Attacker B — filesystem/app-data extraction

An attacker obtains a copy of Rocen's local application data.

Determine exactly what that attacker receives and whether that data is sufficient to recover:

* notes
* titles
* passwords
* encryption keys
* GitHub tokens
* recovery material

### Attacker C — rooted/compromised device

Assume the attacker can inspect application memory/storage and interact with the OS at a privileged level.

Identify what Rocen can realistically protect and what it cannot.

### Attacker D — malicious/compromised GitHub account

Assume an attacker can modify the backup repository or obtain the GitHub token.

Determine whether they can:

* read notes
* replace encrypted notes
* delete notes
* roll back notes
* inject malicious backup records
* cause corruption
* cause a downgrade/restore attack

### Attacker E — network attacker

Assume someone can intercept, manipulate, delay, replay, or redirect traffic.

Check:

* TLS validation
* certificate/public-key pinning
* host allowlisting
* redirects
* DNS-related assumptions
* proxy behavior
* alternate endpoints
* whether authentication tokens can ever leave the intended host

### Attacker F — malicious GitHub repository contents

Assume the repository is writable by an attacker.

Check whether malicious filenames, JSON, metadata, oversized files, unexpected fields, invalid ciphertext, or malicious content can crash the app, bypass validation, overwrite local state, or cause arbitrary behavior.

### Attacker G — malicious update/release

Check whether users can reliably verify that an APK came from the legitimate developer and corresponds to the published source.


# 3. CRYPTOGRAPHY AUDIT — highest priority

Perform a detailed cryptographic review.

Trace every value from:

password
→ normalization
→ salt
→ KDF
→ derived key
→ key wrapping
→ storage
→ encryption/decryption

Do NOT merely say “Argon2id + AES-GCM is secure.”

Review the actual implementation.

## Specifically investigate:

### A. Password verifier vs encryption key

Determine whether any password-derived verifier/hash is also reused as:

* an encryption key
* a wrapping key
* a MAC key
* another long-term secret

If yes:

1. Explain exactly why this is or is not dangerous.
2. Identify what happens if local application storage is extracted.
3. Determine whether an attacker can bypass the original password because a password-equivalent is stored.
4. Recommend a clean separation between:

   * password verification material
   * password-derived KEK
   * random data-encryption/master key

Prefer a design where:

random master key
→ encrypts notes

password-derived KEK
→ wraps master key

password verifier
→ used only for authentication/verification

Do not recommend simply “hash the hash again” without explaining the actual key hierarchy.

### B. Master key architecture

Determine whether Rocen has a true random master/data-encryption key.

If not, explain the security consequences and recommend a key hierarchy.

Evaluate:

* key generation randomness
* key length
* key storage
* hardware wrapping
* password wrapping
* recovery wrapping
* password change behavior
* device migration
* backup restoration
* key rotation

### C. KDF parameters

Check whether encrypted data records contain all parameters required to decrypt themselves.

Verify whether the following are preserved with the ciphertext:

* KDF algorithm
* memory cost
* iteration count
* parallelism
* salt
* format/version

Do NOT allow decryption to depend on the current device's KDF setting unless the encrypted payload explicitly records the parameters used to create it.

Test conceptually:

standard device → hardened device
hardened device → standard device
old version → new version
new version → old version where supported

Identify compatibility and downgrade issues.

### D. AES-GCM

Verify:

* key size
* nonce size
* nonce uniqueness
* randomness source
* authentication tag handling
* ciphertext integrity checks
* failure behavior
* whether nonce reuse is possible
* whether plaintext is returned before authentication succeeds
* whether attacker-controlled associated data is authenticated
* whether titles/metadata can be modified independently of ciphertext

Check for accidental nonce reuse across:

* notes
* device keys
* password state
* recovery data
* retries
* repeated encryption
* sync operations

### E. Key separation

Ensure keys are not reused between unrelated purposes.

Look for separation between:

* note encryption
* device key
* authentication
* GitHub credential protection
* recovery
* integrity/MAC operations

If one key is reused for multiple purposes, classify it as:

RED = dangerous
YELLOW = questionable
GREEN = safe/intentional

and explain why.

### F. Password changes

Trace the complete password-change process.

Determine whether changing the password:

* re-encrypts all notes unnecessarily
* rewraps only a master key
* changes salts
* changes KDF parameters
* leaves old key material accessible
* leaves stale temporary files
* leaves stale backups
* creates a rollback path
* can be interrupted safely
* can leave local and GitHub state inconsistent

A password change should ideally change the wrapping of the master key rather than forcing unnecessary full-data re-encryption.

### G. Recovery phrase

Audit:

* generation randomness
* entropy
* word count
* checksum
* storage
* display
* screenshots
* clipboard
* logging
* memory lifetime
* GitHub upload
* recovery process
* brute-force implications
* whether the phrase is treated like a secret

Never log or persist the actual recovery words unless strictly required.

Check whether recovery bypasses any security boundary.

# 4. LOCAL STORAGE AUDIT

Inspect all local persistence:

* Hive
* SharedPreferences
* files
* cache
* temporary files
* SQLite if present
* Android preferences
* Keystore
* app documents
* external/public storage

For EVERY persisted security-sensitive value, report:

Value
→ location
→ plaintext or encrypted
→ protection mechanism
→ why it is stored
→ attacker impact if extracted

Pay particular attention to:

* `system_crypto_pin`
* passwords
* password hashes/verifiers
* recovery information
* GitHub tokens
* device keys
* note titles
* note contents
* filenames
* sync state
* repository names
* branch information

Determine whether sensitive Hive boxes themselves are encrypted.

If a value is stored in plaintext locally, determine whether the Android app sandbox is the only protection.

# 5. MEMORY & SECRET LIFETIME

Review how secrets are handled in RAM.

Check:

* password strings
* recovery phrases
* GitHub tokens
* encryption keys
* decrypted note contents
* Uint8List / byte arrays
* String conversions
* temporary copies
* isolates
* exception messages
* JSON serialization

Determine whether secret bytes are:

* zeroed when possible
* copied unnecessarily
* converted from bytes to immutable Strings
* retained longer than necessary

Do NOT claim that zeroing memory provides absolute security.

Explain exactly what it protects against and what it does not.

 

# 6. GITHUB TOKEN SECURITY

Trace the token from user entry to:

storage
→ retrieval
→ request construction
→ HTTP client
→ GitHub

Verify:

* minimum required GitHub permissions
* token scope
* whether fine-grained PAT is supported
* whether only one dedicated repository is needed
* whether `/user` or other unnecessary endpoints are contacted
* whether token appears in logs
* whether token appears in exceptions
* whether token appears in URLs
* whether token is ever sent to a non-GitHub host
* whether redirects can leak the token
* whether proxy behavior can leak the token
* whether the token is cached in memory
* whether token deletion actually removes it

Recommend the minimum possible GitHub permissions.

Prefer:

dedicated repository
+
minimum repository permissions
+
no unrelated GitHub API access

# 7. NETWORK SECURITY

Audit every network request in the entire repository.

Do not assume the developer's stated “GitHub only” policy is correct.

Search for:

* `http://`
* `https://`
* `Uri`
* `url_launcher`
* WebViews
* package download/update checks
* analytics
* crash reporting
* telemetry
* remote configuration
* third-party API URLs
* redirects
* hard-coded domains
* dynamically constructed hosts

Create a table:

Host
Purpose
HTTP method
Authentication
Data sent
Data received
Can redirect?
Certificate pinning?
Allowed by host policy?

Verify that GitHub API requests cannot redirect credentials to another host.

# 8. CERTIFICATE / PUBLIC-KEY PINNING

Audit pinning carefully.

Check:

* what exactly is pinned
* certificate vs SPKI/public key
* primary pin
* backup pin
* key rotation process
* expiration behavior
* fail-open vs fail-closed
* behavior when pinning initialization fails
* behavior when pin is outdated
* whether a malicious proxy can become usable
* whether pinning is actually applied to every GitHub request
* whether any code path bypasses the pinned HTTP client

Document whether the code and README/CHANGELOG agree.

Do not assume certificate pinning automatically improves security.

Determine whether it introduces:

* availability risks
* stale-pin risks
* false confidence
* bypassable alternate clients

# 9. REMOTE BACKUP SECURITY

Determine exactly what goes to GitHub.

For each backup object, identify:

* plaintext fields
* encrypted fields
* filenames
* note IDs
* titles
* timestamps
* metadata
* encryption version
* KDF parameters
* salts
* nonces
* authentication tags

Determine whether an attacker with read-only GitHub access can learn:

* note titles
* number of notes
* note creation/update timing
* note size
* repository structure
* device identity
* usernames
* internal state

Recommend minimizing metadata leakage.

Strongly consider:

Every remote note is encrypted
+
opaque/random remote filename
+
encrypted title/body
+
self-describing encryption envelope

Do not rely on “locked note” as the sole condition for remote encryption if the product claims encrypted backup.

# 10. SYNC / CONFLICT SECURITY

Audit multi-device synchronization.

Look for:

* forced branch updates
* race conditions
* stale branch refs
* time-of-check/time-of-use problems
* overwrite behavior
* deletion propagation
* replay
* rollback
* duplicate notes
* conflicting encrypted versions
* malicious remote state

Determine whether synchronization can:

* silently destroy local edits
* silently destroy remote edits
* roll back to older note versions
* delete a note unexpectedly
* overwrite `device_key.json`
* overwrite `password_state.json`
* treat internal security files as normal notes

Prefer conditional updates and explicit conflict resolution.

Do not use force-push/force-update behavior for ordinary sync unless there is a strong, documented reason.



# 11. REPLAY / ROLLBACK ATTACKS

This is especially important for encrypted backups.

Ask:

If an attacker has write access to the GitHub repository, can they replace a newer encrypted note with an older valid encrypted note?

AES-GCM authenticity does NOT by itself prevent replay of a previously valid ciphertext.

Determine whether Rocen needs:

* monotonically increasing versions
* authenticated revision numbers
* timestamps
* per-record version counters
* repository state binding
* anti-rollback checks

Be careful not to claim a timestamp alone prevents replay.

 

# 12. INPUT VALIDATION

Treat GitHub repository data as untrusted attacker-controlled input.

Audit:

* JSON parsing
* filenames
* note IDs
* repository paths
* owner names
* branch names
* timestamps
* size limits
* malformed ciphertext
* oversized payloads
* duplicate IDs
* duplicate filenames
* missing fields
* unknown fields
* unexpected Unicode
* path traversal
* null bytes
* resource exhaustion

The app must fail safely on malformed remote data.

Do not allow malicious backup data to become executable behavior.

 

# 13. LOGGING & DIAGNOSTICS

Search the entire repository for:

* `print`
* `debugPrint`
* logger calls
* stack traces
* exception output
* HTTP request/response logging
* JSON logging

Confirm that production logs never contain:

* passwords
* recovery words
* GitHub tokens
* plaintext notes
* decrypted note contents
* encryption keys
* full sensitive exception payloads

Also check indirect leaks such as:

repository name
note title
filename
query parameters
authorization headers

Do not assume `debugPrint()` means debug-only.

 

# 14. CLIPBOARD / SCREENSHOT / UI LEAKAGE

Inspect:

* clipboard
* copy buttons
* recovery phrase display
* password fields
* note editor
* Android screenshots
* recent-apps preview
* screen recording
* notifications
* share sheets
* external intents

Consider whether sensitive information should use:

* `FLAG_SECURE`
* clipboard auto-clear
* password obscuring
* secure text entry
* no sensitive notifications
* no sensitive recent-app previews

Do not blindly enable every mitigation.

Explain the user-experience tradeoff.

 

# 15. ANDROID SECURITY

Audit native Android configuration.

Check:

* signing configuration
* release signing
* debug signing
* debuggable state
* min SDK
* target SDK
* exported activities
* exported services
* exported receivers
* content providers
* intent filters
* backup configuration
* Android Auto Backup
* device transfer
* cleartext traffic
* network security config
* Keystore
* StrongBox
* hardware-backed keys
* biometric configuration
* screenshot protection
* external storage access
* permissions

Especially verify whether Android's automatic backup could copy sensitive Rocen local files to another location.

This is a HIGH-PRIORITY check.

 

# 16. ANDROID BACKUP / RESTORE

Determine whether Android Auto Backup or device migration can capture:

* Hive databases
* local keys
* token storage
* preferences
* recovery metadata
* temporary files

If encrypted app state can be restored onto an attacker-controlled or unauthorized device, determine the implications.

Recommend appropriate Android backup rules when necessary.

 

# 17. DEPENDENCY AUDIT

Inspect `pubspec.yaml`, lockfiles, Android dependencies, plugins, FFI libraries, and native libraries.

For each security-sensitive dependency identify:

Package
Version
Purpose
Security impact
Known concerns
Whether it handles secrets/network/storage/crypto

Pay special attention to:

* cryptography
* FFI
* smart_dev_pinning_plugin
* HTTP
* Hive
* Android security plugins
* media/file plugins

Do not claim a package is vulnerable merely because it is third-party.

Distinguish:

trusted/standard dependency
from
security-critical dependency that needs extra review.

 

# 18. RELEASE / SUPPLY-CHAIN SECURITY

Audit how the application is built and distributed.

Verify:

* production signing key
* debug vs release build
* minification
* obfuscation where appropriate
* reproducibility
* Git tags
* release commits
* APK hashes
* signing certificate fingerprints
* CI/CD
* build scripts
* GitHub Actions
* secret handling in CI
* artifact provenance

Recommend that every public release provide:

* version
* exact git commit/tag
* APK SHA-256
* signing certificate fingerprint
* reproducible/verifiable build information where practical

Do NOT treat Play Protect/OS malware scanning as proof of developer authenticity.

 

# 19. DOWNGRADE / MIGRATION SECURITY

Check whether an attacker can cause users to install or reopen older, weaker crypto formats.

Audit:

* encryption version numbers
* migration code
* old cipher compatibility
* old XOR formats
* older password schemes
* downgrade paths
* old backups
* version negotiation

If a legacy format was insecure, determine whether the app should:

* migrate it
* refuse it
* mark it legacy
* require explicit conversion

Never silently downgrade a user's cryptographic protection.

 

# 20. ERROR HANDLING

Security-sensitive failures should generally fail closed.

Search for:

* `catch` blocks
* fallback return values
* `return true`
* `return false`
* ignored exceptions
* fallback plaintext behavior
* bypassed authentication
* fallback to weaker crypto
* fallback to unpinned network connections

For every fallback, ask:

“What security property is lost if this path executes?”

Pay special attention to:

root detection
hardware security
certificate pinning
authentication
decryption
integrity verification

A failure to determine that something is safe should not automatically become “safe.”

 

# 21. DIFFERENTIATE SECURITY FROM NORMAL FAILURES

For every finding, explicitly label it:

### RED — Release blocker

A realistic attack can compromise confidentiality, integrity, authentication, keys, or secret material.

### ORANGE — Serious security weakness

Not an immediate exploit, but meaningfully weakens a stated security property.

### YELLOW — Hardening / privacy / integrity concern

Worth fixing, but not a direct compromise.

### BLUE — Reliability / UX / maintainability

Useful improvement, but not a security flaw.

### GREEN — Not a problem

Initially suspicious-looking behavior that is actually reasonable once the full data flow is understood.

Do NOT inflate findings.

 

# 22. Evidence requirement

For every RED/ORANGE/YELLOW finding, provide:

1. Finding title
2. Severity
3. Exact file
4. Exact function/class
5. Relevant code behavior
6. Data flow
7. Attacker assumptions
8. Attack scenario
9. Security property affected
10. Why existing protection is insufficient
11. Recommended fix
12. Whether the fix is backward compatible
13. How to test the fix
14. Whether the issue is already fixed in another branch/version

Never say:

“Could be vulnerable.”

Instead say either:

“Confirmed security weakness because…”
or
“Not confirmed; requires additional evidence because…”

 

# 23. Compare implementation vs documentation

Cross-check:

* README
* CHANGELOG
* MULTI-DEVICE documentation
* comments
* release notes
* source code
* Android configuration

Create a section:

## Documentation / Implementation mismatches

For every mismatch state:

Document says:
Code actually does:
Security impact:
Priority:

Do not assume either side is correct.

 

# 24. SECURITY IMPROVEMENT REQUESTS

After completing the vulnerability audit, create a SECOND section called:

# Recommended Security Enhancements

These are not necessarily vulnerabilities.

Suggest additional improvements such as:

* separate master-key architecture
* self-describing crypto envelope
* authenticated metadata
* encrypted local titles
* encrypted remote backups regardless of UI lock state
* anti-rollback/version protection
* stronger sync concurrency handling
* fail-closed security checks
* secure Android backup rules
* release artifact hashes
* signing fingerprint publication
* dependency monitoring
* threat-model documentation
* security policy / SECURITY.md
* responsible disclosure process
* automated security tests
* crypto test vectors
* migration tests
* fuzz testing for backup JSON/ciphertext
* property-based tests for encryption/decryption
* static analysis
* secret scanning
* dependency vulnerability scanning
* CI checks preventing direct `debugPrint`
* CI checks preventing accidental cleartext network connections
* tests ensuring only approved hosts can receive authenticated requests
* tests ensuring GitHub tokens are never present in URLs/logs
* tests ensuring malformed remote backup data cannot crash or overwrite state
* audit logging that never includes sensitive values

For every proposed enhancement explain:

Why it helps
What threat it mitigates
Implementation complexity
Whether it changes UX
Whether it is worth doing before release

 

# 25. Create a final prioritized action list

End the report with:

## MUST FIX BEFORE RELEASE

Only genuine release blockers.

## SHOULD FIX SOON

Meaningful security/privacy weaknesses.

## GOOD HARDENING

Security improvements that are useful but not blockers.

## OPTIONAL

Low-impact improvements.

## DO NOT FIX

Things that were investigated and are actually safe/reasonable.

 

# 26. Final security architecture recommendation

After reviewing the code, describe what you believe Rocen's ideal security architecture should be.

Pay particular attention to this desired separation:

User password
↓
Argon2id
↓
Password-derived KEK
↓
wrap/unwrap random Master Key
↓
AES-256-GCM
↓
note data

And independently:

Password verifier
↓
authentication only

Android Keystore / StrongBox
↓
hardware protection of key material where available

GitHub
↓
encrypted backup only

Ensure that password changes, device migration, and recovery all operate on the master key rather than treating a stored password verifier as the actual note encryption key.

 

# 27. Important review rules

Do NOT:

* claim AES/Argon2 is secure merely because the algorithm names are present
* claim something is a vulnerability without an attack path
* assume root detection is a complete security boundary
* assume certificate pinning automatically prevents MITM
* assume Play Protect proves APK authenticity
* assume open-source means audited
* assume a changelog claim is implemented
* assume a private ZIP is identical to the public release
* suggest security theater without explaining its benefit
* recommend custom cryptography when standard constructions already exist
* expose or reproduce real secrets found in the repository

DO:

* trace the actual data flow
* reason from the attacker model
* verify assumptions against source
* prefer standard cryptographic constructions
* minimize secret lifetime
* minimize metadata leakage
* fail closed on security-critical errors
* preserve backward compatibility where safe
* include tests for every security fix
* explicitly mark uncertainty

# Final instruction

Be skeptical but fair.

The goal is not to prove Rocen is insecure.

The goal is to determine:

1. What is actually secure?
2. What is actually insecure?
3. What is merely imperfect engineering?
4. What needs to be fixed before release?
5. What can be hardened later?
6. What new security mechanisms should be added?

Do not rewrite the code during the audit.

Return a technically detailed report with concrete file/function references and a prioritized remediation plan.

<!--We get the full analysis of the source code, and we saw lots of flaws that SHOULD be FIXED before we push the update to the public, our next prompt we are using to catogorized the problem, is written down below, and so see the audit report, check the SECURITY/ for more information that will be fixed in the new update of v0.4.5-->
# After Analysis files are build
Now, lets start fixing each one, but first we need to identify each problem and its effort need to be put, so we choose if we should start that first or at last. Also, we have fix the things that is too important to less important, so create a list of problems that need to be solved, and score them accordingly. 1-10, highest is the most important. 1 = negligible security impact; 5 = useful but non-urgent; 10 = critical and should be addressed immediately.

Scoring:
Give every item a SECURITY PRIORITY score from 1–10:

10 = highest priority / strongest security improvement / should be addressed immediately
9 = critical security issue
8 = very serious security issue
7 = important security weakness
6 = meaningful security hardening
5 = useful security improvement but not urgent
4 = minor hardening
3 = low-impact improvement
2 = mostly convenience/maintainability
1 = negligible security impact
Do not automatically give something a high score just because it is technically interesting.

Also give each item an IMPLEMENTATION EFFORT score from 1–10:
10 = major architectural redesign/migration
8–9 = large/high-risk change
6–7 = significant change
4–5 = moderate change
2–3 = small change
1 = trivial change
For each item briefly explain why that effort score was assigned.
The score should consider:

severity
exploitability
attacker requirements
confidentiality impact
integrity impact
availability/data-loss impact
number of users/data affected
likelihood of real-world occurrence
how much security is gained by fixing it
whether another fix already solves the same root cause

Do not double-count the same root cause.
For example, determine whether:

- password-verifier/encryption-key reuse
- lack of a random master key
- password-change re-encryption burden

are separate fixes or one architectural fix with multiple consequences.

Likewise determine whether:

- missing AAD
- ciphertext substitution
- metadata tampering
- replay/rollback

share a common cryptographic or synchronization root cause.

Do NOT start implementing or editing code.
Do NOT create commits.
Do NOT rewrite files.
Do NOT suggest code unless needed to explain the architecture of a fix.
This is ONLY a prioritization and remediation-planning pass.
At the end, give one recommended sequence:

"Fix this first → then this → then this..."
The sequence should minimize migration risk and avoid fixing a lower-level issue before its architectural dependency has been resolved.