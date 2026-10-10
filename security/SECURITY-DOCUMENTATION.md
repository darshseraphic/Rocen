# ROCEN — Security Documentation Consolidation & Coverage

**Consolidated:** 10 October 2026  
**Purpose:** Make this file the single, self-contained Markdown source for the in-scope Rocen security documentation and the current Stage 5 handoff, so the in-scope source Markdown files do not need to remain as separate files.  
**Important:** This is documentation consolidation, not a fresh source-code audit, not evidence that the app compiles, and not a claim that Stage 5 is complete.

## Table of contents

1. [How to use this single file](#1-how-to-use-this-single-file)
2. [Scope and source manifest](#2-scope-and-source-manifest)
3. [Current status at the last reviewed snapshot](#3-current-status-at-the-last-reviewed-snapshot)
4. [Approved Stage 5 architecture and invariants](#4-approved-stage-5-architecture-and-invariants)
5. [Open blockers and required repair sequence](#5-open-blockers-and-required-repair-sequence)
6. [Runtime validation and completion gate](#6-runtime-validation-and-completion-gate)
7. [Textual preservation of the architecture diagram](#7-textual-preservation-of-the-architecture-diagram)
8. [Coverage and preservation notes](#8-coverage-and-preservation-notes)
9. [Archived source documents](#9-archived-source-documents)
10. [Prior coverage map — historical assessment (Appendix H)](#appendix-h--prior-security-documentation-coverage-map-historical-assessment)

## 1. How to use this single file

This Markdown file has two layers:

- **The front section** is the easy-to-scan index, present status, architecture boundaries, blockers, next actions, test commands, and the textual equivalent of the architecture diagram.
- **The source appendices** preserve the full text of each in-scope Markdown source, with only heading levels shifted downward so each source nests under its appendix heading. Source wording, tables, code examples, checklists, findings, historical claims, and priorities are otherwise retained. The source document title and origin appear before each appendix.

The one separately supplied `Rocen_Stage5_Architecture_and_Security_Handoff.md` is byte-for-byte identical to `security/Stage 5 Architecture & Security Handoff.md` from `security.zip`, so it is represented once rather than duplicated. Its SHA-256 is recorded in the manifest.

The PNG diagram's semantic content is transcribed in Section 7. This Markdown-only consolidation does **not** preserve the PNG's exact pixels, typography, colors, or spatial layout as a binary image. Its component labels, flow steps, state transitions, responsibilities, and stated invariants are captured textually. If exact visual fidelity is required, retain the original PNG outside this single-file set.

Relative links inside archived source text may still mention the original filenames. Those references are retained as historical context; they should not be assumed to open after the original files are deleted.

## 2. Scope and source manifest

### Included sources

| Appendix | Original file / origin | Why it is preserved |
|---|---|---|
| A | `current.md` (supplied alongside the archives) | Current reviewed Stage 5 baseline, blocker list, current implementor instruction, tests, evidence limits, and completion criteria. |
| B | `Phase Stage - 5.md` from `Rocen-Stage-5-Documentation.zip` | Detailed Stage 5 status snapshot, source blockers, documentation cross-checks, broader priority register, tests, and completion gate. |
| C | `Current Stage 5 Workflow.md` from `Rocen-Stage-5-Documentation.zip` | Practical developer/implementor/auditor workflow and next steps. |
| D | `security/Stage 5 Architecture & Security Handoff.md` from `security.zip` | Detailed architecture, previous source findings, file inventory, repair plan, checkpoints, authorization and ownership audits, and AI implementor rules. |
| E | `security/CHANGELOG.md` from `security.zip` | Release-history claims for the project versions documented there. |
| F | `security/PROMPT.md` from `security.zip` | Broad security threat model and audit instruction checklist. |
| G | `security/WORKFLOW.md` from `security.zip` | Root-cause clusters, historical risk/effort scores, findings and recommended order of work. |
| Section 7 | `security/SESSION BOUNDARY & KEY ISOLATION.png` from `security.zip` | Textual reconstruction of the architecture and lifecycle diagram. |
| H | Previous uploaded version of `SECURITY_DOCUMENTATION_COVERAGE.md` | Historical, ten-section assessment mapping the earlier Stage 5 documents against the in-scope root-level files in `security.zip`. It is preserved because this consolidated file uses the same filename. |

### SHA-256 provenance for the supplied source snapshots

Hashes below identify the original files as they were supplied, before this single-file consolidation. They are provenance aids, not security approvals.

| Original source | SHA-256 |
|---|---|
| `current.md` | `46fee47839a1599858b5b9bcd0639fcf4ecec669ade24fc0eccc232bbbcc432b` |
| `Phase Stage - 5.md` | `805459134e3867d11ae736d10923073a2dd0c37eec6cfec5ec8122075406f447` |
| `Current Stage 5 Workflow.md` | `bfe3d862a274932bed65d95be023d4b5efd69222290b24780f563e1c5de39d97` |
| `security/Stage 5 Architecture & Security Handoff.md` | `c384fb5975a5294cec8f5f0b5f5db3b1f74e2e3689be91d0d747e2b76c52d413` |
| `Rocen_Stage5_Architecture_and_Security_Handoff.md` (duplicate of the preceding file) | `c384fb5975a5294cec8f5f0b5f5db3b1f74e2e3689be91d0d747e2b76c52d413` |
| `security/CHANGELOG.md` | `4da3dd849e4eebda49c90d924517966af758532c7fa9b7bb257ffb253dfb32e2` |
| `security/PROMPT.md` | `f3fcb7bd858edd97430b8893fcfa1d8dc6f081ec6d8c224ec0b61da09d8172e0` |
| `security/WORKFLOW.md` | `ba94f171eadf5dc92ae4ded95f98605f4eea5c3899152a9792e8bcacb58179e0` |
| `security/SESSION BOUNDARY & KEY ISOLATION.png` | `e3467ba2bf068ae935b076f6d10311a5dc17972ca8baeae77a0a28c57d0437e5` |

### Explicit exclusions

This consolidation **does not include or claim to cover**:

- `security/MULTI-DEVICE.md`
- Anything inside `security/audits/`
- Anything inside `security/remediation/`

Those materials were expressly excluded from the requested scope. References to them that occur inside retained source documents remain references only; the excluded file contents have not been copied, analyzed, or certified here.

### Single-file cleanup guidance

The included Markdown text is present in this file. After confirming this consolidated copy meets your needs, the separate `current.md`, `Rocen_Stage5_Architecture_and_Security_Handoff.md`, and `Rocen-Stage-5-Documentation.zip` are redundant for the in-scope textual content. The in-scope root Markdown files (`CHANGELOG.md`, `PROMPT.md`, `Stage 5 Architecture & Security Handoff.md`, and `WORKFLOW.md`) are also reproduced below.

**Do not delete `security.zip` without consciously accepting the loss of the excluded material inside it.** The archive also contains `MULTI-DEVICE.md`, `security/audits/`, `security/remediation/`, and the original PNG. None of those excluded Markdown contents have been merged here. The PNG's readable semantic content is transcribed in Section 7, but its exact visual pixels/layout are not retained. If you truly want only this one Markdown file, deletion of the archives means accepting those omissions and the loss of the original visual asset.

## 3. Current status at the last reviewed snapshot

**Snapshot date:** 10 October 2026.  
**Last independently reviewed app-source archive named by the handoff:** `Rocen-P5-repair-2.zip`.  
**Stage 5 status in that snapshot:** **IN PROGRESS / NOT APPROVED**.  
**Runtime evidence:** no confirmed Flutter/Dart compile, analysis, or test run is recorded for that source snapshot.

This status is taken from the supplied handoff records. It does not establish what may have changed in files or archives produced after the recorded snapshot. Before acting on it as today's status, compare any newer source archive and implementor report against the source and update this section with actual evidence.

### Improvements the reviewed source was reported/observed to contain

The status documents record the following structures in `Rocen-P5-repair-2.zip`; they should be preserved unless a later independent source inspection proves a defect:

- `MasterKeyManager` is no longer intended to be the long-lived live-key owner; the activation transaction is library-private as `_ActivationTransaction`.
- Temporary activation MK/NEK/TEK values are transaction-owned before transfer; stale unwrap output is checked after the await, with a defensive stale adoption/clearing path.
- The named activation checkpoints exist in source: `AFTER_PASSWORD_AUTH`, `AFTER_MK_UNWRAP`, `AFTER_NEK_DERIVATION`, `AFTER_TEK_DERIVATION`, `BEFORE_SESSION_INSTALL`, `AFTER_SESSION_INSTALL`, and `BEFORE_ACTIVATION_COMMIT`. A separate unwrap/adoption race seam is also discussed in the handoff.
- Session key installation has generation/transaction freshness checks; rollback is intended to remain scoped to its activation attempt.
- The old public `associateRemoteForTesting()` and `changePasswordForTesting()` APIs are reported removed from the reviewed snapshot.
- `SessionAuthorizationToken` is used by authenticated `changePassword()` and `associateRemote()` operations; the previous public `MasterKeyLocalStore.write`/`clear` surface is removed in favor of the trusted-library arrangement described in the handoff.
- Generic GitHub writes reject reserved authority paths, including malformed or normalized variants. Authority mutations use `GithubAuthorityWriteGrant` and are intended to revalidate immediately before remote mutation.
- `PasswordStateManager` mutation methods have been moved away from public APIs into the trusted implementation.
- A separate `ProtectedSessionApp`/Navigator and `ProtectedSessionResources` structure owns protected navigation and a root `ProviderContainer`; destruction callbacks are registered so security-owned resources can be destroyed synchronously through `lockSync()`.
- Lifecycle transitions away from resumed/interactive state call `lockSync()`; corrupt authority is intended to fail closed rather than be treated as first-run absence.
- Protected application-data persistence is gated off/fail-closed while the Stage 6 encrypted envelope is not implemented.

These are source-snapshot observations recorded in the handoff, not a claim that runtime tests passed.

## 4. Approved Stage 5 architecture and invariants

Stage 5 hardens the session/authority boundary while preserving Stage 3/4 cryptographic meaning and persistent credential/wrapper formats. It is not permission to redesign the cryptographic format or to claim Stage 6 is done.

### Ownership boundaries

| Component | Intended responsibility | Must not do |
|---|---|---|
| `MasterKeyLocalStore` | Persist/read the durable encrypted or wrapped authority record, recovery data and metadata. | Own live session key bytes or become an authorization-free public mutation bypass. |
| `MasterKeyManager` | Coordinate authority decisions, validation, state transitions, and activation transactions. | Retain long-lived live MK/NEK/TEK bytes. |
| Internal activation transaction (`_ActivationTransaction`) | Own candidate/temporary activation secrets for one unlock or activation attempt; track freshness; support synchronous invalidation and cleanup. | Become a publicly constructible, long-lived, authoritative key owner. |
| `SessionKeyMaterial` | Sole authoritative live owner of MK, NEK and TEK after successful session installation. | Leave authoritative live key material present after lock. |
| `SessionSecurityManager` | Own authoritative lifecycle/security state, session generation/epoch, authorization policy, and registered security cleanup. | Treat a state label by itself as proof that a particular asynchronous operation remains authorized. |
| `SessionAuthorizationToken` | Private/unforgeable, epoch/session-bound proof used by authenticated protected operations. | Remain valid after lock or be replaced with public “test” mutation APIs. |
| Session-scoped protected UI/resources | Keep the protected `MaterialApp`/Navigator and ProviderContainer/resources within the security-owned session lifetime. | Depend on a later Flutter frame as the security primitive for privileged teardown. |
| Stage 4 crypto providers | Perform HKDF/KDF/domain-separation/AEAD/key-derivation operations as appropriate. | Cache long-lived live keys in providers, closures, static fields, or unrelated state. |

### Core invariants

1. While `UNLOCKED`, `SessionKeyMaterial` is the sole live authoritative owner of MK/NEK/TEK.
2. While `LOCKED`, no authoritative live MK/NEK/TEK remains in any component.
3. A transaction-local candidate is temporary and non-authoritative until validated and installed; it is cleared after use and on failure, cancellation, staleness, or other exit paths on a best-effort basis.
4. All relevant asynchronous work validates session/transaction freshness after each relevant await and immediately before a protected side effect. A stale result must not install keys or mutate protected local/remote authority.
5. `lockSync()` synchronously invalidates authorization/transaction freshness, clears transaction-owned temporary material, destroys `SessionKeyMaterial`, and invokes security-owned cleanup for provider/session resources independently of Flutter frame timing.
6. `changePassword` and `associateRemote` must perform their final freshness/authorization checks immediately before each protected durable mutation or remote side-effect start.
7. Bootstrap eligibility is operation-scoped. The fact that state equals `LOCKED` or `BOOTSTRAP` is not, alone, authority to run privileged bootstrap mutations.
8. First-run and valid recovery must remain possible through narrowly authorized bootstrap operations; corrupt or conflicting authority must fail closed or follow explicit reconciliation, not silently fall back to fresh-install behavior.
9. Generic GitHub backup APIs must not mutate reserved security authority paths outside the trusted authority-write mechanism. Any authority-write grant must be confined to its permitted operation/path/mutation/fence/lifetime and must not leak through caller-controlled overrides.
10. The seven checkpoint boundaries must be real stale-transaction boundaries. Production checkpoint pausing must be inert by default; deterministic tests may enable it using an explicit compile-time test define.
11. Protected session UI and ProviderContainer must be genuinely session-scoped and security-owned. Widget disposal on a later frame is not enough for synchronous security teardown.
12. Preserve the existing Stage 3/4 cryptographic meanings and stored format. AAD/envelope and anti-rollback work are outside this Stage 5 repair unless separately approved as a later phase.

### Explicit limitations

- Dart `String` values are immutable and cannot be reliably overwritten in place. Crypto libraries may create internal/transient copies. Secret lifetime should be minimized, but physical zeroization of every runtime/library copy must not be claimed.
- Native screenshot/screen-capture enforcement is not verified from the reviewed repair archive because Android/iOS native implementation was not present there. The app's actual policy for unsupported platforms must be an explicit product/security decision; accepting “unsupported” as if protected is not proof of enforcement.
- Stage 6 encrypted durable app-data envelope is not implemented by this Stage 5 snapshot. Protected application-data persistence is reported disabled/fail-closed; this is not equivalent to completed data-at-rest encryption.
- An incomplete repair ZIP lacking platform folders/assets is not proof that a complete project cannot build, but it also cannot support a build/test pass claim.

## 5. Open blockers and required repair sequence

The last-reviewed `Rocen-P5-repair-2.zip` handoff identifies two primary architecture blockers and associated routing, cleanup, policy, and evidence issues.

### Blocker A — GitHub authority-grant leakage / insufficient grant scope

The documented problem is that `GithubBackupService` is subclassable and authority-writing methods can be overridden. If a trusted production service passes a real `GithubAuthorityWriteGrant` through an overridable public method, a caller-controlled subclass can capture the grant. A private constructor by itself does not prevent this.

**Required direction:** remove the caller-controlled grant-interception path; bind each grant to its intended operation, permitted paths and mutation kind, fence, and limited lifetime; reject unrelated or replayed use; use transport-level testing that does not expose real grants; recheck authority/freshness immediately before each protected remote mutation.

### Blocker B — State-only bootstrap fence

The documented `_PreSessionFence` is stateless and delegates to `requirePreSession()`, which accepts both `BOOTSTRAP` and `LOCKED`. A locked established account must not gain privilege-free bootstrap mutation authority just because it is locked. In addition, `lockSync()` during `BOOTSTRAP` can advance the epoch while the state remains `BOOTSTRAP`; a state-only check can therefore accept stale work.

**Required direction:** use a narrowly scoped bootstrap permit/operation bound to an explicit eligibility decision and monotonic generation/epoch. Synchronous lock must invalidate it, and stale work must fail before further protected work.

### Blocker C — Bootstrap routing and authority-state decisions

The status snapshot says `_refreshAuthority()` calls `finishBootstrap()` without first making the transition conditional on separate no-authority, valid-authority, and corrupt-authority outcomes. `establishFirstDevice()` also has a path with an existing local record that was flagged for review because bootstrap/recovery must not become a privileged bypass for an existing locked account.

**Required direction:** route fresh install, an existing valid authority record, and corrupt authority distinctly; ensure recover/first-device operations are truly bootstrap-scoped; after relevant local or remote awaits, revalidate before deriving secrets, mutating local authority, or initiating another remote mutation. If authority appears concurrently, use explicit conflict/reconciliation behavior rather than stale overwrite/promotion.

### Blocker D — Bootstrap cleanup and test reset isolation

The status snapshot reports that `lockSync()` has a `BOOTSTRAP` early-return path that skips registered cleanup callbacks. It also reports public `resetForTesting()` controls that reset the epoch to zero and return to `BOOTSTRAP`, raising production exposure and stale-generation/ABA concerns.

**Required direction:** run security-owned cleanup when a lock occurs during bootstrap, synchronously where required; restrict test reset controls to a genuine test arrangement; do not reset monotonic freshness tokens to a fixed old value.

### Blocker E — Screen-security policy and native evidence

The status documents flag that `ScreenSecurity.satisfiesPolicy()` treats `unsupportedPlatform` as satisfying the protection policy, while the actual native MethodChannel handler could not be audited from the repair archive. Native screenshot protection remains **unverified** until the platform sources and a real platform validation are available, and the unsupported-platform behavior must be explicitly decided.

### Blocker F — Runtime verification absent

The recorded implementation environment had no Flutter/Dart toolchain. Tree-sitter parsing and Python/static source assertions are not equivalent to Dart compilation, `flutter analyze`, or running `flutter test`. No completion decision may be based on the implementor report alone.

### Next repair sequence

1. Inspect the actual returned archive and changed-file list; do not rely solely on the implementor summary.
2. Verify grants cannot be captured through an override and are bound to intended operation, permitted path/mutation set, current fence, and short lifetime.
3. Verify bootstrap permits are genuinely operation-scoped, generation/epoch-bound, invalidated by lock, and checked after relevant awaits and immediately before protected side effects.
4. Verify fresh-install, established locked-account, valid authority, corrupt authority, and recovery routes separately.
5. Verify bootstrap lock executes sensitive cleanup and test resets cannot reopen bootstrap or create an ABA/stale-generation problem.
6. Preserve the existing seven activation checkpoints, transaction ownership, reserved path hardening, protected session UI/provider resources, and Stage 3/4 cryptographic meanings.
7. Review deterministic test cases and then execute all required commands in the complete project.
8. Update this section and the evidence inventory only after independently checking the new source and obtaining actual command output/exit codes.

## 6. Runtime validation and completion gate

Run from the directory of the **complete** Flutter project, not from an incomplete security repair ZIP. In Windows PowerShell:

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true --reporter expanded
```

Capture full output and exit code for each command. Do not report a command as passed unless it was actually executed and exited successfully.

The normal test run must demonstrate that checkpoint controls are inert in ordinary mode. The define-enabled run must actually exercise deterministic pause/resume tests; skipped or unexecuted race tests are not passes. Required deterministic coverage includes:

- each of the seven activation checkpoints;
- the unwrap/adoption race and stale install/rollback behavior;
- inability to intercept/capture/replay authority grants, plus path and mutation scope restrictions;
- bootstrap lock during local/remote awaits;
- expired/stale bootstrap permit rejection;
- refusal to run bootstrap-only mutations for an established locked account;
- distinct missing/valid/corrupt authority routing;
- synchronous bootstrap sensitive-input/resource cleanup;
- test reset isolation and monotonic-generation behavior;
- protected UI/provider-container teardown; and
- stale results being unable to trigger later protected mutations.

Use exactly one evidence label per required test or command:

- `EXECUTED AND PASSED`
- `EXECUTED AND FAILED`
- `NOT EXECUTED — runtime unavailable`
- `SOURCE-REVIEWED ONLY`

Do not mark Stage 5 approved until the independent source review and complete-project runtime evidence support every required gate. The handoff also preserves broader follow-up items including Stage 6 encrypted note/application-data storage, Android release signing and backup policy, ProGuard/R8, native screen protection, remote payload limits, metadata minimization, sync failure surfacing, memory-copy hardening, supply-chain checks, and known changelog/source mismatches. Those are not closed by completing this narrow Stage 5 repair.

## 7. Textual preservation of the architecture diagram

The original `SESSION BOUNDARY & KEY ISOLATION.png` has seven visible regions. This transcription preserves the readable labels and intended relationships so the PNG can be removed if visual fidelity is not required.

### 7.1 System architecture — Stage 3 + Stage 5

**User / App** lists the operations: unlock; change password; recover; manage devices; use app features.

**App layer (UI / Services)** contains Authentication Service, Settings Service, Crypto Service (providers), and Background Tasks.

**Stage 5 — Session Layer** contains `SessionKeyMaterial`, labelled “sole live owner while unlocked”, with MK (authoritative), NEK (derived), and TEK (derived). It owns/manages key lifecycle and zeroes on lock.

**Stage 3 — Authority Layer** contains `MasterKeyManager`, labelled “state/controller only”, with authority state (none / provisional / authoritative), transaction control, validation/coordination, and an explicit “NEVER holds live MK bytes” invariant.

**Persistent Storage** contains `MasterKeyLocalStore`, described as durable authority, with encrypted wrappers, recovery data, and metadata.

The **Stage 4 Crypto Providers** row contains HKDF (key derivation), KDF (domain separation), AEAD (encryption/authentication), Key Derivation (NEK/TEK), and Secure Storage (encrypted data).

The diagram shows interaction between user/app and app services; app services and session layer; app services and authority layer; authority layer and persistent storage; and crypto-provider interactions with the session/authority parts as appropriate. These arrows describe intended architecture, not verified runtime wiring.

### 7.2 Key ownership model

The green single-owner invariant says that while `UNLOCKED`, `SessionKeyMaterial` is the sole live authoritative owner of MK / NEK / TEK; when `LOCKED`, no live authoritative key remains in any component.

- `MasterKeyLocalStore` (durable authority): encrypted wrappers, recovery data, metadata; explicitly “Not a live key owner”.
- `MasterKeyManager` (state/controller): state machine, transaction control, validation, coordination; explicitly “No live MK buffer”.
- `SessionKeyMaterial` (sole live owner): MK authoritative, NEK derived, TEK derived; only owner when `UNLOCKED`.
- **Transaction-local candidate (temporary):** holds MK during operations; non-authoritative until validated; zeroed after use, on failure, cancellation, or when stale. It is not a long-lived owner, is not accessible to generic crypto, and must be validated and authorized.

### 7.3 Key lifecycle and workflow

**3.1 Cold start:** app launches → no live MK in memory → `MasterKeyLocalStore` provides encrypted wrappers → system is `LOCKED`; there is no live authoritative MK.

**3.2 Unlock (password):** user enters password → unwrap MK into a transaction-local candidate → validate transaction/session (epoch) → `SessionKeyMaterial` takes ownership → candidate buffer is zeroed → derive NEK / TEK (Stage 4). Intended state: `UNLOCKING` → `UNLOCKED`; `SessionKeyMaterial` owns MK / NEK / TEK.

**3.3 Change password:** re-authenticate current password → obtain current MK from session → prepare new password wrapper using the same MK → validate → update local/remote wrappers → zero temporary material. Intended state remains `UNLOCKED` with the same MK rewrapped under the new password.

**3.4 Recovery / associate remote:** verify recovery / remote authentication → unwrap MK into a transaction-local candidate → validate epoch / transaction → `SessionKeyMaterial` takes ownership → candidate is zeroed → refresh recovery wrappers / sync. The drawing's flow is an intended lifecycle illustration only; the Stage 5 text separately marks the recovery/association scope for audit and must not be read as proof the reviewed implementation route was safe.

**3.5 Lock:** invalidate authorization and epoch → synchronously destroy `SessionKeyMaterial` and zero MK / NEK / TEK → clear providers / caches → dispose protected container → update state to `LOCKED`. The stated end state is no live authoritative MK anywhere.

**3.6 Second unlock:** user enters password → unwrap MK to candidate → validate and install → zero candidate → derive NEK / TEK (Stage 4) → new `SessionKeyMaterial` owner; intended state is `UNLOCKED`.

### 7.4 Component responsibilities

- **User / App:** collects credentials, triggers operations, displays status, and never handles keys.
- **SessionKeyMaterial:** owns MK / NEK / TEK, derives NEK / TEK, manages lifecycle, zeroes on lock, and has no persistent storage.
- **MasterKeyManager:** state machine, validation/coordination, transaction control, never holds live MK bytes, reads/writes the local store.
- **MasterKeyLocalStore:** persistent wrappers, recovery data, durable authority, never holds a live key.
- **Crypto Providers:** HKDF / KDF / AEAD / derivation functions; no persistent key cache and no live-key storage.

### 7.5 State transitions

The diagram's principal sequence is:

`LOCKED (no live MK)` → `UNLOCKING (transaction-local candidate)` → `UNLOCKED (SessionKeyMaterial owns MK / NEK / TEK)` → `LOCKING (destroy session material)` → `LOCKED`.

A lock/unlock cycle returns through `LOCKED`; a new activation must not inherit authoritative keys from the previous session.

### 7.6 Diagram security invariants

- `UNLOCKED`: `SessionKeyMaterial` owns live MK / NEK / TEK; `MasterKeyManager` has no live MK.
- `LOCKED`: `SessionKeyMaterial` is destroyed synchronously; no live authoritative MK remains anywhere.
- Transaction-local candidates are non-authoritative and zeroed on all exit paths.
- All asynchronous operations validate the session/transaction; stale results cannot install keys.
- No long-lived secret resides in providers, closures, static fields, or cached state.

### 7.7 Diagram legend

The diagram distinguishes the User/App layer, Stage 5 Session layer, Stage 3 Authority layer, Persistent Storage, Stage 4 Crypto Providers, and transaction-local temporary material. Arrow classes are labelled **Data flow**, **Control flow**, and **Interaction**. Green check icons visually mark intended invariants; they are not test results or proof that the code obeys the diagram.

## 8. Coverage and preservation notes

The earlier coverage review concluded that the two Stage 5 consolidation documents were useful for current status and operational work, but were not by themselves an archival replacement for the root security documentation. The complete predecessor report is preserved in **Appendix H** so its classifications, source-by-source coverage tables, and retention guidance are not lost. Appendix H is a historical assessment of the *earlier pair* of Stage 5 documents; it is not an independent audit of this new consolidated file. This updated file separately retains the full source text of the included Markdown sources in Appendices A–G.

- **`CHANGELOG.md`:** its complete historical release notes are retained in Appendix E. Changelog claims remain claims made at the time they were written; they are not proof for `Rocen-P5-repair-2.zip` or a later archive.
- **`PROMPT.md`:** the broad threat-model and audit checklist is retained in Appendix F, not just the subset relevant to Stage 5. The prompt itself is a review instruction set, not a report that every question has been answered.
- **Stage 5 handoff:** the complete handoff text is retained in Appendix D; its detailed file/test inventory and prior findings remain available as design/review history.
- **`WORKFLOW.md`:** the complete clusters, score table and recommended sequence are retained in Appendix G. Original scores are planning ratings, not a fresh risk evaluation.
- **Stage 5 snapshot/workflow:** Appendices B and C preserve the detailed status and operational instructions; Appendix A gives the short current handoff recorded for the same review window.
- **Diagram:** the semantic content is retained in Section 7, but the precise graphic is not embedded.

### What this document does not prove

It does not prove that the described architecture is correctly implemented; it does not turn historical changelog statements into verified facts; it does not show that runtime tests passed; it does not resolve open blockers; it does not implement Stage 6; and it does not cover the expressly excluded `MULTI-DEVICE.md`, audit folder, or remediation folder. A single-file consolidation reduces documentation navigation friction only. Code review, actual test execution, and explicit evidence recording are still required.

## 9. Archived source documents

The appendices below preserve the supplied Markdown sources. Only the heading depth is adjusted to make each source a section of this master file. The contents are included for reference, not re-endorsed as current facts where they describe an older baseline.

---

## Appendix A — Current Stage 5 Development Status

<!-- Original source filename: current.md -->
<!-- Original SHA-256: 46fee47839a1599858b5b9bcd0639fcf4ecec669ade24fc0eccc232bbbcc432b -->

### ROCEN — Current Stage 5 Development Status

**Last updated:** 10 October 2026  
**Current source baseline:** `Rocen-P5-repair-2.zip`  
**Current phase:** Stage 5 architecture repair — GitHub authority-grant scope and bootstrap authorization/fencing  
**Status:** In progress. Do not declare Stage 5 complete.

---

#### 1. Purpose of this document

This file is the short, current handoff for developers and AI agents working on Rocen Stage 5. It records what exists in the latest reviewed source, what has been found, what the implementor is currently being asked to fix, and what evidence is still required.

It is a status document, not a replacement for the Stage 5 architecture/security specification. Source code is the authority for what is actually implemented. Implementor reports describe claimed work but do not prove that it compiles or passes tests.

#### 2. Workflow being used

The project uses the following engineering workflow:

1. **Developer** defines the requirement and supplies the current project source.
2. **AI source review** inspects the actual files, rather than relying only on status reports.
3. **Two AI auditors** challenge the findings and each other's proposed fixes until the concrete security issue and an acceptable remedy are clear.
4. **Prompt review/refinement** turns the findings into a bounded implementation prompt, preserving correct existing work and avoiding unintended Stage 3/4 redesign.
5. **Implementor AI (Claude)** changes source and tests, then reports what changed and what it could verify.
6. **Independent source re-audit** checks the returned ZIP against the report and the security requirements.
7. **Runtime verification** runs Flutter/Dart commands in a complete project environment. Static source checks are not treated as runtime test execution.
8. **Completion decision** is made only when the source audit and available executed-test evidence support it.

The aim is not to produce increasingly large prompts. The aim is to identify concrete defects, fix them, verify the actual resulting source, and record evidence honestly.

#### 3. Current source baseline and evidence limits

The latest reviewed archive is `Rocen-P5-repair-2.zip`. Claude reported that it made source changes and test updates, but it did **not** have a Dart/Flutter toolchain. It reported only a Tree-sitter syntax pass over `lib/` and `test/`, plus Python checks that re-created some static assertions.

Therefore, for this baseline:

- **Flutter/Dart compilation:** not verified.
- **`flutter analyze`:** not executed.
- **`flutter test`:** not executed.
- **Deterministic race tests:** present/updated in source, but runtime results unverified.
- **Static/source assertions:** some were mechanically checked in Python; these are not Dart test execution.
- **Native screenshot protection:** not verified; the archive does not contain Android/iOS native source implementing the screen-security channel.

The repair ZIP is a source snapshot, not proof of a runnable complete mobile project. Use the complete project environment, including its required assets and native platform files, for runtime validation.

#### 4. Work already present in `Rocen-P5-repair-2.zip`

The following improvements are present in source. They should be preserved unless the next source review finds a concrete defect:

##### Activation and key ownership

- `MasterKeyManager` no longer serves as the long-lived live-key owner.
- The activation transaction is represented by the library-private `_ActivationTransaction`.
- Temporary activation MK/NEK/TEK material is transaction-owned before transfer.
- Stale unwrap output is checked immediately after the unwrap await; adoption also has a defensive stale check and clearing path.
- Key material is transferred toward `SessionKeyMaterial` through the activation/install flow.
- The seven required checkpoint boundaries are represented in source: `AFTER_PASSWORD_AUTH`, `AFTER_MK_UNWRAP`, `AFTER_NEK_DERIVATION`, `AFTER_TEK_DERIVATION`, `BEFORE_SESSION_INSTALL`, `AFTER_SESSION_INSTALL`, and `BEFORE_ACTIVATION_COMMIT`.
- `SessionKeyMaterial.install()` contains local stale-generation/transaction enforcement after `AFTER_SESSION_INSTALL`.
- Rollback is scoped to the activation attempt, intended to avoid an old failed attempt clearing a newer one.

##### Authenticated service operations and remote paths

- The old `associateRemoteForTesting()` and `changePasswordForTesting()` public methods were removed from this source snapshot.
- `SessionAuthorizationToken` is used for authenticated `changePassword()` and `associateRemote()` operations.
- `MasterKeyLocalStore` writes are no longer exposed through the previous public `write`/`clear` surface; the store is integrated as a `part` of the trusted service library.
- Generic GitHub writes reject reserved authority paths such as `device_key.json` and `password_state.json`, including attempts to bypass simple path comparison with malformed/normalized variants.
- Authority-writing methods use `GithubAuthorityWriteGrant` and recheck their fence before mutating HTTP requests.
- `PasswordStateManager` mutation methods were moved away from public APIs into the production-service library's internal implementation.

##### Session UI, providers and lifecycle

- A separate `ProtectedSessionApp` exists with its own `MaterialApp`/Navigator while a session is active.
- `ProtectedSessionResources` owns the root `ProviderContainer`, with a destruction callback registered with `SessionSecurityManager`.
- Intended privileged resource destruction is synchronous through `lockSync()`; framework widget-state disposal may follow on a later frame.
- Navigation state is data-only rather than a collection of retained screen widgets.
- Lifecycle transitions away from resumed/interactive state call `lockSync()`.
- Corrupt authority has a distinct fail-closed route, rather than silently being treated as fresh-install absence.
- First-run setup/recovery has a route intended to refresh the authority state and enter the normal lock/unlock lifecycle without requiring a restart.

These are **source observations**, not statements that runtime tests have passed.

#### 5. Problems still open in the current baseline

The latest source audit identified two primary architecture blockers and related issues.

##### A. GitHub authority-grant leakage

`GithubBackupService` is currently subclassable. The production service can be supplied a service instance and passes `GithubAuthorityWriteGrant` into its public authority-writing methods. A caller-controlled subclass can override those methods and capture a real grant.

The grant is not yet sufficiently constrained to one specific logical operation, permitted path set, mutation kind, and lifetime. A private constructor alone does not prevent a valid grant from leaking through an overridable call.

**Required direction:** remove the caller-controlled grant-interception path; constrain grants to their intended operation/path/lifetime; preserve HTTP testing using a transport-level arrangement that does not expose grants; recheck the grant/fence immediately before each protected remote side effect.

##### B. Bootstrap authorization is not operation-scoped

The current `_PreSessionFence` is stateless and delegates to `requirePreSession()`. That check accepts both `BOOTSTRAP` and `LOCKED`.

A locked established account must not be allowed to perform privilege-free bootstrap-only mutations merely because it is locked. Also, a `lockSync()` occurring during `BOOTSTRAP` advances the epoch while the state can remain `BOOTSTRAP`; the current state-only fence can therefore still pass after lock.

**Required direction:** use a narrowly scoped bootstrap operation/permit bound to the applicable generation/epoch. `lockSync()` must synchronously invalidate it; resumed work must fail freshness validation before further protected work. Preserve genuine first-run bootstrap and recovery without inventing a second password or wrongly requiring a normal unlocked-session token.

##### C. Bootstrap routing and cleanup

The current source calls `finishBootstrap()` from `_refreshAuthority()` without first making the authority-eligibility transition conditional on distinct no-authority/valid-authority/corrupt-authority cases.

The `BOOTSTRAP` early-return path in `lockSync()` does not run registered cleanup callbacks. That can leave sensitive bootstrap UI/controller cleanup unperformed during a lifecycle lock.

`resetForTesting()` also resets the epoch to zero and returns the manager to `BOOTSTRAP`; this needs a restricted test arrangement and an audit for stale-generation/ABA concerns.

##### D. Related paths that must be rechecked

- `recoverFromRemote()` and `establishFirstDevice()` must be genuinely bootstrap-scoped. They must not serve as alternate mutation paths when local authority already exists.
- After every relevant remote read/await, the bootstrap operation must be revalidated before further secret-derived work, local authority mutation, or another remote mutation.
- Concurrent appearance of an authority record must trigger the intended conflict/reconciliation behavior, not a stale overwrite or promotion.
- Already-started network requests are not assumed cancellable; the guarantee is that stale results do not trigger subsequent protected mutations.

#### 6. Current repair instruction being implemented

The latest prompt asks Claude to repair the current source, not redesign Stage 5. Its scope is:

1. **Fix authority-grant leakage:** ensure grants do not pass through caller-controlled overridable service methods; bind a grant to its intended operation, path/mutation set, fence, and lifetime.
2. **Make bootstrap authorization operation-scoped:** a bootstrap permit is issued only for an explicitly eligible setup/recovery operation and becomes stale on `lockSync()`.
3. **Correct first-run/existing-account/corrupt-authority routing:** `LOCKED` alone does not authorize bootstrap mutation; corrupt authority fails closed; legitimate first-run recovery remains possible.
4. **Fully audit `recoverFromRemote()`:** trace all callers, local-record races, awaits, secret ownership, serialization, and durable mutation.
5. **Fix bootstrap cleanup:** `lockSync()` during bootstrap invalidates permits, advances generation, clears registered sensitive inputs and destroys registered resources synchronously.
6. **Restrict testing reset controls:** prevent `resetForTesting()` from being an ordinary production control or from reopening bootstrap authority in production; avoid epoch reset patterns that can create ABA-style ambiguity.
7. **Preserve existing activation/checkpoint work** and update/add deterministic tests.
8. **Report evidence honestly:** source checks, mechanical checks, hand-traced reasoning, and executed Dart/Flutter tests must be separate categories.

Claude has not yet returned a verified post-repair ZIP/report for this latest prompt. The above is the work currently in progress, not a claim that these remaining blockers are fixed.

#### 7. Likely files affected by the current repair

The implementor should confirm the exact change list in its final report. Expected files to inspect/include where necessary:

| File | Why it matters |
|---|---|
| `lib/core/master_key_production_service.dart` | Defines the authority grant, mutation fences, and first-device/recovery orchestration. |
| `lib/core/github_backup_service.dart` | Currently subclassable; exposes authority-write methods and generic write protections. |
| `lib/core/password_state_manager.dart` | Remote password-state writes and device/generation bookkeeping. |
| `lib/core/session_security_manager.dart` | Session states, epoch, `lockSync()`, cleanup callbacks, bootstrap eligibility and reset behavior. |
| `lib/main.dart` | `_refreshAuthority()` and first-run/existing/corrupt-authority routing. |
| `lib/core/session_unlock_service.dart` | Bootstrap/unlock flow and credential/MK handling. |
| `lib/core/security_checkpoints.dart` | Deterministic checkpoint testing controls and production-vs-test behavior. |
| `test/authority_remote_write_boundary_test.dart` | Grant leakage, authority paths, bootstrap/remote mutation fencing. |
| `test/session_security_manager_test.dart` | Lock, lifecycle, checkpoint and bootstrap behavior. |
| `test/session_authorization_gate_test.dart` | Session token validity and stale authorization. |
| `test/key_ownership_audit_test.dart` | Repository-wide source assertions; ensure it rejects old bypasses rather than expecting them. |
| Other relevant tests | Any tests whose fakes/callers depend on service subclassing or public testing reset APIs. |

This is a predicted inspection list, not a verified final change list.

#### 8. Next test and validation sequence

After Claude returns the updated source, first inspect the ZIP and compare the changed files against its report. Then use the complete Flutter project directory—not an incomplete archive missing assets or platform source—to execute:

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true --reporter expanded
```

The normal test invocation must verify that checkpoint controls are inert. The define-enabled invocation must run deterministic pause/resume race tests. Confirm the test framework actually ran the race groups; a skipped test is not a pass.

Capture complete output and exit codes. If a command fails, fix the underlying defect and rerun it. Do not weaken security assertions solely to obtain a green test result.

##### Test evidence labels

Every required test should receive exactly one status:

- `EXECUTED AND PASSED`
- `EXECUTED AND FAILED`
- `NOT EXECUTED — runtime unavailable`
- `SOURCE-REVIEWED ONLY`

Tree-sitter syntax parsing and Python checks of Dart source are not Flutter/Dart runtime test execution.

#### 9. Other known limitations (not part of this narrow repair)

- **Native screenshot protection:** the current archive lacks Android/iOS native source implementing the screen-security MethodChannel. Do not claim `FLAG_SECURE` or equivalent OS-level protection is working until the real platform implementation is present and verified. The current Android fail-closed policy still needs a product decision.
- **Stage 6 data-at-rest envelope:** not implemented in this repair scope. Protected persistence remains gated rather than being claimed as encrypted durable application storage.
- **Dart string lifetime:** passwords supplied as Dart `String` values cannot be guaranteed to be physically erased.
- **External cryptographic implementation copies:** a crypto library may retain private transient copies while performing an operation; lockSync cannot clear memory it cannot reach. The system must reject and clear stale results as soon as they return, while claims about physical RAM erasure remain limited.
- **In-process raw storage access:** Dart visibility is an API boundary, not a sandbox against arbitrary code already running in the same process.

These limitations must remain explicit in future handoffs and reports.

#### 10. Completion criteria for this repair

Do not declare this repair complete until source review supports all of the following:

- no caller-controlled override can capture a production authority grant;
- grants are constrained to their intended mutation/path/lifetime and become invalid when the operation or fence ends;
- `GithubBackupService` generic writes cannot bypass reserved authority-path protections;
- bootstrap eligibility is operation-scoped, not merely based on `BOOTSTRAP`/`LOCKED` state;
- `lockSync()` synchronously invalidates bootstrap permits and performs bootstrap sensitive-input/resource cleanup;
- an established locked account cannot use a bootstrap-only public mutation path;
- `recoverFromRemote()` is properly scoped and stale recovery cannot mutate existing authority;
- testing reset APIs cannot reopen bootstrap authorization in a production build or reset generations unsafely;
- existing activation transaction ownership and all seven checkpoint boundaries remain intact;
- the updated tests specifically exercise the new risks;
- runtime claims match what actually ran.

After source repair, run the actual Flutter commands in the complete project environment before deciding whether Stage 5 can proceed to unrelated feature work.

#### 11. Working principle

**The report is not the implementation. The ZIP is the implementation. Tests existing is not tests passing. A stale result being rejected is not proof that its temporary secret was synchronously destroyable. A private constructor is not enough if a live capability can leak through an overridable method. A `LOCKED` state is not, by itself, bootstrap authorization.**

Preserve correct existing work, repair the concrete gaps, re-audit the result, and make evidence-based completion decisions.

---

## Appendix B — Phase / Stage 5 Status Snapshot

<!-- Original source filename: Phase Stage - 5.md -->
<!-- Original SHA-256: 805459134e3867d11ae736d10923073a2dd0c37eec6cfec5ec8122075406f447 -->

### ROCEN — Phase / Stage 5: Session Security Hardening

**Status date:** 10 October 2026  
**Last source archive independently inspected for this document:** `Rocen-P5-repair-2.zip`  
**Overall status:** **IN PROGRESS — NOT APPROVED FOR STAGE 5 COMPLETION**  
**Next implementation repair:** GitHub authority-grant scope/leakage and operation-scoped bootstrap authorization/fencing.  
**Runtime status:** Flutter/Dart compilation and tests have **not** been executed for this source snapshot.

> **Source-of-truth rule:** This document consolidates the security documents and records what the inspected source supports. The source archive is authoritative for source-level claims; an implementor report, changelog, comment, test name, or prior audit is not proof that a behavior works. Runtime success must only be recorded after the corresponding Flutter/Dart commands actually run.

> **Scope note:** `MULTI-DEVICE.md` was intentionally not reviewed or incorporated, as requested. The wider audit backlog from `PROMPT.md` and `WORKFLOW.md` is recorded only where needed to distinguish Stage 5 work from deferred or unverified work.

---

#### 1. Purpose and source set

This file is the consolidated Stage 5 record: architecture intent, source-verified implementation status, open blockers, the repair sequence, tests/evidence, and completion criteria. It combines the Stage 5 material from:

- `CHANGELOG.md` — historical release claims, not security proof;
- `PROMPT.md` — original threat model, audit rules, architecture goals, and prioritization instructions;
- `Stage 5 Architecture & Security Handoff.md` — intended Stage 5 architecture and prior source findings;
- `WORKFLOW.md` — root-cause consolidation and broader security-priority sequence;
- `current.md` and `current(1).md` — merged current baseline, blocker status, and review workflow.

The last source bundle reviewed here is `Rocen-P5-repair-2.zip`. The implementor has reported that another repair is underway, but no post-repair archive was available when this document was prepared. Do not infer that in-progress changes are present.

##### Evidence vocabulary

| Label | Meaning |
|---|---|
| **SOURCE PRESENT — RUNTIME UNVERIFIED** | The code or structure exists in the reviewed archive. This does not prove compilation or correct runtime behavior. |
| **PARTIAL / BLOCKED** | Some mechanism exists, but a known flaw prevents treating the property as satisfied. |
| **NOT IMPLEMENTED / NOT VERIFIED** | The reviewed source does not establish the required behavior, or required platform/runtime evidence is absent. |
| **DEFERRED / OUT OF STAGE 5 SCOPE** | Deliberately reserved for another phase; do not claim it is complete in Stage 5. |
| **RUNTIME VERIFIED** | Use only after actual Flutter/Dart or target-platform commands run and their output/exit code is recorded. **No Stage 5 runtime verification is established for this snapshot.** |

---

#### 2. Stage 5 goal and scope boundary

Stage 5 creates a real session-security boundary around live cryptographic material and privileged UI/provider lifetime. The intended lifecycle is:

```text
BOOTSTRAP → LOCKED → UNLOCKING → ACTIVATING → UNLOCKED
                         ↑                    |
                         └──── lock/rollback ─┘
```

First-run setup/recovery may use a narrowly scoped pre-session operation, but **`LOCKED` alone must never be treated as authorization to perform an unrestricted bootstrap mutation**.

##### Approved ownership model

```text
MasterKeyLocalStore
    = durable wrapped authority record
    = not an owner of live session keys

MasterKeyManager
    = operation state, serialization, and authority decisions
    = no persistent/live MK/NEK/TEK cache

ActivationTransaction
    = one unlock attempt
    = owner of temporary activation secrets
    = synchronously reachable from lockSync()

SessionKeyMaterial
    = sole authoritative live MK/NEK/TEK owner after installation

SessionAuthorizationToken
    = non-forgeable, epoch/session-bound permission for ordinary
      authenticated-session operations

Session/provider/UI resources
    = owned by the current session and synchronously destroyable on lock
```

Epoch/session validity, activation-transaction freshness, and installed-key generation are distinct controls. They must not silently substitute for one another.

##### Scope and invariants

- Preserve Stage 1–4 cryptographic meaning and frozen behavior unless a separately reviewed concrete defect requires a change.
- A password change must rewrap the **same** Master Key, not mint a replacement key.
- No second Stage 5 session password is introduced; the existing cryptography password remains the unlock credential.
- No Stage 6 envelope/migration, compatibility reader, or data migration is introduced in this phase.
- Do not claim guaranteed physical RAM erasure. Describe the controllable buffers/references the application actually clears.

---

#### 3. What the reviewed source already contains

The rows below are source observations in `Rocen-P5-repair-2.zip`, **not executed-test results**.

| Area | What is present in source | Status and evidence |
|---|---|---|
| Session state machine | `SessionSecurityManager` defines `bootstrap`, `locked`, `unlocking`, `activating`, and `unlocked`; the normal unlock/commit path uses these states. | **SOURCE PRESENT — RUNTIME UNVERIFIED** (`lib/core/session_security_manager.dart`) |
| Session authorization | `SessionAuthorizationToken` has a library-private constructor and is epoch-bound. Production `changePassword()` and `associateRemote()` require a token. | **SOURCE PRESENT — RUNTIME UNVERIFIED**; overall authorization boundary remains blocked by adjacent public/overridable mutation paths. |
| Activation transaction visibility | `_ActivationTransaction` is a library-private type in a `part` of `session_security_manager.dart`. | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| MK unwrap/adoption | `session_unlock_service.dart` checks staleness immediately after unwrap returns and before adoption; adoption has its own stale-rejection/zeroing logic. `duringMkUnwrap` can hold the Future only in a compile-time test-control build. | **SOURCE PRESENT — RUNTIME UNVERIFIED**; the result held by an external/completed Future is not transaction-owned until delivered. |
| Temporary and live key ownership | `MasterKeyManager` generates a random 32-byte candidate and does not keep a key field. Activation code holds temporary key material in the transaction and transfers it to `SessionKeyMaterial`; install checks freshness/generation after `AFTER_SESSION_INSTALL`. | **SOURCE PRESENT — RUNTIME UNVERIFIED**; do not interpret this as proof that crypto-library internal copies are erasable. |
| Seven activation checkpoints | All seven required checkpoint names and race tests A–G appear in source/test files. An additional `duringMkUnwrap` test seam exists. | **TESTS PRESENT — NOT EXECUTED** |
| Checkpoint production/test behavior | `SecurityCheckpoints` is gated by `bool.fromEnvironment('ROCEN_SECURITY_TEST_CHECKPOINTS')`; `reach()` returns `null` in a normal build; control methods throw or no-op when disabled. | **SOURCE PRESENT — RUNTIME UNVERIFIED**. Race tests require the explicit `--dart-define`; they must not be counted as passing when skipped. |
| Protected app/navigation | `ProtectedSessionApp` has a session-scoped `MaterialApp`/Navigator; navigation state is data-only. | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| Provider ownership | `ProtectedSessionResources` creates a root `ProviderContainer`; `main.dart` registers its synchronous destroyer with the session manager before awaiting screen-security acquisition. | **SOURCE PRESENT — RUNTIME UNVERIFIED**, but bootstrap cleanup still has a gap described below. |
| Protected data persistence | `database.dart` explicitly sets `protectedApplicationPersistenceAvailable = false`; protected note/task operations fail closed and return no persisted content. | **INTENTIONALLY DISABLED / DEFERRED** until the approved Stage 6 encrypted envelope exists. This is not a claim that encrypted durable notes storage is complete. |
| Corrupt authority distinction | `main.dart` handles `CorruptLocalAuthorityException` separately from a missing authority record. | **PARTIAL**: the current bootstrap-to-locked transition does not make `finishBootstrap()` conditional on the authority result; see blocker B. |
| Generic GitHub write path reservation | `GithubReservedPaths` normalizes paths and fails closed for malformed/reserved paths; the three generic write methods invoke the guard. | **SOURCE PRESENT — RUNTIME UNVERIFIED**; authority grant scope/leakage still blocks approval. |
| PasswordStateManager API | `password_state_manager.dart` is a `part of` the trusted production-service library; the remote mutation methods are underscore-private and local/remote writes have fence calls. | **SOURCE PRESENT — RUNTIME UNVERIFIED**; the passed fence itself is not yet safe enough for bootstrap. |
| Authenticated durable password write | `changePassword()` requires a `SessionAuthorizationToken`, revalidates after KDF/unwrap steps, and uses a fenced local write helper. | **SOURCE PRESENT — RUNTIME UNVERIFIED**; do not declare the full security-operation boundary approved while remote grants/bootstrap fencing remain open. |
| Root-detection failure behavior | `CryptoEngine.isDeviceRooted()` treats channel errors as rooted (`true`). | **SOURCE PRESENT — RUNTIME UNVERIFIED** |

---

#### 4. Confirmed open blockers in the reviewed source

##### Blocker A — GitHub authority grants can leak through an overridable service

**Source:** `lib/core/github_backup_service.dart` (class declaration around line 119 and public `authority*` methods around lines 456, 721, 904); `lib/core/master_key_production_service.dart` (grant class around lines 54–59 and caller-supplied `remoteService` parameters/calls).

- `GithubBackupService` is declared as a non-`final` class.
- Its authority-write methods are public and accept `GithubAuthorityWriteGrant`.
- `MasterKeyProductionService` accepts a service instance from its caller and passes the grant to its methods. A caller-controlled subclass can override a method and capture a live grant.
- The grant contains only a `_MutationFence` and `checkBeforeRemoteStart()`. It is not bound to a specific operation, path set, mutation kind, or single-use lifetime.
- Generic methods do reject reserved authority paths, but that does not solve a leaked grant passed to a public authority method for an unrelated path.

**Required fix:** eliminate the caller-controlled grant-interception path; constrain grants to their intended operation/path/mutation and lifetime; keep legitimate HTTP testing without exposing production grants to overridable test doubles; recheck before every mutating request. Do not merely make the constructor private or add comments.

**Status: BLOCKER CONFIRMED IN SOURCE.** Existing tests capture grants through a fake service and test that they fail after a lock, but do not establish that a grant cannot be reused for an unrelated path while its fence is still valid.

##### Blocker B — Bootstrap fence is stateless and treats `LOCKED` as eligible

**Source:** `lib/core/master_key_production_service.dart` around lines 92–97; `lib/core/session_security_manager.dart` around lines 344–350.

`_PreSessionFence` is a constant, stateless object whose `check()` calls `requirePreSession()`. That check accepts both `BOOTSTRAP` and `LOCKED`, without capturing the generation/epoch of a particular bootstrap attempt.

As a result, a lock can occur during awaited setup/recovery work, advance the epoch, and leave state bootstrap/locked; the old fence can continue passing based only on state.

**Required fix:** issue an operation-scoped bootstrap permit/fence only when setup/recovery is explicitly eligible; bind it to a monotonic operation generation/epoch; invalidate it synchronously on lock; revalidate after awaits and immediately before all protected local writes/remote-write starts. A locked established account must not gain a privilege-free bootstrap path.

**Status: BLOCKER CONFIRMED IN SOURCE.**

##### Blocker C — Bootstrap routing can select the wrong lifecycle transition

**Source:** `lib/main.dart` around lines 160–175; `lib/core/master_key_production_service.dart` around lines 128–180 and 443–493.

- `_refreshAuthority()` performs a local authority read, catches corrupt authority separately, but calls `finishBootstrap()` whenever the state is `BOOTSTRAP` without making the transition conditional on no-authority/valid-authority/corrupt-authority.
- `establishFirstDevice()` has an `existingLocal != null` branch that restores local authority and may call `_associateRemote()` using the pre-session fence. That is too broad if the public bootstrap entry is callable for an established locked account.
- `recoverFromRemote()` is public and also uses the same state-only pre-session fence. The private recovery path needs to be rechecked for a local record appearing during remote/KDF awaits.

**Required fix:** explicitly distinguish no authority, valid existing authority, and corrupt authority; keep genuine first-run setup/recovery possible, but fail closed or route through the authorized operation when authority already exists. A race in which local authority appears must not trigger stale overwrite/promotion.

**Status: BLOCKER CONFIRMED IN SOURCE.**

##### Blocker D — Bootstrap lock skips sensitive cleanup callbacks

**Source:** `lib/core/session_security_manager.dart` around lines 561–579.

When `_state == SessionState.bootstrap`, `lockSync()` increments the epoch, invalidates the activation transaction, destroys registered session resources, and returns early. It does not invoke `_runCleanupCallbacks()`, whereas the normal lock branch does.

**Required fix:** bootstrap lock must synchronously invalidate outstanding bootstrap work and execute applicable sensitive-input cleanup. Callback registration/unregistration must not leak into later sessions or invoke stale controllers.

**Status: BLOCKER CONFIRMED IN SOURCE.**

##### Blocker E — Public test reset can reopen bootstrap and resets epoch

**Source:** `lib/core/session_security_manager.dart` around lines 623–630; `lib/core/master_key_manager.dart` around line 237.

- `SessionSecurityManager.resetForTesting()` is public, calls `lockSync()`, then resets `_epoch = 0` and `_state = bootstrap`.
- `MasterKeyManager.resetForTesting()` is public.
- The current static audit explicitly permits these `resetForTesting()` methods and asserts the session manager returns to `BOOTSTRAP`.

These are useful test isolation controls but remain in the ordinary source API and can affect the production lifecycle if called. Resetting epochs to a fixed value also weakens freshness-generation assumptions if any old state/reference remains reachable.

**Required fix:** constrain resets to the intended test arrangement without relying on the name or annotation; do not reset freshness generations to values that can create ABA-like ambiguity.

**Status: BLOCKER CONFIRMED IN SOURCE.**

##### Blocker F — Unsupported screen-security platform currently satisfies the gate

**Source:** `lib/core/screen_security.dart` around lines 50–60; activation gate in `lib/main.dart` around lines 219–229.

`ScreenSecurity.satisfiesPolicy()` returns `true` for `unsupportedPlatform`, while the same enum documentation says protection is not enforced there. Android's missing/failed native acknowledgement is treated more strictly, but non-Android platforms can pass the policy without actual OS-level protection.

The archive does not include Android/iOS native project sources, so the native implementation of the screen-security channel cannot be independently verified here.

**Required fix:** make the supported-platform/session policy explicit and consistent; do not label unprotected platforms as protected. If the product requires screen-capture prevention for all sensitive sessions, fail closed where enforcement is unavailable; if some platforms are supported without it, document that as an explicit product decision and do not claim protection.

**Status: BLOCKER / POLICY DECISION REQUIRED. Native enforcement NOT VERIFIED.**

##### Blocker G — Current source has not compiled or run under Flutter/Dart

**Source package limitation:** `Rocen-P5-repair-2.zip` contains `lib/`, `test/`, and `pubspec.yaml`, but omits `assets/logo.png` referenced by the manifest and omits native Android/iOS directories.

The implementor reported only Tree-sitter syntax parsing and Python checks of static assertions. No `flutter analyze` or `flutter test` has been executed.

**Required fix:** validate in the complete project environment. Run `flutter pub get`, `flutter analyze`, `flutter test --reporter expanded`, and `flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true --reporter expanded`. Record complete output and exit codes. The normal test run must verify checkpoints are inert; the define-enabled run must actually run the deterministic races, not skip them.

**Status: RUNTIME VERIFICATION NOT DONE.**

---

#### 5. Historical changelog cross-check and documentation mismatches

`CHANGELOG.md` is useful release history; it is not the authority for current implementation state. The following source cross-checks matter to Stage 5 and release-security honesty.

| Changelog / documentation claim | What the reviewed source shows | Status |
|---|---|---|
| Old public `ForTesting` security mutations were removed in the latest repair. | `associateRemoteForTesting()` and `changePasswordForTesting()` are absent from the current source; their authenticated production methods require `SessionAuthorizationToken`. | **Implemented in source**, but other mutation-boundary blockers remain. |
| GitHub authority files are protected from generic writes. | Reserved path normalization and checks exist in `GithubBackupService`; however, authority grants can leak through the overridable service and are not operation/path bound. | **Partial — not approved.** |
| The password rule “NO SAME LETTER IN UPPER + LOWER” was removed. | `CryptoEngine.isPasswordComplexityValid()` still rejects intersecting uppercase/lowercase letters (`lib/core/crypto_engine.dart` around lines 79–80); the displayed requirement list also includes `NO SAME LETTER IN UPPER + LOWER` around lines 95–97. | **CONFIRMED CHANGELOG/SOURCE MISMATCH.** This is not a Stage 5 session-security blocker, but the changelog claim is not true of this source snapshot. |
| `password_state.json` is excluded from GitHub pull/sync as a user note. | This archive has reserved-path write checks and authority reads, but the current source does not expose an obvious general GitHub pull/list pipeline proving the historical exclusion end-to-end. | **NOT RE-VERIFIED in this source snapshot; do not count as proven without a targeted path/test.** |
| Prior changelog says analyzer warnings were resolved / builds were tested. | No current `flutter analyze` or test run exists for `Rocen-P5-repair-2.zip`. | **Historical claim only; current snapshot runtime status remains unverified.** |
| Changelog says hardware binding / secure-storage architecture was preserved. | `CryptoEngine.hardwareKeyTier()` only reports a platform tier; its source comments explicitly say it does not create, wrap, unwrap, persist, or use a hardware-backed data key. The archive contains no native Android/iOS source to inspect. | **Hardware-backed MK protection NOT IMPLEMENTED/VERIFIED in this snapshot. Do not claim it is active.** |
| Stage 5 application data is protected and persisted. | `database.dart` sets `protectedApplicationPersistenceAvailable = false`; protected note/task writes return false and exports return empty data. | **Intentionally disabled until Stage 6 encrypted storage envelope; not implemented as persistent encrypted note storage.** |

Other changelog items about Clipboard media, UI polish, and Android configuration are historical product changes, not evidence that Stage 5 is complete. Native/build configuration claims cannot be independently verified from the current repair ZIP because platform files are absent.

---

#### 6. Relationship to `PROMPT.md` and `WORKFLOW.md`

`PROMPT.md` defines the broad threat model and audit discipline: inspect concrete code paths, distinguish vulnerability from hardening, compare documentation against source, and require evidence for each finding. Its recommendations are not proof that a fix has landed.

`WORKFLOW.md` ranks a broader pre-release backlog. This Stage 5 phase does **not** close every item in that list. Based on the reviewed source:

| Broader audit item | Current disposition for this phase |
|---|---|
| Separate random Master Key from password verifier / password-derived KEK | **Implemented in source architecture:** Stage 3 wraps an independently generated 32-byte MK; verifier is separately salted and is not used as the encryption key. Runtime tests remain unexecuted. |
| Preserve password-wrap KDF metadata | **Present in source:** wrap JSON includes `v`, `kdf`, `memory`, `iterations`, `salt`, `nonce`, `ct`, and `mac`. The current parser accepts only the fixed approved profile; do not infer future profile migration support. |
| Root-detection channel failure | **Fail-closed in source:** `CryptoEngine.isDeviceRooted()` returns/caches `true` on channel error. Runtime/platform behavior not verified. |
| AAD binding for note/title metadata and replay/rollback protection | **Not implemented as the final note envelope in this phase.** Protected note persistence is disabled; this belongs to the later approved data-envelope work, not Stage 5 completion. |
| Encrypted Hive data-at-rest / Stage 6 ciphertext envelope | **Deferred / not implemented.** The current note/task persistence gate is deliberately fail-closed. |
| Android release signing, `allowBackup`, ProGuard/R8 | **Not verifiable from this archive**, which lacks Android project/build files. Must be checked in the complete project before release. |
| Hardware-backed MK wrapping / StrongBox or TEE integration | **Not implemented/verified in this source snapshot.** `hardwareKeyTier()` reports a tier but does not use it to wrap the MK; keep this as a separate approved phase/release requirement. |
| Native screenshot enforcement / `FLAG_SECURE` or equivalent | **Not verified.** The archive has Dart MethodChannel integration but no native platform implementation. The current unsupported-platform policy is too permissive and remains open. |
| Payload-size limits for untrusted remote JSON, `deviceId` metadata minimization, `amendSync` failure surfacing, broader release/supply-chain items | **Separate broader audit backlog.** Not certified complete by this Stage 5 review; return to them in the appropriate phase. |

`MULTI-DEVICE.md` was not reviewed; no claims about that file or its full design are made here.

---

#### 7. Current implementation status summary

| Requirement | Status |
|---|---|
| Real epoch-bound `SessionAuthorizationToken`; no `SessionAuthorizationPolicy`/public no-op model | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| Public `associateRemoteForTesting()` / `changePasswordForTesting()` absent | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| `_ActivationTransaction` internal | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| Candidate MK stale check before adoption and defensive stale-adoption rejection | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| One-way candidate/NEK/TEK transfer and synchronous clearing of transaction-owned buffers | **SOURCE PRESENT — RUNTIME UNVERIFIED; physical erasure beyond reachable buffers not claimed** |
| Seven checkpoints A–G and H unwrap race tests exist | **TESTS PRESENT — NOT EXECUTED** |
| `PasswordStateManager` public mutation API removed | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| Generic GitHub writes block reserved authority paths | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| Grant cannot leak, replay, target an unrelated path, or outlive its operation | **NOT SATISFIED — BLOCKER A** |
| Bootstrap operation is explicitly eligible, epoch/generation scoped, and invalidated by lock | **NOT SATISFIED — BLOCKER B** |
| Bootstrap API cannot act as a recovery/association bypass for an established locked account | **NOT SATISFIED — BLOCKER C** |
| Bootstrap lock invokes sensitive cleanup synchronously | **NOT SATISFIED — BLOCKER D** |
| Public resets cannot reopen bootstrap/reset freshness generation | **NOT SATISFIED — BLOCKER E** |
| Session app/navigation/provider lifetime is session-scoped and destruction is synchronous | **SOURCE PRESENT — RUNTIME UNVERIFIED** |
| Unsupported platform cannot pass a policy that claims screen protection | **NOT SATISFIED — BLOCKER F** |
| Flutter compile/analyze/tests | **NOT EXECUTED — RUNTIME UNAVAILABLE to prior implementor; needs run in complete environment** |
| Stage 5 sign-off | **NOT GRANTED** |

---

#### 8. Required next repair sequence

Do not restart Stage 5. Preserve the improvements already in source and fix in this order:

1. **Close GitHub grant leakage.** Remove caller-controlled interception; bind each grant to a specific operation, allowed paths/mutation kind, current fence and bounded lifetime; prevent reuse after operation completion. Replace grant-capturing test subclasses with transport-level test doubles.
2. **Introduce operation-scoped bootstrap authorization.** Eligibility must be explicitly established for a genuine first-run/setup/recovery attempt, not inferred solely from `BOOTSTRAP` or `LOCKED`. Capture a monotonic generation/epoch and invalidate it on `lockSync()`.
3. **Fix bootstrap routing and recovery scope.** Distinguish absent, valid, and corrupt local authority. Narrow or reject `establishFirstDevice()`/`recoverFromRemote()` paths when authority already exists; validate after each await and before every subsequent protected side effect. Preserve legitimate first-run recovery.
4. **Fix bootstrap synchronous cleanup.** Ensure `lockSync()` in bootstrap invalidates operation permits and runs sensitive-controller cleanup callbacks, with safe callback registration/unregistration.
5. **Restrict test-reset controls.** Remove normal production reachability to `resetForTesting()` or use a genuine test arrangement. Never reset epochs to a fixed value that can create stale-generation ambiguity.
6. **Resolve screen-capture support policy.** Unsupported platforms must not silently satisfy a protection requirement. Make supported-platform behavior an explicit product decision; verify native implementation from the complete platform project.
7. **Update targeted deterministic tests and static audits.** Include grant path/operation reuse, expiry, bootstrap lock during remote/local awaits, existing-local-record recovery rejection, cleanup, and reset isolation. Keep A–G and H unwrap tests.
8. **Run real validation** in the complete project: `flutter pub get`; `flutter analyze`; `flutter test --reporter expanded`; `flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true --reporter expanded`. Save output and exit codes.
9. **Re-audit the resulting ZIP independently.** Compare claimed files with the actual diff, assign evidence labels, and update this file. Do not declare Stage 5 complete until no blocker remains and runtime evidence supports the claim.

---

#### 9. Test and evidence inventory

The reviewed archive includes, among other tests:

- `test/session_security_manager_test.dart` — session transitions, token invalidation, cleanup, checkpoint races A–G, activation ownership diagnostics, the H unwrap/adoption race, and several bootstrap checks.
- `test/authority_remote_write_boundary_test.dart` — reserved path normalization, generic write rejection, authorized write paths, stale write boundaries, test-control behavior, and source-level assertions.
- `test/key_ownership_audit_test.dart` — source checks for authorization API shape, key ownership, protected provider scope, and static boundaries.
- `test/session_key_material_test.dart` and `test/session_unlock_service_test.dart` — install/unlock/key ownership behavior.
- `test/master_key_production_service_test.dart` and `test/session_authorization_gate_test.dart` — production service operation and authorization behavior.
- `test/settings_sensitive_cleanup_test.dart` and `test/widget_test.dart` — selected UI/resource cleanup behavior.

**None of these tests is recorded as executed for the `Rocen-P5-repair-2.zip` baseline.** Test names and assertions are evidence of intended checks, not passing results. Also, the current tests do not close the known grant-scope/bootstrap-generation gaps merely by existing. Some current tests explicitly treat public `resetForTesting()` methods and a stateless `_PreSessionFence` as acceptable; those assertions must be revised as part of the repair.

##### Required status labels for each test after execution

- `EXECUTED AND PASSED`
- `EXECUTED AND FAILED`
- `NOT EXECUTED — runtime unavailable`
- `SOURCE-REVIEWED ONLY`

Do not describe Tree-sitter parsing or Python static checks as Dart/Flutter runtime execution.

---

#### 10. Completion gate

Do not mark Stage 5 complete until all are true:

- [ ] No public authorization-free security mutation exists.
- [ ] No public `ForTesting` security mutation exists.
- [ ] `SessionAuthorizationToken` is the actual capability for authenticated operations and is not forgeable by ordinary code.
- [ ] `GithubBackupService` authority grants do not cross a caller-controlled override boundary.
- [ ] A grant is bound to its intended operation/path/mutation set and expires after that operation.
- [ ] Generic GitHub writes cannot mutate reserved authority files.
- [ ] Each protected remote request start and local durable write has an immediate valid fence check.
- [ ] Bootstrap eligibility is operation-scoped, not inferred from `BOOTSTRAP`/`LOCKED` alone.
- [ ] `lockSync()` invalidates bootstrap permits and prevents stale resumed work from further mutations.
- [ ] Established locked accounts cannot use bootstrap APIs as privilege-free association/recovery paths.
- [ ] Corrupt authority fails closed and cannot be reinterpreted as fresh installation.
- [ ] Bootstrap `lockSync()` runs sensitive cleanup synchronously.
- [ ] Test resets cannot reopen bootstrap authority in normal production or reset freshness epochs unsafely.
- [ ] `_ActivationTransaction` stays internal; candidate ownership transfer is explicit and one-way.
- [ ] All seven activation checkpoint stale boundaries and the unwrap/adoption race remain deterministic and meaningful.
- [ ] `SessionKeyMaterial.install()` itself rejects stale post-install results.
- [ ] Protected app/Navigator/provider resources are session-scoped and security destruction does not depend on a later frame.
- [ ] Unsupported platforms cannot pass a screen-protection gate while being described as protected; native claims are supported by native evidence.
- [ ] Stage 3/4 cryptographic meaning is unchanged.
- [ ] Stage 6 encrypted application-data persistence is not falsely claimed as implemented.
- [ ] Flutter analysis and test commands were actually executed in the complete project; output/exit codes are recorded.
- [ ] Every test/claim has an honest evidence status and remaining blockers are disclosed.

---

#### 11. Broader audit-priority register from `WORKFLOW.md` (not all part of Stage 5)

The original `WORKFLOW.md` scored pre-release findings by **Security Priority** and **Implementation Effort**. These are the original ratings, not new ratings from this source pass. The table preserves the planning history while separating Stage 5 status from deferred work.

| # | Finding in the original workflow | Priority / effort | Current source disposition |
|---|---|---:|---|
| 1 | Debug-signed release build | 9 / 2 | **NOT VERIFIED** — Android Gradle/signing files are absent from `Rocen-P5-repair-2.zip`. Must be checked in the complete release project before shipping. |
| 2 | Master-key architecture (verifier/key reuse, no independent MK, password-change burden) | 9 / 8 | **SOURCE IMPLEMENTED in current architecture** — a random 32-byte MK is generated, separate password verifier and wrapping key paths exist, and password-change code validates that the key is unchanged. Runtime tests are unexecuted. |
| 3 | Fail-open root/hardening defaults | 6 / 1 | **PARTIAL / SOURCE REVIEWED** — `CryptoEngine.isDeviceRooted()` fails closed (`true`) on channel error. The older `_isHardened` symbol is absent in this source; platform/KDF behavior still needs full-project verification. |
| 4 | AAD binding for metadata tampering/ciphertext substitution | 7 / 4 | **NOT IMPLEMENTED as a note envelope in this phase** — protected note persistence is explicitly disabled; no AAD implementation is present in the reviewed `lib/` source. Deferred with approved data-envelope work. |
| 5 | AAD-based replay/rollback protection | 7 / 6 | **NOT IMPLEMENTED in this phase** — no note-envelope AAD/generation binding is present; this is not closed by Stage 5 session locking. |
| 6 | KDF parameters recorded in encrypted payloads | 6 / 5 | **PARTIAL BY DATA TYPE** — password/recovery wrap JSON records `v`, `kdf`, `memory`, `iterations`, `salt`, `nonce`, `ct`, and `mac`; it accepts only the fixed approved profile. A persistent note ciphertext envelope remains deferred. |
| 7 | `publishNewState` monotonicity check | 5 / 2 | **LEGACY SYMBOL ABSENT / EQUIVALENT NEEDS REVIEW** — current source uses `_publishRotationAtomically`, derives the next generation from the observed remote generation, and optionally checks `expectedGeneration`. Do not treat the old finding as closed without reviewing this replacement path and its conflict tests. |
| 8 | ProGuard/R8 rules | 6 / 3 | **NOT VERIFIED** — build files/rules are absent from the source archive. |
| 9 | Hive encryption at rest | 7 / 6 | **NOT DONE for protected application data / persistence disabled** — `database.dart` makes note/task persistence unavailable; this is not equivalent to encrypted Hive. Review other persisted metadata separately in the storage phase. |
| 10 | Screenshot/recording protection scope | 6 / 3 | **PARTIAL / BLOCKED** — session activation checks screen-security status, but `unsupportedPlatform` currently satisfies policy and native enforcement is absent from the archive. |
| 11 | Payload-size limit before JSON decode | 4 / 2 | **NOT EVIDENCED** — `_decodeResponseJson` directly calls `jsonDecode(response.body)`; no size cap is visible at that boundary in the reviewed source. Recheck the complete transport implementation. |
| 12 | `android:allowBackup=false` | 5 / 1 | **NOT VERIFIED** — Android manifest is absent from this archive. |
| 13 | Stable `deviceId` in shared `password_state.json` | 4 / 3 | **STILL PRESENT IN THE CURRENT SCHEMA** — `PasswordStateDevice` includes `deviceId`, and state serialization includes device identifiers. This broader metadata/privacy item is not solved by the Stage 5 authority-write gate. |
| 14 | Zero plaintext/intermediate buffers in `crypto_isolate.dart` | 3 / 2 | **PARTIAL / NEEDS SEPARATE REVIEW** — source explicitly zeroes some key buffers; this Stage 5 pass does not establish that every plaintext/intermediate buffer is cleared. |
| 15 | `amendSync` silent delete/rename failure | 4 / 3 | **LEGACY ITEM NOT VERIFIED AGAINST CURRENT API** — `amendSync` is absent by name in this source archive. Identify the equivalent current sync behavior before marking fixed or still applicable. |
| 16 | Native plugin redirect / `FLAG_SECURE` uncertainty | 3 / N/A | **NOT VERIFIED** — the needed native/plugin source is not present in the archive. Must be handled through full platform source or vendor evidence. |
| 17 | Biometrics, `SECURITY.md`, backup SPKI pin, logging-name hygiene | 2–3 / 2–4 | **GENERAL HARDENING BACKLOG** — not certified complete in this Stage 5 review. |

These broader items must not be silently folded into a Stage 5 “done” claim. Some are deferred by architecture (notably the Stage 6 ciphertext envelope); others require the complete Android/iOS project or a separate security pass.

---

#### 12. Final position

Rocen Stage 5 has meaningful architecture present in source: epoch-bound session tokens, internal activation transactions, transaction-scoped candidate-key ownership, checkpointed unlock/activation, reserved GitHub path guards, private password-state mutation methods, and session-owned UI/provider resources.

That is progress, not completion. The latest reviewed source still has the confirmed grant-leakage and bootstrap-fencing blockers, bootstrap cleanup/reset issues, and a screen-security policy inconsistency. Runtime validation has not been performed. The next authority on status is the next actual source archive plus executed test evidence—not the current implementor's report.

---

## Appendix C — Current Stage 5 Workflow & Handoff

<!-- Original source filename: Current Stage 5 Workflow.md -->
<!-- Original SHA-256: bfe3d862a274932bed65d95be023d4b5efd69222290b24780f563e1c5de39d97 -->

### ROCEN — Current Stage 5 Workflow & Handoff

**Status date:** 10 October 2026  
**Last reviewed source baseline:** `Rocen-P5-repair-2.zip`  
**Phase status:** **Stage 5 architecture repair in progress; not approved complete.**  
**Current repair focus:** GitHub authority-grant leakage, operation-scoped bootstrap fencing, bootstrap cleanup, and reset restrictions.  
**Runtime evidence:** no Flutter/Dart tests or analysis have been executed against the reviewed baseline.

This document merges `current.md` and `current(1).md` into one operational handoff. It records how work is performed, what the active repair is, who must do what next, and what evidence is required. It is not an implementation proof; inspect the latest source archive after each repair.

---

#### 1. Canonical workflow

```text
Developer supplies current complete source/baseline
        ↓
Source-review AI inspects actual files and docs
        ↓
Auditor 1 and Auditor 2 independently inspect / challenge findings
        ↔ compare attack paths, root causes, and proposed remedies
        ↓
Prompt-review AI consolidates only verified/current findings
        ↓
Implementor AI changes code and tests (no scope restart)
        ↓
Implementor returns changed-file list, archive, and evidence report
        ↓
Independent source audit compares claims with actual source/diff
        ↓
Developer runs Flutter/Dart validation in full project environment
        ↓
Review failures; fix underlying defects; rerun commands
        ↓
Update this workflow handoff and `Phase Stage - 5.md`
        ↓
Only then decide whether Stage 5 gate is satisfied
```

The implementor is not the final authority on its own security. Auditor consensus is a finding/recommendation, not a substitute for checking source. A source archive is the implementation baseline; tests in files do not prove they ran; static assertions do not prove runtime behavior.

#### 2. Who is responsible for what

- **Developer:** supplies the authoritative project tree, decides product policies (including supported screen-security platforms), runs the real toolchain, preserves logs and approves phase transitions.
- **Source-review AI:** verifies claims against files/line ranges; separates confirmed defects from uncertainty and out-of-scope backlog.
- **Auditor 1 / Auditor 2:** independently find and challenge architecture flaws, bypasses, race conditions, and test/evidence gaps; they should challenge each other's assumptions rather than merely duplicate reports.
- **Prompt-review AI:** merges agreed, source-backed findings into a targeted prompt. Prefer a narrow repair directive over repeatedly expanding the prompt with unrelated security backlog.
- **Implementor AI:** implements the agreed repair, updates affected tests, returns the actual changed files and source archive, and clearly labels checks it could and could not run.
- **Final verifier:** independently inspects the returned archive and executes validation in a complete Flutter environment.

#### 3. Current baseline and evidence limits

The latest reviewed archive is `Rocen-P5-repair-2.zip`. The implementor reported Tree-sitter parsing and Python checks, but did not have Dart/Flutter available. Therefore:

| Verification | Baseline status |
|---|---|
| Source presence / code inspection | Reviewed for the items recorded in `Phase Stage - 5.md` |
| Tree-sitter syntax pass | Reported by implementor; not equivalent to Dart compilation |
| Python/static source assertions | Reported by implementor; not runtime tests |
| `flutter pub get` | Not executed in the reported environment |
| `flutter analyze` | Not executed |
| `flutter test --reporter expanded` | Not executed |
| Checkpoint-enabled race suite | Not executed |
| Native Android/iOS screen-security implementation | Not present in the repair archive; not verified |

The repair ZIP includes `lib/`, `test/`, and `pubspec.yaml`, but is not a complete runnable mobile project: it omits `assets/logo.png` referenced by the manifest and native Android/iOS source directories. Use the complete project working tree or a complete archive for actual build/test validation. Do not treat missing archive content alone as a source-code failure.

#### 4. What the current implementation has already put in place

The following structures are present in the last-reviewed source and should be preserved unless a new source finding proves otherwise:

- `SessionSecurityManager` state machine and non-forgeable epoch-bound `SessionAuthorizationToken`.
- Library-private `_ActivationTransaction` and controlled ownership of temporary activation material.
- Immediate stale check after MK unwrap plus defensive stale adoption/clearing.
- One-way transfer of session key material into `SessionKeyMaterial` and an internal stale-generation check after `AFTER_SESSION_INSTALL`.
- Seven named activation checkpoints A–G plus the additional `duringMkUnwrap` seam.
- Compile-time checkpoint controls intended to be off in ordinary production builds and enabled explicitly for race tests.
- No public `associateRemoteForTesting()` or `changePasswordForTesting()` mutation method in this baseline.
- `PasswordStateManager` mutation implementation moved into the trusted production-service library as private methods.
- Generic GitHub write methods reject normalized/malformed reserved security-authority paths.
- Session-scoped `ProtectedSessionApp`/Navigator and `ProtectedSessionResources` with root ProviderContainer registered for synchronous destruction.
- Fail-closed protected application-data persistence gate while Stage 6 envelope/storage remains unimplemented.

These are source observations, not test passes.

#### 5. Current blocking findings

##### Blocker 1 — Grant leakage / insufficient grant scope

`GithubBackupService` is currently subclassable. The production service can pass a real `GithubAuthorityWriteGrant` into overridable public authority-writing methods. A caller-controlled subclass can capture it. The grant checks only its fence; it is not bound to a permitted path set/mutation/operation lifetime. A private constructor alone is insufficient.

##### Blocker 2 — Bootstrap fence is stateless

`_PreSessionFence` delegates to `requirePreSession()`, which accepts both `BOOTSTRAP` and `LOCKED`. It does not capture the specific authorized bootstrap operation's generation/epoch. Old setup/recovery work can therefore pass a state-only check after `lockSync()`.

##### Related blocker 3 — Bootstrap routing is too broad

`main.dart` calls `finishBootstrap()` when state is `BOOTSTRAP` without basing the transition on distinct no-authority, valid-authority, and corrupt-authority outcomes. `establishFirstDevice()` has an existing-local-record branch that can restore authority and call remote association under the pre-session fence. Bootstrap/recovery entry points must not become privilege-free routes for an established locked account.

##### Related blocker 4 — Bootstrap cleanup and test resets

`lockSync()` takes an early return in `BOOTSTRAP` without running `_runCleanupCallbacks()`. `SessionSecurityManager.resetForTesting()` remains public, resets the epoch to zero, and returns to `BOOTSTRAP`; `MasterKeyManager.resetForTesting()` is also public. These test controls are currently accepted by a static audit but still affect production-visible security lifecycle state.

##### Related blocker 5 — Screen security policy

`ScreenSecurity.satisfiesPolicy()` currently returns true for `unsupportedPlatform`, despite the enum and docs saying protection is not enforced there. The native implementation cannot be audited from the current ZIP. The platform support/fail-closed policy needs an explicit decision and correction.

##### Verification blocker 6 — No runtime evidence

The reviewed source has not been compiled/analyzed or tested under Dart/Flutter. The active repair prompt must preserve source-level and test evidence honesty.

The detailed source references and acceptance criteria are in `Phase Stage - 5.md`.

#### 6. Current repair instruction / expected next implementation

The active implementor instruction is a focused continuation from `Rocen-P5-repair-2.zip`; it is not a Stage 5 restart. The repair must:

1. Stop authority grants crossing caller-controlled overridable service methods.
2. Bind each grant to its intended operation, permitted path/mutation set, current fence, and limited lifetime; reject unrelated/replayed use.
3. Replace grant-capturing test subclasses with a transport-level test arrangement that does not expose production grants.
4. Introduce explicitly eligible, operation-scoped bootstrap authority/fencing tied to a monotonic generation/epoch.
5. Invalidate bootstrap permits synchronously on `lockSync()` and reject stale work after every relevant await and before each protected side effect.
6. Make first-run setup/recovery distinct from an established locked account and corrupt authority; preserve legitimate first-run recovery.
7. Run sensitive-input cleanup callbacks synchronously when a lock happens during bootstrap.
8. Restrict `resetForTesting()` controls to the real test arrangement and avoid fixed-value freshness epoch resets.
9. Preserve existing activation transaction ownership, all seven checkpoints, reserved path rules, session-owned UI/provider resources, and Stage 3/4 cryptographic meaning.
10. Update deterministic tests, static audits, source report, and evidence inventory.

Do not claim this repair is already complete. No later archive has been independently inspected here.

#### 7. Immediate next steps after the implementor returns

##### Step 1 — Inspect actual source and diff

Compare the changed-file list with the archive. Review `github_backup_service.dart`, `master_key_production_service.dart`, `session_security_manager.dart`, `master_key_manager.dart`, `main.dart`, and the affected tests. Confirm the grant cannot be captured through an override; confirm grants are operation/path scoped; confirm bootstrap permits expire after lock; confirm locked-existing and corrupt-authority cases cannot enter bootstrap mutations; confirm bootstrap lock runs cleanup; confirm resets cannot reopen bootstrap or cause an ABA freshness issue.

##### Step 2 — Run validation in the complete project directory

In Windows PowerShell, from the directory containing the complete project's `pubspec.yaml`:

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true --reporter expanded
```

Capture the full output and exit code for each command. If the first command fails because files/assets are missing, move to the complete project tree instead of diagnosing an incomplete ZIP as a code failure.

- Normal `flutter test` must validate that checkpoint controls are inert in normal mode.
- The define-enabled invocation must actually execute deterministic pause/resume tests; skipped race tests do not count as passed.
- Resolve genuine compile/runtime/test failures without deleting or weakening security assertions.

##### Step 3 — Review test coverage and evidence

Require deterministic tests for grant leakage/reuse/path restrictions, bootstrap lock during local/remote awaits, existing-local-record recovery refusal/routing, stale bootstrap permit rejection, synchronous cleanup, and test reset isolation. Preserve A–G and H unwrap/adoption tests.

Use exactly one status per required test:

- `EXECUTED AND PASSED`
- `EXECUTED AND FAILED`
- `NOT EXECUTED — runtime unavailable`
- `SOURCE-REVIEWED ONLY`

##### Step 4 — Update the handoff

After the source audit and runtime commands, update both `Phase Stage - 5.md` and this workflow file with the new source archive identity, exact files changed, concrete test results, remaining blockers, and next action. Do not copy implementor claims as facts without verifying them.

#### 8. Current security review backlog outside this repair

The broad audit in `PROMPT.md` and the priority sequence in `WORKFLOW.md` include additional pre-release work that is not closed by the current Stage 5 repair. Track separately:

- Stage 6 encrypted note/application-data envelope and any required AAD/anti-rollback design; note/task persistence is currently disabled.
- Android release signing, backup policy, ProGuard/R8 rules, and native screen protection; current archive lacks native/build files needed for verification.
- Payload limits for untrusted remote JSON, device metadata minimization, `amendSync` failure surfacing, memory-copy hardening, supply-chain/signing checks, and other findings from the full security audit.
- The Changelog/source mismatch where the change log says the uppercase/lowercase same-letter restriction was removed, but the current `CryptoEngine.isPasswordComplexityValid()` still enforces it.

These must not be silently labelled fixed. They are outside the active repair unless explicitly brought into scope by the developer.

#### 9. Decision rule

**No Stage 5 completion decision based on a prompt, audit consensus, changelog, static parse, or test files alone.** The next source archive must pass independent source review, and the complete-project Flutter/Dart checks must actually run. Stage 5 remains **IN PROGRESS / NOT APPROVED** until the source, tests, and evidence satisfy the completion gate in `Phase Stage - 5.md`.

---

## Appendix D — Stage 5 Architecture & Security Handoff

<!-- Original source filename: Stage 5 Architecture & Security Handoff.md -->
<!-- Original SHA-256: c384fb5975a5294cec8f5f0b5f5db3b1f74e2e3689be91d0d747e2b76c52d413 -->

### ROCEN — Stage 5 Architecture & Security Handoff

**Document type:** Developer / AI handoff and living Stage 5 security status record  
**Current baseline:** `Rocen-P5.zip`  
**Last audited baseline:** 2026-10-08  
**Status:** **Stage 5 architecture repair in progress — NOT COMPLETE**

---

#### 1. Purpose of this document

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

#### 2. Source/evidence hierarchy

When different artifacts disagree, use this order of authority:

1. **Current Rocen source tree / latest ZIP** — implementation truth.
2. **Current test tree** — evidence of intended assertions and test coverage, but not proof of execution unless runtime output exists.
3. **Security architecture/design documents** — intended architecture and security reasoning.
4. **Implementor AI reports** — implementation claims that must be checked against source.
5. **Auditor AI reports** — security findings and recommendations that must also be checked against source.
6. **This handoff document** — project/status memory and workflow record.

An AI report never overrides the actual source.

---

### 3. Development workflow being used

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

##### Why the workflow is structured this way

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

### 4. Stage 5 security goal

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

### 5. What has already been implemented in the current Stage 5 work

The current `Rocen-P5.zip` manifest records:

- **14 new files**
- **10 modified files**
- **29 unchanged files**
- **1 project/configuration change entry**

The current tree contains 55 files in the ZIP.

#### 5.1 Session state/security layer

The current implementation includes a Stage 5 session state machine in:

`lib/core/session_security_manager.dart`

with the intended states:

- `bootstrap`
- `locked`
- `unlocking`
- `activating`
- `unlocked`

The source comments describe lifecycle interruption as returning to `LOCKED` and explicitly state that resume does not silently recreate an authenticated session.

#### 5.2 Session authorization capability

`SessionAuthorizationToken` exists in `session_security_manager.dart`.

Its current source shape has:

- private constructor,
- epoch-bound state,
- creation controlled by `SessionSecurityManager`.

The intended purpose is authorization of ordinary authenticated-session operations, separate from key ownership.

#### 5.3 Activation transaction

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

#### 5.4 Deterministic checkpoint system

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

#### 5.5 Session key material

The current ZIP adds:

`lib/core/session_key_material.dart`

This component is intended to own live MK/NEK/TEK material during the live session.

Its `install()` path includes generation-based stale checks and the `AFTER_SESSION_INSTALL` boundary.

**Current status:** important stale-result fencing exists, but the lifetime of temporary key objects across suspended async derivation still requires architectural repair. See Section 8.

#### 5.6 Session unlock path

The current ZIP adds:

`lib/core/session_unlock_service.dart`

The production password unlock path now uses the real password → local authority → authentication → MK unwrap sequence rather than relying on a fabricated authentication seam for the Stage 5 race path.

The source contains the required password/MK checkpoint locations.

#### 5.7 MasterKeyManager custody refactor

`lib/core/master_key_manager.dart` was modified to move away from long-lived live MK custody.

The target responsibility is now control/state/serialization/authority decisions rather than acting as a persistent live-key cache.

This is a major architectural improvement over the earlier design.

#### 5.8 Domain-key derivation

`lib/core/domain_key_derivation.dart` was modified in the Stage 5 branch while preserving the Stage 4 domain-key derivation model.

Stage 5 must continue to preserve the established derivation semantics and frozen vectors.

#### 5.9 UI/session entry points

The current ZIP adds:

`lib/features/lock_screen.dart`

and modifies:

`lib/main.dart`
`lib/navbar.dart`
`lib/features/settings.dart`

The navigation representation has been moved toward a data-only model rather than retaining long-lived Widget instances inside navigation state.

#### 5.10 Session/security tests

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

### 6. Files changed in the current `Rocen-P5.zip`

#### 6.1 New production files

```text
lib/core/activation_transaction.dart
lib/core/security_checkpoints.dart
lib/core/session_key_material.dart
lib/core/session_security_manager.dart
lib/core/session_unlock_service.dart
lib/features/lock_screen.dart
```

#### 6.2 Modified production files

```text
lib/core/domain_key_derivation.dart
lib/core/master_key_manager.dart
lib/core/master_key_production_service.dart
lib/features/settings.dart
lib/main.dart
lib/navbar.dart
```

#### 6.3 New test files

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

#### 6.4 Modified test files

```text
test/domain_key_derivation_test.dart
test/master_key_manager_test.dart
test/master_key_production_service_test.dart
test/widget_test.dart
```

#### 6.5 Unchanged but relevant production files

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

### 7. What the implementor AI reported vs. what the latest ZIP actually proves

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

### 8. Verified security blockers discovered in the latest ZIP

These are the main problems the current repair pass is intended to solve.

#### 8.1 Public authorization-free security mutations

Current source still exposes:

```text
associateRemoteForTesting()
changePasswordForTesting()
```

They are publicly reachable.

A name such as `ForTesting` is not an access-control boundary.

##### Required fix

Remove these public production security-mutation methods entirely.

Stage 3 tests must instead target genuinely lower-level cryptographic/mechanical primitives that do not themselves constitute an unauthorized Stage 5 security mutation.

No public replacement may be introduced.

---

#### 8.2 ActivationTransaction is still public

Current source defines a publicly constructible:

```dart
class ActivationTransaction {
  ActivationTransaction(...)
}
```

##### Required fix

Make it an internal implementation detail.

Ordinary application/feature code must not be able to construct the real production activation transaction.

Do not widen production visibility merely to make unit tests easier.

---

#### 8.3 Unwrap → adopt stale race

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

##### Required fix

1. Check transaction freshness immediately after unwrap returns.
2. Make `adoptCandidateMk()` itself defensive and reject an already-stale transaction.
3. Clear/dispose the rejected incoming candidate rather than retaining it.

---

#### 8.4 Suspendable activation secrets are not all synchronously controllable

Temporary `SecureBytes` objects can exist as async locals during NEK/TEK derivation.

Generation checks can reject stale completion, but generation fencing is not the same as synchronous secret-lifetime control.

##### Required fix

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

#### 8.5 changePassword durable-write fencing

Entry-time and queue-time authorization checks are not sufficient when an operation has additional awaits before durable mutation.

A lock can occur during KDF/read/other asynchronous work.

##### Required fix

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

#### 8.6 associateRemote durable-write / remote-start fencing

The same issue exists for `associateRemote()`.

##### Required fix

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

#### 8.7 Protected application / Navigator is not genuinely session-scoped

The current ZIP still has a persistent outer `MaterialApp` with its Navigator.

`ProtectedAppRoot` is a subtree rather than the actual session-owned application/navigation boundary.

That means protected `Navigator.push/pop` operations resolve through the permanent app-level navigation context unless explicitly redesigned.

##### Required fix

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

#### 8.8 ProviderContainer is not synchronously destroyed by lockSync()

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

##### Required fix

Create explicit session-resource ownership reachable from `lockSync()`.

`lockSync()` must be able to synchronously invalidate/destroy/detach the privileged session ProviderContainer and associated security resources.

Flutter's later widget rebuild is only visual cleanup.

---

#### 8.9 ACTIVATING resources must also be synchronously destructible

The current architecture can create session resources during activation before the normal unlocked-session teardown registration is fully established.

##### Required fix

As soon as protected resources are created during activation, register them with an explicit cleanup owner reachable by `lockSync()`.

The activation state must never contain a protected resource whose destruction depends solely on later widget disposal.

---

#### 8.10 Bootstrap/first-run flow remains incomplete

The current architecture can leave first-run setup in a bare Settings screen instead of cleanly entering the standard session lifecycle.

##### Required fix

Preserve the approved credential model:

```text
existing cryptography password
    =
Stage 5 session-unlock credential
```

After first-device establishment, the application must enter the normal Stage 5 security lifecycle without requiring a restart simply to enter the protected session model.

---

#### 8.11 recoverFromRemote() requires complete scope analysis

The current call graph suggests it is used for pre-session initialization/recovery.

That may be valid.

But the public API should be narrowed if the actual architecture is bootstrap-only, and the full race/await/durable mutation path must still be traced.

Do not add a session token solely to satisfy a checklist if doing so would make legitimate pre-session recovery impossible.

---

#### 8.12 Native screenshot protection is not verified in the current archive

The ZIP contains Dart MethodChannel integration but no native Android/iOS implementation that can be independently verified in this archive.

Therefore the project must not claim OS-level screen capture protection as implemented.

The final report must accurately distinguish:

```text
Dart hook present
native implementation unavailable/unverified
```

from actual verified native enforcement.

---

### 9. Current architecture: intended repaired direction

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

### 10. Planned/current repair files

The exact set may expand if source review reveals a stronger architecture is necessary. The likely files involved are:

#### Production files expected to be repaired

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

#### Tests expected to be rewritten/updated

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

### 11. How the current security bugs are being fixed

#### 11.1 Public mutation bypass

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

#### 11.2 Stale transaction / key ownership

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

#### 11.3 Temporary secret ownership

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

#### 11.4 Durable mutation fencing

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

#### 11.5 UI/provider session destruction

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

### 12. Deterministic checkpoint test plan

The seven mandatory tests remain the primary race proof.

#### A — AFTER_PASSWORD_AUTH

```text
pause
→ lockSync()
→ release
→ immediate freshness failure
→ no MK recovery continuation
→ LOCKED
```

#### B — AFTER_MK_UNWRAP

```text
pause
→ lockSync()
→ release
→ freshness failure
→ acknowledgeRecoveredAuthority() does NOT execute
→ no stale authority mutation
→ LOCKED
```

#### C — AFTER_NEK_DERIVATION

```text
pause
→ lockSync()
→ release
→ freshness failure
→ TEK derivation does NOT continue
→ LOCKED
```

#### D — AFTER_TEK_DERIVATION

```text
pause
→ lockSync()
→ release
→ freshness failure
→ installation does NOT begin
→ LOCKED
```

#### E — BEFORE_SESSION_INSTALL

```text
pause
→ lockSync()
→ release
→ freshness failure
→ install() does NOT begin
→ LOCKED
```

#### F — AFTER_SESSION_INSTALL

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

#### G — BEFORE_ACTIVATION_COMMIT

```text
pause
→ lockSync()
→ release
→ freshness failure
→ ACTIVATING cannot commit
→ LOCKED
```

Additionally required:

#### H — unwrap/adoption race

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

### 13. Authorization test plan

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

### 14. Ownership audit plan

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

### 15. Async secret-retention audit plan

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

### 16. Bootstrap / corrupt authority rules

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

### 17. Screenshot-control status

Current ZIP status:

```text
Dart MethodChannel integration: present
Native Android/iOS implementation: absent in archive
OS-level screenshot enforcement: unverified
```

Therefore no documentation may claim native screenshot prevention is implemented until the native source exists and is independently verified.

---

### 18. Runtime/evidence policy

Because the current implementor environment has reported Flutter/Dart unavailable, the project must distinguish:

##### A. EXECUTED AND PASSED

Flutter/Dart command actually executed and succeeded.

##### B. EXECUTED AND FAILED

Flutter/Dart command actually executed and failed.

##### C. NOT EXECUTED — runtime unavailable

Test exists but could not be run because the required runtime was unavailable.

##### D. SOURCE-REVIEWED ONLY

Correctness supported by source inspection/hand trace but not runtime execution.

Python regex/source-order checks are **not** Flutter/Dart runtime execution.

---

### 19. Current implementation status matrix

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

### 20. Completion gate for this phase

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

### 21. Rules for future AI implementors

Future implementor AIs should follow these rules:

##### Rule 1 — Source beats report

Never assume a previous AI report is correct. Inspect the current source.

##### Rule 2 — Security architecture beats naming

A method named `ForTesting`, `internal`, `core`, or `testOnly` is not automatically safe.

##### Rule 3 — Preserve cryptographic meaning

Do not change Stage 3/4 cryptographic semantics to solve Stage 5 lifecycle problems.

##### Rule 4 — Do not weaken production security for tests

Make tests reach lower-level primitives or use internal arrangements, rather than shipping public bypasses.

##### Rule 5 — A final-state check is not enough

A test that only proves `LOCKED` after a race does not prove where stale work stopped.

##### Rule 6 — Epoch fencing is not secret zeroization

Rejecting a stale result is different from synchronously controlling the lifetime of the secret used to produce it.

##### Rule 7 — Flutter visual teardown is not a security primitive

Security/resource destruction must not depend on a later frame.

##### Rule 8 — Do not overclaim runtime evidence

Source inspection is not the same thing as executing Flutter/Dart tests.

##### Rule 9 — Challenge the architecture

If a stronger security architecture is warranted, the implementor should say so and implement it, as long as Stage 3/4 cryptographic meaning, credential semantics, persistent data format, and scope are preserved.

##### Rule 10 — Fix before expanding

Do not add unrelated Stage 5 features while security architecture blockers remain open.

---

### 22. Immediate next step

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

### 23. Change history / review trail

#### Stage 5 design baseline

The Stage 5 architecture documents established:

- LOCKED/UNLOCKING/ACTIVATING/UNLOCKED semantics,
- transactional unlock/rollback,
- session-scoped provider/UI lifetime,
- lockSync destruction ordering,
- generic crypto denial while locked,
- lifecycle locking,
- provider/navigation isolation,
- no Stage 6 migration during this stage.

#### Ownership correction

Earlier implementation was identified as effectively having more than one live MK holder.

The architecture was changed toward:

```text
MasterKeyManager = authority/control
ActivationTransaction = temporary activation owner
SessionKeyMaterial = live authoritative session owner
```

#### Checkpoint correction

The initial checkpoint implementation could only prove the eventual unlock would fail.

The design was strengthened so stale checkpoint resumption is immediately rejected.

#### Authorization correction

An earlier authorization policy accepted arbitrary caller-provided logic and exposed a public no-op form.

That was identified as a structural bypass.

The target design now uses the real epoch-bound `SessionAuthorizationToken`.

#### Current repair correction

The latest ZIP then showed that public `ForTesting` mutations still existed, and that UI/provider/session resource lifetime was not yet fully isolated.

The project is therefore currently in another targeted architecture-repair cycle.

---

### 24. Final status statement

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

---

## Appendix E — Changelog

<!-- Original source filename: CHANGELOG.md -->
<!-- Original SHA-256: 4da3dd849e4eebda49c90d924517966af758532c7fa9b7bb257ffb253dfb32e2 -->

### Changelog

#### [0.4.0-alpha] — Code Quality, Sync Safety, Recovery UX & Clipboard Media Overhaul

This release fixes analyzer-flagged code issues across several screens, closes a gap where syncing from GitHub could pull down and expose internal security files, resolves a case where an interrupted password change could leave the app permanently unable to complete a new password change, and adds full video support alongside a rebuilt zoom/rotation/edit/crop workflow in Clipboard's full-screen media viewer.

##### Code Quality

- Resolved all outstanding `flutter analyze` warnings across `quicknote.dart`, `bookmarks.dart`, `clipboard.dart`, and `ideainbox.dart`:
  - Wrapped single-statement `if` bodies in braces per `curly_braces_in_flow_control_structures`.
  - Replaced deprecated `Color.withOpacity()` calls with `Color.withValues(alpha: ...)` throughout.
  - Migrated deprecated `Share.shareXFiles(...)` calls to `SharePlus.instance.share(ShareParams(...))`.
  - Removed an unnecessary `dart:typed_data` import already covered by `flutter/services.dart`.
  - Added `mounted` / `context.mounted` guards after `await` calls flagged by `use_build_context_synchronously`, ensuring dialogs and snackbars are never shown against a disposed `BuildContext`.

##### GitHub Sync Safety

- Excluded `password_state.json` from the file list processed during a pull/refresh from GitHub, alongside the existing `device_key.json` exclusion, so neither internal security file can be surfaced to the user as a note, edited, or deleted through the notes UI.
- Confirmed the local title-uniqueness check (`titleExists`) only ever reads local device state and performs no GitHub lookup, so duplicate-title checks stay fully offline.

##### Recovery & Password Change

- Fixed a case where cancelling the recovery-phrase step mid-password-change would leave the device correctly on the new password, but permanently unable to start another password change — the app would only show a dead-end **"PASSWORD CHANGE UNAVAILABLE"** dialog.
- Added a **CONTINUE** action to that dialog for this specific case, which re-prompts for the 12-word recovery phrase and, if accepted, finishes the interrupted change: re-wrapping and re-uploading `device_key.json` and confirming the pending password state with GitHub.
- Before finishing an interrupted change, the app re-checks `password_state.json` on GitHub first — if another device has since changed the password or the remote state otherwise disagrees, the existing reconciliation messaging is shown instead of publishing over it.
- Increased the height of each word box in the 12-word recovery-phrase dialogs (entry and display) from a cramped 6-words-per-row, 2-row layout to a 3-words-per-row, 4-row layout, without changing the dialog's width, so longer BIP-39 words are no longer clipped.
- Increased the font size of the words shown in the "write these down" recovery-phrase display dialog from 9 to 12 for better readability.
- Preserved all existing brutalist/minimal dialog styling (borders, spacing, button treatment) across these changes.

##### Clipboard: Image + Video Support

- Clipboard's gallery and import pickers now request and accept both images and videos, not images only.
- Gallery and imported-media grids show a small play-icon overlay on video thumbnails.
- Added a full-screen video player (play, pause, seek via a scrubbable progress bar) using `video_player`, replacing the broken `Image.file` attempt on video files in the imported grid.
- Fixed video playback flicker on play/pause/replay: the video controller's `Future` was being recreated on every rebuild, which repeatedly bounced `FutureBuilder` back to its loading state; the future is now cached per item so this no longer happens.
- Fixed the video progress bar rendering mid-video instead of above the toolbar, and set its color to theme-aware black/white instead of the package's default red.
- Added ROTATE support for video (rotates only the video content, not the fixed controls), automatically hidden while that video is actively playing so it's never tappable mid-playback.

##### Clipboard: Full-Screen Viewer, Zoom, Rotation & Toolbar

- Added double-tap zoom that anchors at the exact tap location (previously it always zoomed from a fixed corner regardless of where the user tapped).
- Zoom now bounces 1x → 2x → 3x → 2x → 1x on repeated double-taps, replacing an earlier wrap-around cycle.
- Manual pinch-to-zoom and the normal action toolbar's visibility are mutually exclusive, as originally specified; single-tap now fully blocks page-swipe navigation whenever the toolbar is hidden.
- Fixed the normal action toolbar to an exact 64px height with SHARE-EDIT-LIKE-BIN-COPY in five evenly divided slots, with safe-area inset handled as separate space outside that 64px rather than inflating it.
- Added image rotation (0°→90°→180°→270°→0°) that rotates only the media content; fixed navigation controls and toolbars never rotate.
- Fixed a gallery/imported-media loading performance issue: the app previously fetched every asset in the library in one call, taking 10-15+ seconds on a library of 3000+ photos and 500+ videos, and re-doing the same full fetch on every manual refresh. Loading is now windowed (90 assets per page), with more pages fetched automatically as the grid is scrolled near its end.
- Added a fast thumbnail-first display in the full-screen image viewer: the already-cached grid thumbnail shows instantly while the full-resolution file decodes in the background and fades in.

##### Clipboard: Copy to Clipboard

- Implemented real system-clipboard image copying via `super_clipboard`, replacing the earlier non-functional attempt.
- Diagnosed and fixed the Android integration gap that made COPY silently do nothing while still showing a "COPIED" confirmation: the app's `minSdkVersion` was below `super_clipboard`'s required minimum of 23, and the required `super_native_extensions` content provider was missing from `AndroidManifest.xml`. Both are now correctly configured.
- COPY shows a brief "COPIED" notice (~500ms, auto-dismissing) only after a real clipboard write succeeds; genuine failures are reported honestly rather than shown as success.

##### Clipboard: Crop

- Added interactive image cropping: a draggable, resizable crop rectangle with a handle on all four corners (previously only the bottom-right corner was resizable, and dragging the rectangle itself only worked when grabbing its exact border pixels rather than anywhere inside it).
- Fixed cropped images never appearing anywhere — not in the app, not in the device's file manager — despite the save reporting success. The original implementation wrote into the device-gallery asset's own plugin-managed cache directory, which is volatile, private, and not something other tools can see. Cropped images are now saved through `saver_gallery` into the device's public Pictures/Rocen album via MediaStore, exactly like a normal saved photo.
- Fixed a crop-quality bug where repeatedly re-cropping an already-cropped image would leave a visible black gap between the photo and its frame, most noticeable on small images: the crop overlay's sizing was locked in from its very first layout pass and never recalculated; it now recalculates until the user starts actively dragging, and rotation-aware sizing is now computed explicitly rather than relying on implicit widget layout behavior.
- Fixed a black-screen flicker when opening the crop tool: the image dimension lookup was being redone from scratch on every rebuild and briefly hid the photo behind a blank loading screen; it's now computed once, and the photo stays visible with a small spinner while it resolves.
- Added a "DONE" confirmation notice after a successful crop, matching the existing "COPIED" notice style.
- Repositioned the crop confirm/cancel buttons and the edit toolbar's CROP control, which the 64px toolbar change had left overlapping the crop image and, in some cases, floating mid-image instead of just above the toolbar.
- CROP remains visibly disabled and non-interactive for video, per the original design.

##### Android Configuration

- Added the `READ_MEDIA_VIDEO` permission so video assets are genuinely returned after permission approval, alongside the existing `READ_MEDIA_IMAGES` and `READ_MEDIA_VISUAL_USER_SELECTED` permissions.
- Added the `super_native_extensions` content provider declaration required by `super_clipboard`, using the project's actual `applicationId`.
- Raised `minSdkVersion` to 23 via `flutter.minSdkVersion` in `local.properties`, the required floor for `super_clipboard`.
- Diagnosed and fixed an unrelated pre-existing build issue found during this work: a casing mismatch between `namespace` (`Rocen`) and `applicationId` (`rocen`) in `build.gradle.kts` was causing `ClassNotFoundException: MainActivity` on install; aligned both to lowercase `rocen` to match the Kotlin package folder and the app's existing channel-name convention.

##### Dependencies

- Added `video_player`, `image`, `super_clipboard`, and `saver_gallery` — no existing dependency covered video playback, pixel-level image cropping, or binary/gallery clipboard writes.

#### [0.4.0] — Security, Backup & UI/UX Overhaul

This release focuses on stabilizing GitHub backup setup, strengthening failure handling and diagnostics, refining password validation, and improving the settings interface.

##### Security & Cryptography

- Improved the first-time cryptographic password setup flow and its integration with the recovery-key system.
- Preserved the existing password hashing, key derivation, encryption, hardware binding, and secure-storage architecture while refining password validation behavior.
- Removed the **“NO SAME LETTER IN UPPER + LOWER”** password restriction.
  - The rule rejected passwords when the same alphabetic letter appeared in both uppercase and lowercase forms.
  - The restriction was removed from the displayed password requirements and from the actual password-validity checks.
  - All other password requirements remain in place.
- Kept the 12-word recovery phrase as part of the password recovery flow.
- Improved failure handling so unsuccessful GitHub setup does not leave a failed credential configuration treated as a completed backup setup.

##### GitHub Backup

- Fixed the first-time GitHub backup setup path for a completely empty repository.
- Fixed a critical first-time setup logic issue where the generated `device_key.json` was never marked as published, causing **“BACKUP SETUP FAILED”** to be shown even when setup had not actually been attempted.
- Connected the recovery phrase generation to the existing recovery-phrase display flow during first-time setup.
- Added the missing publish/verification flow for `device_key.json`.
- Added proper handling for an empty GitHub repository where the Contents API can return **HTTP 409** before the repository has its first commit.
- Allowed Rocen to initialize an empty repository through the GitHub Contents API instead of incorrectly treating the empty state as a backup failure.
- Preserved the existing recovery behavior for repositories that already contain `device_key.json`.
- Added safer repository-state tracking so the local repository ownership marker is established only after the device key is successfully prepared for the repository.
- Improved GitHub backup error handling for repository reads, writes, commits, trees, and branch references.
- Added operation-specific GitHub permission diagnostics for failures such as:
  - reading repository contents
  - creating `device_key.json`
  - creating Git trees
  - creating commits
  - creating/updating branch references
- Added handling for GitHub API rate-limit failures with a dedicated diagnostic message.
- Removed reliance on the `/user` authenticated-user endpoint during setup because Rocen does not need that unrelated endpoint to perform backup operations.
- Removed unnecessary metadata preflight assumptions from the core backup setup path so the app tests the repository operations it actually needs.
- Improved repository validation so the configured `owner/repository` path is checked consistently.
- Added clearer differentiation between repository access problems and contents read/write problems.
- Improved handling of default-branch resolution for repositories whose default branch is not `main`.
- Kept empty-repository initialization compatible with the existing GitHub backup architecture.

##### GitHub Request & Network Security

- Kept GitHub communication restricted to `https://api.github.com`.
- Preserved public-key/SPKI certificate pinning through the existing `smart_dev_pinning_plugin`.
- Fixed the custom pinned HTTP client so request data required by GitHub is passed correctly to the native secure client.
- Added an explicit `User-Agent` for GitHub API requests.
- Added explicit `Content-Type: application/json` handling for GitHub JSON requests.
- Corrected GitHub request construction for empty-repository initialization.
- Preserved UTF-8 request/response handling and Base64 processing used by the GitHub and cryptographic flows.
- Added the missing `dart:convert` import required by the pinning layer for Base64 and UTF-8 operations.
- Kept certificate-pinning behavior intact while improving request compatibility.

##### GitHub Diagnostics

- Reworked GitHub 403 diagnostics so the app reports which backup operation was denied instead of always showing a generic failure.
- Distinguished repository-access failures from contents read/write failures.
- Avoided presenting hardcoded permission information as though it came directly from GitHub when the custom pinning plugin does not expose response headers.
- Included the actual GitHub response body in diagnostics where appropriate so future authorization problems can be investigated from the server's returned message.
- Added clearer messaging for cases where GitHub can see a repository but denies a specific operation.

##### Settings & UI/UX

- Improved dialog typography across the settings interface.
- Dialog headlines remain bold.
- Dialog body text is displayed at regular weight rather than semi-bold.
- Preserved the existing button styling and other settings UI typography.
- Preserved the existing brutalist/minimal settings visual language while improving readability.
- Kept password requirement indicators, progress feedback, and recovery dialogs intact while adjusting the password-policy behavior.

##### Reliability & Code Quality

- Corrected several integration issues encountered while stabilizing the GitHub flow, including:
  - missing declarations for repository state fields
  - missing `dart:convert` imports
  - invalid bare `return;` statements in boolean-returning asynchronous logic
  - malformed string literals in diagnostics
- Kept the current working source files aligned after successful build/run/test validation.
- The final working configuration was verified by building and testing the app successfully.

##### Result

The release resolves the GitHub backup setup failure encountered during fresh installation with an empty repository, improves diagnostics for token/repository authorization failures, retains the secure pinned GitHub connection, simplifies the password policy by removing an unnecessary restriction, and refines settings dialog presentation.

---

## Appendix F — Deep Security Audit, Threat Analysis & Hardening Review Prompt

<!-- Original source filename: PROMPT.md -->
<!-- Original SHA-256: f3fcb7bd858edd97430b8893fcfa1d8dc6f081ec6d8c224ec0b61da09d8172e0 -->

### Rocen — Deep Security Audit, Threat Analysis & Hardening Review

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



### 1. First: Build the actual security model

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

 

### 2. Threat model

Explicitly evaluate protection against:

##### Attacker A — ordinary malicious app

A different non-root Android application attempts to access Rocen's files, logs, clipboard, intents, screenshots, etc.

##### Attacker B — filesystem/app-data extraction

An attacker obtains a copy of Rocen's local application data.

Determine exactly what that attacker receives and whether that data is sufficient to recover:

* notes
* titles
* passwords
* encryption keys
* GitHub tokens
* recovery material

##### Attacker C — rooted/compromised device

Assume the attacker can inspect application memory/storage and interact with the OS at a privileged level.

Identify what Rocen can realistically protect and what it cannot.

##### Attacker D — malicious/compromised GitHub account

Assume an attacker can modify the backup repository or obtain the GitHub token.

Determine whether they can:

* read notes
* replace encrypted notes
* delete notes
* roll back notes
* inject malicious backup records
* cause corruption
* cause a downgrade/restore attack

##### Attacker E — network attacker

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

##### Attacker F — malicious GitHub repository contents

Assume the repository is writable by an attacker.

Check whether malicious filenames, JSON, metadata, oversized files, unexpected fields, invalid ciphertext, or malicious content can crash the app, bypass validation, overwrite local state, or cause arbitrary behavior.

##### Attacker G — malicious update/release

Check whether users can reliably verify that an APK came from the legitimate developer and corresponds to the published source.


### 3. CRYPTOGRAPHY AUDIT — highest priority

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

#### Specifically investigate:

##### A. Password verifier vs encryption key

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

##### B. Master key architecture

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

##### C. KDF parameters

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

##### D. AES-GCM

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

##### E. Key separation

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

##### F. Password changes

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

##### G. Recovery phrase

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

### 4. LOCAL STORAGE AUDIT

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

### 5. MEMORY & SECRET LIFETIME

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

 

### 6. GITHUB TOKEN SECURITY

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

### 7. NETWORK SECURITY

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

### 8. CERTIFICATE / PUBLIC-KEY PINNING

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

### 9. REMOTE BACKUP SECURITY

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

### 10. SYNC / CONFLICT SECURITY

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



### 11. REPLAY / ROLLBACK ATTACKS

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

 

### 12. INPUT VALIDATION

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

 

### 13. LOGGING & DIAGNOSTICS

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

 

### 14. CLIPBOARD / SCREENSHOT / UI LEAKAGE

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

 

### 15. ANDROID SECURITY

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

 

### 16. ANDROID BACKUP / RESTORE

Determine whether Android Auto Backup or device migration can capture:

* Hive databases
* local keys
* token storage
* preferences
* recovery metadata
* temporary files

If encrypted app state can be restored onto an attacker-controlled or unauthorized device, determine the implications.

Recommend appropriate Android backup rules when necessary.

 

### 17. DEPENDENCY AUDIT

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

 

### 18. RELEASE / SUPPLY-CHAIN SECURITY

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

 

### 19. DOWNGRADE / MIGRATION SECURITY

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

 

### 20. ERROR HANDLING

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

 

### 21. DIFFERENTIATE SECURITY FROM NORMAL FAILURES

For every finding, explicitly label it:

##### RED — Release blocker

A realistic attack can compromise confidentiality, integrity, authentication, keys, or secret material.

##### ORANGE — Serious security weakness

Not an immediate exploit, but meaningfully weakens a stated security property.

##### YELLOW — Hardening / privacy / integrity concern

Worth fixing, but not a direct compromise.

##### BLUE — Reliability / UX / maintainability

Useful improvement, but not a security flaw.

##### GREEN — Not a problem

Initially suspicious-looking behavior that is actually reasonable once the full data flow is understood.

Do NOT inflate findings.

 

### 22. Evidence requirement

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

 

### 23. Compare implementation vs documentation

Cross-check:

* README
* CHANGELOG
* MULTI-DEVICE documentation
* comments
* release notes
* source code
* Android configuration

Create a section:

#### Documentation / Implementation mismatches

For every mismatch state:

Document says:
Code actually does:
Security impact:
Priority:

Do not assume either side is correct.

 

### 24. SECURITY IMPROVEMENT REQUESTS

After completing the vulnerability audit, create a SECOND section called:

### Recommended Security Enhancements

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

 

### 25. Create a final prioritized action list

End the report with:

#### MUST FIX BEFORE RELEASE

Only genuine release blockers.

#### SHOULD FIX SOON

Meaningful security/privacy weaknesses.

#### GOOD HARDENING

Security improvements that are useful but not blockers.

#### OPTIONAL

Low-impact improvements.

#### DO NOT FIX

Things that were investigated and are actually safe/reasonable.

 

### 26. Final security architecture recommendation

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

 

### 27. Important review rules

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

### Final instruction

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
### After Analysis files are build
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

---

## Appendix G — Security Workflow and Scored Findings

<!-- Original source filename: WORKFLOW.md -->
<!-- Original SHA-256: ba94f171eadf5dc92ae4ded95f98605f4eea5c3899152a9792e8bcacb58179e0 -->

#### Root-cause consolidation

**Cluster 1 — the master-key architecture.** Password-verifier/encryption-key reuse (3A), lack of an independent random master key (3B), and the password-change re-encryption burden (3F) are **one architectural fix, not three**. 3B is the root cause; 3A is its direct, most dangerous *symptom* (the verifier being directly usable as a decryption key); 3F is a *downstream consequence* (there's no master key to merely re-wrap, so every password change must touch every note). Introducing a real master key resolves all three simultaneously. I'm scoring this as **one item**.

**Cluster 2 — missing AAD / substitution / metadata tampering / replay-rollback.** These share a common root cause only partially. Missing AAD (3D) is the mechanism; ciphertext substitution and metadata tampering are its *direct consequence* — fixing AAD fixes both in one move. Replay/rollback (Part 3, Section 9) is **related but distinct**: even with perfect AAD binding a note's ciphertext to its ID, an attacker with GitHub write access can still force-push an *old, validly-AAD-bound* commit as current, because AAD says "this ciphertext belongs to this note," not "this ciphertext is the most recent version of this note." AAD needs a monotonic counter/generation bound into it to *also* close replay — so I'll treat this as **one fix (add AAD) with two scopes**: metadata-tamper protection (cheap, do first) and replay-binding (needs the generation number threaded through, slightly more work) — scored together since they're the same code change, same function, same PR.

**Cluster 3 — the two fail-open defaults** (`isDeviceRooted`, `_isHardened`) are the same pattern, same two-line-per-site fix, same file. One item.

**Cluster 4 — release/signing/ProGuard** are genuinely separate: debug signing and missing ProGuard rules touch different files, different risks, different effort. Kept separate.

**Cluster 5 — `publishNewState`'s missing monotonicity check** is distinct from the replay/rollback AAD fix above — it's an *application-level* sanity check inside one function, not a cryptographic binding. Fixing AAD-based replay protection would make this check redundant for the *ciphertext* case, but `publishNewState` also governs the *coordination metadata itself* (generation numbers), which isn't ciphertext at all — so this stays a **separate, much smaller item** that's worth doing regardless of whether Cluster 2's replay scope ever ships.

Here's the full scored list.

#### Scored Findings

| # | Finding | Security Priority (1–10) | Effort (1–10) | Reasoning |
|---|---|---|---|---|
| 1 | **Debug-signed release build** (Part 2/4, H-4) | **9** | **2** | Undermines every other fix in this audit if a tampered build can be distributed as if legitimate — full confidentiality/integrity/availability blast radius, affects every user, trivial to exploit (public debug key), zero legitimate reason it's still this way pre-launch. Effort is trivial: generate a real keystore, point `signingConfig` at it. |
| 2 | **Master-key architecture** (3A + 3B + 3F, one fix) | **9** | **8** | The headline finding of the whole audit — a cold filesystem extraction alone defeats note/token encryption with no password-cracking required. Confidentiality impact is total for anyone who reaches local storage; affects every user with any locked note or saved token. Effort is high: new key-generation, wrap/unwrap logic, migration of every existing user's notes and token to the new scheme, careful sequencing with password-change and device-key-wrap flows so nothing is a data-loss trap mid-migration. |
| 3 | **Two fail-open defaults** (`isDeviceRooted`, `_isHardened`) | **6** | **1** | Real, demonstrable weakening, but bounded — worst case is using an already-reasonable "standard" KDF tier instead of "hardened," not a break. Affects only devices where the native channel call happens to throw, a narrower and less certain occurrence than Finding 2. Effort is trivial: flip two boolean defaults. High value-per-effort, but the actual security delta is smaller than its cheapness might suggest — I'm resisting the temptation to inflate it just because it's an easy win. |
| 4 | **AAD binding: metadata-tamper + ciphertext-substitution scope** (3D, narrow scope) | **7** | **4** | Real integrity gap exploitable by anyone with local or repo write access (Attacker B/D) — titles can be swapped, ciphertext can be substituted between notes undetected. No confidentiality break, but a meaningful trust violation for a feature users specifically chose ("lock this note") believing it protects more than just the body's bytes. Moderate effort: touches the encrypt/decrypt call signature and both call sites (notes, token), plus a compatibility path for already-encrypted data without AAD. |
| 5 | **AAD binding: replay/rollback scope** (extends #4 with a generation/version bound) | **7** | **6** | Same mechanism as #4 but needs the sync layer's generation/version number threaded into the AAD construction, which means touching `password_state_manager.dart`'s publish/reconcile flow too, not just the crypto call sites — meaningfully more moving parts and more ways to get the migration wrong (e.g., a note encrypted before this ships has no generation-bound AAD to compare against). Scored as a slightly higher effort than #4 alone because of that cross-file coordination, even though it's the same root mechanism. |
| 6 | **KDF parameters not recorded in ciphertext** (3C) | **6** | **5** | A real, reproducible data-loss bug (not a confidentiality break) — a note can become undecryptable with the *correct* password if `kdf_hardened` ever flips between encrypt and decrypt. Moderate-likelihood given root-detection heuristics can genuinely flip. Effort is moderate: bump the wire format version, add a compatibility branch that falls back to today's device-state-dependent behavior for old data, store two extra integers going forward. |
| 7 | **`publishNewState` missing monotonicity check** | **5** | **2** | A real, missing defense-in-depth check in a security-relevant function, but the one call site currently exercising it already has an equality-based pre-check that catches the common case in practice — this is "the function isn't self-defending," not "this is currently exploitable in the normal flow." Cheap: one `if` statement inside one function. |
| 8 | **Missing ProGuard rules file** (H-5) | **6** | **3** | Real risk of a silently-broken or silently-wrong release build (crypto code stripped/renamed incorrectly), which could manifest as anything from a crash to — worse — a subtle behavioral change nobody notices until it's a data-loss incident. Not currently *known* to be broken, which is exactly the problem: it's an unverified gap, not a confirmed break. Effort is small: create the file, add explicit `-keep` rules for `cryptography`/isolate entry points, rebuild and diff `seeds.txt`/`usage.txt` to confirm. |
| 9 | **Hive boxes unencrypted at rest** (H-1) | **7** | **6** | Meaningfully compounds Finding 2 today (unencrypted notes, all titles, and pre-fix note/token ciphertext all sit in a box anyone with filesystem access can read), and remains valuable defense-in-depth *even after* Finding 2 is fixed (an extra layer between "attacker has your files" and "attacker has your data"). Effort is moderate-to-significant: migrating to an encrypted box (or a maintained fork) touches every `Hive.openBox`/`Hive.box` call site and needs a data-migration path for existing installs. |
| 10 | **Screenshot/recording protection scoped only to Settings screen** (Attacker A) | **6** | **3** | Real, demonstrable gap — QuickNote, Clipboard, Bookmarks, IdeaInbox all run with zero protection today, and this is trivially exploitable by anything with screen-recording capability or just Android's own recent-apps thumbnail. Bounded to Attacker A (local, no root needed) rather than a remote/mass-exploitation vector, which caps it below Finding 2/1. Effort is small: move the `FLAG_SECURE` toggle logic to wrap the specific sensitive moments/screens rather than one tab's lifecycle. |
| 11 | **No payload-size limit before `jsonDecode`** (Attacker F) | **4** | **2** | A real, simple DoS vector, but requires the attacker to already have (or trick the user into pointing at) a malicious/compromised repository — a narrower precondition than most other findings, and the impact is a crash/OOM, not data loss or confidentiality/integrity compromise. Effort is trivial: check `Content-Length`/response byte-length before decoding. |
| 12 | **`android:allowBackup` defaults true** (H-6) | **5** | **1** | Meaningfully widens Finding 9's exposure (unencrypted boxes become extractable via a legitimate-looking OS backup flow, not just root/physical access), but is entirely mooted in practice once Finding 9 is fixed (an encrypted box extracted via backup is no more useful to an attacker than one extracted via root). Trivial effort: one manifest attribute. |
| 13 | **Stable `deviceId` in shared plaintext `password_state.json`** (P-1) | **4** | **3** | Metadata/behavioral-pattern leak only — no secrets exposed, requires the attacker to already have repo read access (a precondition that, if met, already grants far more useful information than device topology). Effort is small-to-moderate: stop publishing `deviceId` remotely, keep a local-only `deviceNumber → deviceId` map, verify no other logic silently depends on the public field. |
| 14 | **Plaintext note/ciphertext buffers not zeroed in `crypto_isolate.dart`** (Section 5) | **3** | **2** | Only matters against an attacker with live memory-inspection capability (Attacker C), who — per the audit's own Attacker-C analysis — already has many more direct paths to the same content; this is marginal hardening for an attacker who's mostly already won. Cheap to add (mirror the existing `keyBytes.zero()` pattern onto the plaintext buffers), so worth doing, just not urgent. |
| 15 | **`amendSync` silently drops delete/rename requests for files it can't find** (I-2, prior report) | **4** | **3** | Real silent-failure mode — a user could believe a note was deleted from GitHub when it wasn't — but requires a specific pre-existing inconsistency to trigger (a prior race/bug), not something an attacker can force on demand. Effort: surface a non-2xx-equivalent signal to the caller when part of a batch is dropped instead of a bare early return. |
| 16 | **`FLAG_SECURE`/redirect/native-plugin residual uncertainty items** (Part 5) | **3** | **N/A — not a Rocen code fix** | Not scoreable as an implementation item at all in the same terms — the redirect question can only be closed by the vendor or by disabling redirects entirely if the native API exposes that option (itself effort ≈2 *if* such an option exists, unknown effort if it doesn't). Listed for completeness, not ranked in the main sequence. |
| 17 | **No biometric auth, no `SECURITY.md`, no backup SPKI pin, `secureDebugLog` naming** (H-2, H-3, Section 18 items) | **2–3 each** | **2–4 each** | Genuine hardening/hygiene, none address a demonstrated live weakness — appropriately last. |

#### Recommended sequence

**Fix this first → then this → then this:**

1. **Debug-signed release build (#1).** Zero dependency on anything else, trivial effort, and every subsequent fix is meaningless if a tampered build can circulate under the app's name. Do this before anything else ships anywhere.

2. **Missing ProGuard rules file (#8).** Also independent, also cheap, and should be verified *before* the master-key migration ships — you want confidence that R8 isn't going to silently mangle new crypto code before you introduce more of it.

3. **Two fail-open defaults (#3).** Independent, trivial, no migration risk, immediately reduces exposure while the bigger fix is being built.

4. **Master-key architecture (#2).** This is the architectural linchpin the sequence has to respect: **items 5, 6, and 9 below all become easier, safer, or partially redundant once this exists**, and doing them beforehand risks building on top of a foundation you're about to replace. This should be done as its own dedicated migration, with its own careful rollout (e.g., transparently re-wrap on next successful unlock, per the audit's own recommendation), before anything else touches the encryption call path.

5. **AAD binding, metadata-tamper scope (#4).** Do this *after* the master key exists, not before — you want the AAD change and the key-derivation change to land as one coherent format version bump (bump `_version` once, carry both changes together) rather than two separate incompatible-format migrations back to back, which would double the number of "does this app version still understand old data" edge cases users experience.

6. **AAD binding, replay/rollback scope (#5).** Natural, low-incremental-cost extension of step 5 once the AAD plumbing exists — do it in the same release if possible, since it's the same mechanism with one more field threaded through.

7. **KDF parameters recorded in ciphertext (#6).** Same format-version bump as steps 5–6 — this is the point where I'd combine all three into **one version-2 wire format migration**, since doing three separate breaking-format changes to the same ciphertext envelope across three releases multiplies migration risk for no benefit. Bundle steps 5, 6, and 7 into a single format revision.

8. **`publishNewState` monotonicity check (#7).** Cheap, independent, no reason to wait — could actually be done any time after step 1, but placed here because it's low-consequence enough that it doesn't need to jump the queue ahead of the higher-priority architectural work.

9. **Hive box encryption (#9).** Deliberately placed *after* the master-key work, not before — encrypting the box is real defense-in-depth, but if done first, you'd need to migrate the box's encryption key *and then separately* migrate to the new master-key architecture shortly after, doing key-management migration twice. Sequencing it after step 4 means the box-encryption key itself can be designed to sit correctly within the new architecture from the start.

10. **`android:allowBackup=false` (#12).** Trivial, but sequenced after step 9 since its main value (closing the backup-extraction path) is largely about protecting the same Hive boxes step 9 is busy fixing — do it any time, but no urgency to jump the queue for a one-line change whose payoff is already partially covered by whichever of steps 4/9 ships first.

11. **Screenshot/recording protection scope (#10).** Independent of everything above — could genuinely be done any time, sequenced here mainly because nothing forces it earlier or later.

12. **Payload-size limit (#11).** Independent, cheap, no urgency — do whenever convenient.

13. **Stop publishing `deviceId` remotely (#13).** Independent, small, no urgency.

14. **Zero plaintext buffers in `crypto_isolate.dart` (#14).** Small, mechanical, no dependency — natural to bundle into the same PR as step 4 (the master-key work) since you'll already be touching that file, but not load-bearing for anything.

15. **`amendSync` silent-failure surfacing (#15).** Independent, low urgency.

16. **Everything in the H-2/H-3/Section-18 basket** (biometrics, `SECURITY.md`, backup SPKI pin, `secureDebugLog` rename) — last, as genuine hardening rather than fixes to a demonstrated weakness, done opportunistically alongside other work rather than as a dedicated pass.

**Explicitly not sequenced** (#16 — the native plugin redirect question): this isn't a code change Rocen can make unilaterally with current information. Pursue vendor confirmation in parallel with the above at any point; if the vendor confirms an unsafe default or doesn't respond, revisit as its own item once you know what you're actually fixing.


---

## Appendix H — Prior Security Documentation Coverage Map (historical assessment)

**Provenance:** Preserved from the previously uploaded `SECURITY_DOCUMENTATION_COVERAGE.md` snapshot.  
**SHA-256 of that original snapshot:** `4e28cca06906632e80c7386f919cecaa049c6c8757d6fa643965f05f4dc4a974`.  
**Interpretation:** This source assessed whether `Phase Stage - 5.md` and `Current Stage 5 Workflow.md` covered selected root-level contents of `security.zip`. It predates this master consolidation, so its labels such as “summarized” and “omitted from the consolidation” describe those two earlier documents—not this file. Its advice to retain separate source files was appropriate for that earlier state; the current consolidation preserves the in-scope Markdown sources in Appendices A–G. The excluded `MULTI-DEVICE.md`, `security/audits/`, and `security/remediation/` remain out of scope here as well.

The original report's wording and tables follow below; only heading levels have been shifted to fit this appendix.

### Rocen — Security Documentation Coverage Map

**Prepared:** 10 October 2026  
**Purpose:** Map what the two current Stage 5 documents preserve from the root-level security documentation bundle, and identify what remains summarized, omitted, or outside the Stage 5 handoff.  
**Scope:** This is a documentation-coverage assessment, not a source-code audit and not evidence that an implementation or test works.

#### 1. Scope and documents compared

The comparison uses these two consolidation documents:

- `Phase Stage - 5.md` — the more detailed Stage 5 architecture/status record.
- `Current Stage 5 Workflow.md` — the operational handoff and next-repair workflow.

They were compared against the root-level items in `security.zip` listed below. As instructed, **`MULTI-DEVICE.md` is deliberately excluded**. The entire `security/audits/` and `security/remediation/` directories are also excluded from this comparison, so this file makes no claim about whether their contents are covered.

| Root-level source item in `security.zip` | Included in this coverage review? | Why it matters |
|---|---:|---|
| `CHANGELOG.md` | Yes | Historical release claims and documentation/source mismatches. |
| `PROMPT.md` | Yes | Broad threat model, audit checklist, prioritization, and review rules. |
| `Stage 5 Architecture & Security Handoff.md` | Yes | Detailed Stage 5 design, prior findings, files, checkpoints, tests, and completion criteria. |
| `WORKFLOW.md` | Yes | Consolidated security findings, historical scores, and recommended order of work. |
| `SESSION BOUNDARY & KEY ISOLATION.png` | Yes | Visual architecture, key ownership, lifecycle, state transitions, responsibilities, and invariants. |
| `MULTI-DEVICE.md` | **No — excluded** | Explicitly outside this comparison, per instruction. |
| `security/audits/*` | **No — excluded** | Audit source set intentionally out of scope. |
| `security/remediation/*` | **No — excluded** | Remediation source set intentionally out of scope. |

##### Coverage labels

- **Covered for Stage 5:** The relevant Stage 5 point is carried into the consolidation with enough detail to guide the present phase; this does not mean the implementation has passed.
- **Summarized:** The topic is mentioned, grouped, or reduced to a status/backlog item; the original detail and checklist are not preserved.
- **Omitted from the consolidation:** The topic or product-history detail is not meaningfully reproduced in the two current Stage 5 documents.
- **Out of Stage 5 scope / deferred:** The subject is acknowledged as another phase or broader release work rather than being fully incorporated into the Stage 5 handoff.
- **Not independently verifiable:** A referenced source or platform artifact was not available in the supplied comparison set, so coverage cannot be confirmed.

These labels describe **documentation coverage only**, not security correctness.

#### 2. Overall result

**The two Stage 5 documents are a useful, substantially overlapping Stage 5 handoff, but they are not a full replacement for the included root-level security documents.**

`Phase Stage - 5.md` carries the Stage 5 state model, key-ownership intent, major current blockers, the next repair sequence, evidence policy, and a selected broader-audit status register. `Current Stage 5 Workflow.md` makes the immediate collaboration/validation process easier to execute. Both intentionally focus on Stage 5.

The consolidation therefore preserves the **decision-critical Stage 5 status**, but it does not preserve every historical claim, every threat-model question, every original audit check, every scoring rationale, all old file-level implementation notes, or all non-Stage-5 product history. The PNG is referred to conceptually but is not reproduced as a full diagram in either Markdown consolidation.

The resulting handoff should be read together with the source documents when the omitted detail matters. It should not be treated as an archival replacement for the source bundle.

#### 3. Coverage of `CHANGELOG.md`

The changelog contains two main release groups, `[0.4.0-alpha]` and `[0.4.0]`. The Phase document performs a **selective historical cross-check** in its sections 5–6; it does not reproduce the whole changelog.

| Original changelog section | Coverage in the two Stage 5 documents | Classification | What remains in the original source |
|---|---|---|---|
| `[0.4.0-alpha]` — Code Quality | Only relevant validation/source-vs-claim implications are discussed generally. | Summarized | Individual code-quality history and each change description. |
| GitHub Sync Safety | Related authority-write/path and sync-fencing concerns appear in Stage 5 status/backlog. | Summarized | Full historical description of sync changes and original behavior claims. |
| Recovery & Password Change | Password change, rewrapping the same MK, and recovery/association scope are covered for current Stage 5 architecture. | Covered for Stage 5 / historical details summarized | The complete historical UX/implementation narrative and claims outside the reviewed source snapshot. |
| Clipboard: Image + Video Support | Not part of the Stage 5 security handoff. | Omitted from the consolidation | Feature behavior, cache/display decisions, and related history. |
| Clipboard: Full-Screen Viewer, Zoom, Rotation & Toolbar | Not reproduced. | Omitted from the consolidation | UI feature details and fixes. |
| Clipboard: Copy to Clipboard | Not reproduced. | Omitted from the consolidation | Clipboard implementation changes and user feedback behavior. |
| Clipboard: Crop | Not reproduced. | Omitted from the consolidation | Crop interaction, save location, sizing, and UI fix history. |
| Android Configuration (`[0.4.0-alpha]`) | Build/platform configuration is noted only as not verifiable where the repair archive lacks native/build files. | Summarized / not independently verifiable | Exact permission, provider, SDK, namespace/application ID changes claimed by the changelog. |
| Dependencies (`[0.4.0-alpha]`) | Not given a dependency-by-dependency account. | Omitted from the consolidation | Added dependencies and their original stated purposes. |
| `[0.4.0]` — Security & Cryptography | The password-policy mismatch, hardware-key claim, recovery, and Stage 3/4 key model are cross-checked selectively. | Summarized | The full historical account of all cryptography/password behavior changes. |
| GitHub Backup | Empty-repository setup and authority-write context are discussed selectively. | Summarized | All individual API/error handling and setup fixes listed in the changelog. |
| GitHub Request & Network Security | SPKI pinning/native source verification is called out as unverified; request-construction history is not reproduced in full. | Summarized / not independently verifiable | Request headers, endpoint allowlisting, UTF-8/Base64 and plugin integration change history. |
| GitHub Diagnostics | Not reproduced as a complete historical feature section. | Omitted / summarized only at high level | Individual diagnostics and GitHub response handling changes. |
| Settings & UI/UX | Not part of the Stage 5 handoff except where sensitive cleanup/security behavior intersects. | Omitted from the consolidation | Dialog styling, requirements presentation, recovery UI, and design-system details. |
| Reliability & Code Quality | Runtime evidence honesty is covered, but the changelog's individual historical claims are not all replayed. | Summarized | Full bug-fix list and the historical statement that the earlier configuration built and tested successfully. |
| Changelog `Result` paragraphs | The Stage 5 docs warn that historical claims are not proof for the current ZIP and identify specific mismatches. | Covered as a review principle; not reproduced wholesale | Original release summary and its complete feature framing. |

**Practical conclusion for the changelog:** retain `CHANGELOG.md` as release history. Use `Phase Stage - 5.md` for the selected current-source cross-checks, and do not infer that unmentioned changelog entries were revalidated.

#### 4. Coverage of `PROMPT.md`

`PROMPT.md` is a broad audit instruction set, not just a Stage 5 design note. The current consolidation captures its evidence-first philosophy and some major backlog items, but it does **not** preserve its complete threat-model prompts or all checklist questions.

| `PROMPT.md` section | Coverage in the two Stage 5 documents | Classification | Material not fully carried over |
|---|---|---|---|
| 1. Build the actual security model | Stage 5 trust/ownership model is described, but not the complete app-wide data-flow inventory requested by the original prompt. | Summarized | End-to-end inventory of plaintext, ciphertext, passwords, recovery words, tokens, device keys, metadata, storage, network transmission, and restart/restore survival. |
| 2. Threat model — Attacker A: ordinary malicious app | Screen-security/clipboard-style exposure appears only as a broader concern. | Summarized | Full attacker-specific capability and attack-scenario questions. |
| 2. Attacker B: filesystem/app-data extraction | Storage/envelope status is summarized. | Summarized | Full attacker-received-data inventory and recoverability analysis. |
| 2. Attacker C: rooted/compromised device | Memory limitations and realistic zeroization claims are acknowledged. | Summarized | Full privileged-attacker analysis and capability boundary. |
| 2. Attacker D: malicious/compromised GitHub account | GitHub authority writes and broader backup/sync items appear in the Stage 5 backlog. | Summarized | Full read/replace/delete/rollback/corruption/downgrade threat questions. |
| 2. Attacker E: network attacker | Pinning/native implementation uncertainty is noted. | Summarized | Full TLS, validation, replay, redirect, delay, and request-manipulation checklist. |
| 2. Attacker F: malicious repository contents | Payload-size limits and remote-input issues appear in the broader backlog. | Summarized | Full repository-content injection and parser attack checklist. |
| 2. Attacker G: malicious update/release | Release/signing/supply-chain checks appear only in the broader priority register. | Summarized | Full tampered-release/update threat analysis. |
| 3. Cryptography audit — password verifier vs encryption key | Stage 3 key separation and separate verifier/KEK paths are summarized. | Summarized | Full original verification questions and reasoning. |
| 3. Master-key architecture | Current MK/KEK/session ownership invariants are covered. | Covered for Stage 5/3–4 boundary | Full historical architecture audit checklist and migration investigation. |
| 3. KDF parameters | Fixed-profile metadata is summarized. | Summarized | All KDF audit questions and profile-transition scenarios. |
| 3. AES-GCM | Stage 3/4 meaning is to be preserved; note envelope/AAD is deferred. | Summarized / deferred | Full nonce, tag, AAD, ciphertext-integrity, and call-site checklist. |
| 3. Key separation | NEK/TEK labels and Stage 4 derivation invariants are named. | Covered for Stage 4 invariant; broader checklist summarized | Full original domain-separation questions and any unrelated secret classes. |
| 3. Password changes | Rewrap-the-same-MK invariant and authenticated mutation fence are covered. | Covered for Stage 5 invariant | Full legacy compatibility/migration questions in the original audit prompt. |
| 3. Recovery phrase | Recovery and bootstrap scope are covered at the current Stage 5 boundary. | Summarized | Full recovery-phrase entropy, normalization, exposure, and recovery-flow checklist. |
| 4. Local storage audit | Protected persistence being disabled and selected metadata/storage concerns are stated. | Summarized / deferred | Full Hive/storage/cache/file/backup audit. |
| 5. Memory & secret lifetime | Transaction ownership, reachable buffer cleanup, synchronous lock, and the limitation on claims of physical erasure are covered. | Covered for Stage 5 core; broader scope summarized | Complete inventory of every plaintext/intermediate buffer and all crypto-isolate/FFI/library copies. |
| 6. GitHub token security | GitHub token retention and broader security concerns are noted in the backlog/status. | Summarized | Complete token-at-rest, in-memory lifetime, logging, revocation and access-scope checklist. |
| 7. Network security | Remote write fencing and network/pinning uncertainty are covered selectively. | Summarized | Full endpoint, transport, timeout, retry, redirect, content-type, and HTTP behavior review. |
| 8. Certificate/public-key pinning | Native pinning implementation is explicitly not verified from the incomplete repair ZIP. | Covered as an uncertainty, not as a complete review | Original pin-rotation, bypass, plugin and platform implementation checklist. |
| 9. Remote backup security | Reserved authority paths and grant-fencing blockers are covered. | Summarized | Full backup schema, authority-record integrity, deletion, atomicity, and repository permissions checklist. |
| 10. Sync/conflict security | Relevant generation/remote write fencing is listed as Stage 5 or broader backlog. | Summarized | Full concurrent-device, merge, conflict, and state-reconciliation analysis. |
| 11. Replay/rollback attacks | Explicitly acknowledged as distinct from AAD and still deferred with the data envelope / generation design. | Summarized / deferred | Full replay and rollback cases, protocol-level defenses, and migration consequences. |
| 12. Input validation | Reserved GitHub path normalization and JSON payload-size concern are mentioned. | Summarized | Full validation matrix for every external input and parser. |
| 13. Logging & diagnostics | A subset of historical diagnostics is discussed; broad hygiene remains backlog. | Summarized | Full secret-leakage/logging audit and diagnostic policy. |
| 14. Clipboard/screenshot/UI leakage | Session-scoped UI and screen-security gate are covered; product history is not. | Covered for Stage 5 boundary; otherwise summarized | Full clipboard, screenshot, recents thumbnail, overlay, and sensitive-screen threat checklist. |
| 15. Android security | Native/build files are absent from the latest repair archive and the gap is noted. | Summarized / not independently verifiable | Complete Android manifest, component, channel, permission, hardening and build configuration audit. |
| 16. Android backup/restore | `allowBackup` is listed as not verified. | Summarized / not independently verifiable | Full backup/restore include/exclude rules and device-transfer cases. |
| 17. Dependency audit | Broader supply-chain work is listed, but dependency-by-dependency review is not reproduced. | Omitted from detailed coverage / deferred | Package versions, advisories, transitive dependencies, license/provenance and update review. |
| 18. Release/supply-chain security | Release signing and ProGuard/R8 are named as not verified. | Summarized / not independently verifiable | Complete release-build, signing, reproducibility, provenance, obfuscation and distribution checklist. |
| 19. Downgrade/migration security | Clean cutover/no compatibility/no migration Stage 5 scope is preserved. | Covered for the Stage 5 scope decision; detailed checklist summarized | Full release migration, downgrade and old-format rollback analysis. |
| 20. Error handling | Fail-closed behavior and source/runtime evidence distinctions are mentioned. | Summarized | Full error taxonomy, retry behavior, data-loss and fail-open/fail-closed checklist. |
| 21. Security vs normal failures; RED/ORANGE/YELLOW/BLUE/GREEN categories | Stage 5 uses its own evidence vocabulary and blocker status. | Summarized, not equivalent | Original five finding categories and the complete severity/normal-engineering distinction rubric. |
| 22. Evidence requirement | Source beats claims; tests must be marked executed/not executed; runtime output and exit codes are required. | Covered in substance | Any original evidence-format details not reproduced verbatim. |
| 23. Compare implementation vs documentation | The changelog cross-check has specific examples of mismatches. | Covered selectively | A complete implementation-vs-documentation comparison across every claim/artifact. |
| 24. Security improvement requests / recommended enhancements | A prioritized selected backlog is recorded. | Summarized | All original suggestions and rationale. |
| 25. Final prioritized action list | The Phase document preserves selected scored findings from `WORKFLOW.md`; this is not a full copy of all prompt action buckets. | Summarized | Full must-fix/should-fix/good-hardening/optional/do-not-fix lists in their original organization. |
| 26. Final security architecture recommendation | The approved Stage 3–5 ownership model is described. | Covered for current Stage 5 scope; broader architecture summarized | Full original architecture proposal across the full app and all future phases. |
| 27. Important review rules | The Stage 5 handoff contains a related set of implementor rules. | Covered in substance for Stage 5 | Exact wording/context of all original audit rules and rules unrelated to this phase. |
| Final instruction / post-analysis file instructions | Not used as a complete process specification in the two current docs. | Omitted / summarized through the present workflow | Any original output-file naming and follow-on deliverable instructions. |

**Practical conclusion for `PROMPT.md`:** the current documents are not a replacement for the prompt's full app-wide audit checklist. Keep the original prompt for later storage, sync, Android, dependency, release, and data-envelope phases. Reuse its threat scenarios rather than assuming a row marked “summarized” has been fully audited.

#### 5. Coverage of `Stage 5 Architecture & Security Handoff.md`

This is the source document most closely aligned with `Phase Stage - 5.md`. The later Phase document is a refreshed, source-specific Stage 5 summary, and the Current Workflow document is its operational companion. Coverage is strongest here, but detail was intentionally compressed.

| Original handoff section | Coverage in `Phase Stage - 5.md` and `Current Stage 5 Workflow.md` | Classification | Detail retained only in, or better preserved by, the original handoff |
|---|---|---|---|
| 1. Purpose of this document | Phase's purpose/source-set/evidence vocabulary covers the role of the handoff. | Covered in substance | Full historical purpose/context. |
| 2. Source/evidence hierarchy | Source-of-truth and evidence labels are preserved. | Covered in substance | Full prior hierarchy wording and any historical distinctions. |
| 3. Development workflow | Current Workflow gives the canonical workflow, roles, archive review, runtime validation and follow-up sequence. | Covered in substance | Full explanation of why that workflow is structured as it is. |
| 4. Stage 5 security goal | Current state/ownership goal and scope constraints are preserved. | Covered | The original expanded explanation and supporting examples. |
| 5.1 Session state/security layer | Phase states the lifecycle and key transitions. | Covered | Detailed original file/implementation trace. |
| 5.2 Session authorization capability | Non-forgeable, epoch/session-bound token requirement is retained. | Covered | Full previous design detail and earlier implementation progression. |
| 5.3 Activation transaction | Private transaction, candidate ownership, stale checks and lock reachability are retained. | Covered | Longer step-by-step prior implementation discussion. |
| 5.4 Deterministic checkpoint system | Seven checkpoint names and the unwrap race remain; tests are inventoried. | Covered | Detailed per-checkpoint test rationale and source references. |
| 5.5 Session key material | Sole authoritative live-owner model is retained. | Covered | Full ownership tracing and prior corrections. |
| 5.6 Session unlock path | Unlock/authentication and transfer invariants remain. | Covered | More granular prior call-path narrative. |
| 5.7 MasterKeyManager custody refactor | “No live key bytes/cache” target is explicit in Phase. | Covered | Earlier design history and individual file-level discussion. |
| 5.8 Domain-key derivation | Stage 4 NEK/TEK invariants are preserved at high level. | Covered | More detailed derivation implementation notes and evidence trail. |
| 5.9 UI/session entry points | Session-scoped app/navigation and provider lifetime are retained. | Covered | Earlier widget/navigation entry-point analysis. |
| 5.10 Session/security tests | Test files and unexecuted status are listed. | Covered / summarized | Full test-by-test descriptions and historical names/assertions. |
| 6. Files changed in the current `Rocen-P5.zip` — new production files | Current docs describe selected current files but do not reproduce the complete earlier file inventory. | Summarized | Full list of files described as new in that historical ZIP. |
| 6. Files changed — modified production files | Selected key files and responsibilities are named. | Summarized | Full modified-file list and file-level role descriptions. |
| 6. Files changed — new test files | Several test files and main test groups are inventoried. | Summarized | Full new-test-file inventory for that specific ZIP. |
| 6. Files changed — modified test files | Key tests are mentioned but the complete table is not repeated. | Summarized | Complete modified-test list. |
| 6. Unchanged but relevant production files | Selected relevant current files are referenced. | Summarized | Full unchanged-but-relevant file inventory. |
| 7. Implementor report vs latest ZIP | Phase adopts source-over-report rule and records specific verified gaps; Current Workflow requires a new ZIP/diff review. | Covered in substance | Full prior comparison table and its historical claims. |
| 8.1 Public authorization-free security mutations | Current status says old testing bypasses were removed and preserves remaining boundaries. | Covered | Earlier detailed path-by-path finding and repair discussion. |
| 8.2 Public `ActivationTransaction` | Private `_ActivationTransaction` status is preserved. | Covered | Original finding history. |
| 8.3 Unwrap-to-adopt stale race | Staleness checks and H race are preserved, including runtime-unverified status. | Covered | Detailed prior race sequence and file-level recommendations. |
| 8.4 Suspendable activation secrets | The reachability/clearing limitation is retained in the ownership and evidence sections. | Covered in substance | Full original inventory of secret-bearing futures, locals and suspension points. |
| 8.5 `changePassword` durable-write fencing | Authenticated token and write-fence requirements are summarized. | Covered | Detailed original await/write boundaries. |
| 8.6 `associateRemote` durable-write/remote-start fencing | Authorization and bootstrap/recovery boundary are retained. | Covered | Complete previous per-call path and fence analysis. |
| 8.7 Protected app/Navigator not session-scoped | Session-scoped `ProtectedSessionApp` is noted as source present. | Covered | Prior implementation path and exact architectural correction. |
| 8.8 ProviderContainer not synchronously destroyed | Current docs record session-owned container and the remaining bootstrap cleanup issue. | Covered | Previous detailed resource registration/destruction analysis. |
| 8.9 ACTIVATING resources synchronously destructible | Activation transaction and lock teardown invariants are preserved. | Covered in substance | Original detailed transition/cleanup review. |
| 8.10 Bootstrap/first-run flow incomplete | The current bootstrap blockers are expanded and are central in Phase/Workflow. | Covered and updated | Earlier pre-repair framing; latest blocker list should be preferred for the reviewed baseline. |
| 8.11 `recoverFromRemote()` scope | Narrowing recovery and verifying after awaits are preserved. | Covered | Earlier call-site exploration and full recovery flow notes. |
| 8.12 Native screenshot protection | Unsupported-platform policy and missing native source are recorded as a blocker. | Covered and updated | Earlier platform-integration discussion. |
| 9. Intended repaired architecture | Phase's approved ownership model and state lifecycle preserve the design core. | Covered | Full expanded architectural narrative. |
| 10. Planned/current repair files | Current Workflow names repairs by security property; not every exact intended file change is repeated. | Summarized | Original production/test file plan. |
| 11.1–11.5 How bugs are being fixed | Grant fencing, bootstrap permits, key ownership, durable-write fencing and UI/provider teardown are in the current repair sequence. | Covered in substance, with updated blockers | Full subsection-level implementation plan and previous repair history. |
| 12. Checkpoints A–H | The named checkpoint set and test inventory are preserved. | Covered | Full test steps/expected outcomes for each checkpoint. |
| 13. Authorization test plan | Authorization tests and completion criteria are represented, but not all original individual test cases are reproduced. | Summarized | Full original authorization test cases. |
| 14. Ownership audit plan | Ownership invariant and audit/test references remain. | Summarized | Full owner-by-owner audit steps. |
| 15. Async secret-retention audit plan | Reachable buffers, async boundaries, and limits on erasure claims remain as concerns. | Summarized | Complete original secret-retention checklist. |
| 16. Bootstrap/corrupt authority rules | This is a central part of the current blockers/repair sequence. | Covered and updated | Prior detailed branch matrix; consult the latest blocker/status text where it differs. |
| 17. Screenshot-control status | Current status and missing native verification remain. | Covered | Original evidence/implementation notes. |
| 18. Runtime/evidence policy | Explicit executed/not-executed/source-only labels and command requirements are retained. | Covered | Full earlier evidence examples and historical table. |
| 19. Current implementation status matrix | Phase provides a refreshed status table. | Covered and updated | Historical snapshot-specific table, which should not be treated as current evidence. |
| 20. Completion gate | A current completion gate is retained. | Covered and refreshed | Full earlier gate wording where it was more granular. |
| 21. Future AI implementor rules 1–10 | Similar rules are preserved in substance: source over report, architecture over names, preserve crypto meaning, no weakened test paths, check async boundaries, avoid overclaiming, challenge design, fix before expansion. | Covered in substance | Original full language and context. |
| 22. Immediate next step | The next grant/bootstrap repair and validation sequence are explicit. | Covered and updated | Earlier snapshot's next-step framing. |
| 23. Change history/review trail | Current documents state the current reviewed archive and status date but do not reproduce the full historical change trail. | Summarized | Stage 5 design baseline, ownership correction, checkpoint correction, authorization correction, and prior repair-correction timeline. |
| 24. Final status statement | The not-approved/in-progress status and runtime limitation are clear. | Covered and updated | Historical status text tied to an older snapshot. |

**Practical conclusion for the Stage 5 handoff:** `Phase Stage - 5.md` is the primary current snapshot summary, while `Current Stage 5 Workflow.md` explains how to continue. Keep the original handoff as design history and a deeper checklist; it contains file inventories, test details and audit trails that the newer documents deliberately condense.

#### 6. Coverage of `WORKFLOW.md`

The original workflow has three parts: root-cause clustering, a scored findings table with priority/effort and rationale, and a recommended order of work. The Phase document's section 11 preserves a selected backlog table and explicitly retains the original priority/effort scores where listed. It does not fully reproduce all cluster explanations or every row's original reasoning.

| Original workflow section | Coverage | Classification | Detail retained only in original |
|---|---|---|---|
| Root-cause consolidation: master-key architecture | Stage 3/4 architecture and separate verifier/wrapper model are summarized. | Summarized | Original rationale for treating related findings as one architectural fix and the historical migration implications. |
| Root-cause consolidation: AAD, substitution, metadata tampering, replay/rollback | AAD/envelope and rollback are identified as deferred/outside this Stage 5 phase. | Summarized / deferred | Original distinction between note binding and monotonic “latest version” protection, and the shared-fix scoring rationale. |
| Root-cause consolidation: fail-open defaults | Root-detection behavior is mentioned. | Summarized | Original explanation of the paired pattern and comparative risk/effort rationale. |
| Root-cause consolidation: release signing vs ProGuard/R8 | Both are listed as separate not-verified items. | Summarized | Original reasoning for keeping them separate. |
| Root-cause consolidation: `publishNewState` monotonicity | The older symbol and current equivalent are discussed as needing a separate review. | Summarized | Original explanation of why app-level generation monotonicity is distinct from AAD replay protection. |
| Scored findings table | Phase section 11 keeps 17 selected items and their original scores where present, plus current disposition. | Summarized, with scores preserved for listed rows | Full source rationale, phrasing, dependencies, and complete table text. |
| Recommended sequence | Current Workflow contains an immediate repair/validation sequence; Phase has a Stage 5-specific sequence plus the broader register. | Covered for immediate Stage 5 work; broader order summarized | Original complete sequence for non-Stage-5 pre-release priorities. |

The score values are original planning ratings, not a new assessment made by this coverage document. Current code status in the Phase document is a separate, snapshot-specific judgement. The two must not be conflated.

#### 7. Coverage of `SESSION BOUNDARY & KEY ISOLATION.png`

The image has seven visible regions: **(1)** System Architecture (Stage 3 + Stage 5), **(2)** Key Ownership Model, **(3)** Key Lifecycle & Workflow, **(4)** Component Responsibilities, **(5)** State Transitions, **(6)** Security Invariants, and **(7)** Legend.

| Diagram region | Text coverage in the two Stage 5 documents | Classification | Coverage gap |
|---|---|---|---|
| 1. System architecture | Phase's approved ownership model, Stage 3/4 preservation boundary, persistent authority, and protected application scope describe the core components. | Covered in substance | The diagram's full system-wide component/data/control-flow layout is not reproduced as a visual or complete textual equivalent. |
| 2. Key ownership model | The distinction between durable wrapped authority, state/controller responsibilities, transaction-local candidate keys, and sole live `SessionKeyMaterial` ownership is explicit. | Covered | The image's full visual relationship and every label are not repeated. |
| 3. Key lifecycle & workflow (cold start, unlock, change password, recovery/associate remote, lock, second unlock) | Unlock, password change, recovery/association, and lock are described across the Phase state model and blockers. | Covered in substance | The complete six-column lifecycle sequence and every step/transition are not reproduced as a single diagram-equivalent description. Bootstrap and recovery remain specifically blocked until repaired. |
| 4. Component responsibilities | Responsibilities of `MasterKeyManager`, `MasterKeyLocalStore`, `SessionKeyMaterial`, crypto providers, and protected UI/resources are described. | Covered in substance | Not every diagram bullet is repeated verbatim. |
| 5. State transitions | `BOOTSTRAP`, `LOCKED`, `UNLOCKING`, `ACTIVATING`, `UNLOCKED`, and lock/rollback are explicit in Phase. | Covered | The figure's graphical transition arrows are not reproduced. The image should be treated as intended architecture, not evidence that every transition is correct in source. |
| 6. Security invariants | Sole live key owner while unlocked; no authoritative live key when locked; temporary candidates are not authoritative; async work must validate freshness; UI/provider teardown should be synchronous. | Covered in substance | The full set of image assertions is not reproduced line-by-line. Some corresponding code paths remain blockers or runtime-unverified. |
| 7. Legend | The Phase document explains the architecture through prose and tables. | Omitted as a separate item | Visual styling and distinctions between data flow, control flow, and interaction arrows. |

**Important status caveat:** the PNG is an intended-architecture diagram. Its green check icons and declarative invariants are not proof that the current source satisfies them. The newer Phase document explicitly records blockers around grant scope, bootstrap authorization/cleanup, resets and screen-security policy.

#### 8. What the two current documents intentionally optimize for

The overlap is deliberate:

- `Phase Stage - 5.md` is for the durable record: what was reviewed, what source shows, what's blocked, tests/evidence, and what must be true before sign-off.
- `Current Stage 5 Workflow.md` is for execution: who does what, the current repair instruction, how to inspect the returned archive, which commands must actually run, and the decision rule.

This means their repeated summary is not a coverage defect by itself. The gap is that neither claims to reproduce the entire original corpus, and some non-Stage-5 source material is only referenced in summary form.

#### 9. Recommended use going forward

1. Treat `Phase Stage - 5.md` as the **current Stage 5 status snapshot**, updating it only after a new source archive has been inspected and evidence has been collected.
2. Treat `Current Stage 5 Workflow.md` as the **operational checklist** for the next implementor/auditor cycle.
3. Retain `CHANGELOG.md` as historical release notes; do not treat its success statements as proof for a later source ZIP.
4. Retain `PROMPT.md` as the broad audit checklist for future phases. For any item marked summarized, deferred, or not verified above, return to the original section instead of assuming it has been resolved.
5. Retain `Stage 5 Architecture & Security Handoff.md` as the deeper architecture/history record, particularly for detailed file lists, test plans and review trail.
6. Retain `WORKFLOW.md` as the original scoring/rationale source for the broader backlog; do not treat the Phase table as a full reproduction of every original rationale.
7. Retain the PNG as a visual architecture reference, but annotate/update it if the approved design changes. Do not use it as implementation evidence.
8. Keep `MULTI-DEVICE.md`, `security/audits/`, and `security/remediation/` outside this coverage judgment. They were excluded and have not been assessed here.

#### 10. Final conclusion

The two Stage 5 Markdown documents capture the **current Stage 5 direction and the immediate blockers well**, but the source corpus is broader. `CHANGELOG.md` has product-history details not reproduced; `PROMPT.md` contains a wider threat model and audit checklist that is mostly summarized or deferred; the original Stage 5 handoff retains deeper file/test/history detail; `WORKFLOW.md` holds the original root-cause and scoring rationale; and the PNG presents the architecture visually without a full textual equivalent.

Therefore, the two current documents should be treated as a **Stage 5 working handoff, not a full archive replacement**. This coverage map identifies where to return to source material. It does not change implementation status, close any blocker, or establish runtime verification.

