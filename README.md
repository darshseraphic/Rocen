### ROCEN // THE COMPLETE TECHNICAL SYSTEM MANIFESTO & REFERENCE MANUAL

**DOCUMENT VERSION:** 2026.8.28

**CORE ENGINEER:** DARSHSERAPHIC

**DESIGN MATRIX:** STRICT LOW-FI BRUTALIST ARCHITECTURE

**SECURITY MODEL:** ZERO-KNOWLEDGE, HARDWARE-BOUND, GITHUB-BACKED LOCAL-FIRST WORKSPACE


### 01 // SYSTEM OVERVIEW & THE INTENTIONAL MANIFESTO

<p align="center">
  <img src="https://github.com/user-attachments/assets/cad9b75d-f291-4440-b783-e5b91df4642b" alt="1" width="19%" />
  <img src="https://github.com/user-attachments/assets/fc9284d5-4a05-4b77-995a-c7fa94a250ca" alt="2" width="19%" />
  <img src="https://github.com/user-attachments/assets/56d43090-c6a8-43c4-b02c-f77ef61483c2" alt="3" width="19%" />
  <img src="https://github.com/user-attachments/assets/1e9c0644-2890-45e0-a47e-f411f5528a03" alt="4" width="19%" />
  <img src="https://github.com/user-attachments/assets/d9ea101d-1111-4d82-9fff-43873347ea0b" alt="5" width="19%" />
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/8e70c7a5-8e1b-4c21-9f8b-5a5fb15c974c" alt="6" width="19%" />
  <img src="https://github.com/user-attachments/assets/0b6f336f-7300-4f8a-8806-8d4aacf39638" alt="7" width="19%" />
  <img src="https://github.com/user-attachments/assets/8c6eff91-4444-405f-8532-fada5adedf62" alt="8" width="19%" />
  <img src="https://github.com/user-attachments/assets/9f43db63-8a18-43d0-b8ed-9ccab5f47564" alt="9" width="19%" />
  <img src="https://github.com/user-attachments/assets/be3f0825-880d-424b-9485-65430f1680d0" alt="10" width="19%" />
</p>

#### 1.1 The Problem Statement

Modern mobile engineering is experiencing an era of massive aesthetic and structural bloat — apps saturated with dopamine-loop design patterns, layered drop-shadows, and unnecessary cloud interdependencies. A separate, quieter problem sits underneath that one: most "private" note apps ask you to trust a company's server with your data, a company's uptime with your access, and a company's business model with your privacy — forever, with no way to verify any of it yourself.

#### 1.2 The Rocen Protocol

**Rocen** is a highly focused, low-fidelity, brutalist mobile workspace that rejects both problems at once. It is local-first (your data lives on your device, full stop) and, for anyone who wants cross-device backup, **zero-knowledge GitHub-backed** — meaning your encrypted data can leave your device, but only into a GitHub repository *you* own, using *your* access token, encrypted with a key that never leaves your device in a form anyone else could use. Nobody — not GitHub, not the developer of this app, not anyone who gains read access to your repo — can read your notes without your password and, if needed, your 12-word recovery phrase.

Rocen discards decorative elements: no animations beyond deliberate, purposeful state transitions, zero rounded button edges, zero color-depth gradients. Data entry is a raw pipeline; everything about the interface is built to get out of the way of your thoughts.

#### 1.3 Where This App Is Right Now

Rocen is early — built solo, and still moving fast. That's not a caveat tucked away to cover myself; it's an invitation. I'm actively looking for people to use it day-to-day, push on the parts that feel rough, and tell me what breaks. **[Discord](https://discord.gg/Jc5EErKm4n)** — bug reports, UI complaints, feature requests, "this confused me," all of it is useful right now.

Two different things are true about the state of this project, and it's worth being upfront about both rather than picking one to emphasize: the day-to-day experience — sync, note-taking, the UI — has been stable through regular daily use, including my own. Separately, the cryptography follows correct, standard primitives (Argon2id, AES-256-GCM, hardware-backed Keystore — see §04), but hasn't yet been through an independent third-party security audit. If you're using Rocen for everyday notes, ideas, and tasks, jump in — that's exactly the kind of use that helps most right now. If you're planning to store something where a cryptographic flaw would be genuinely costly to you, know that going in, and treat that decision as your own call rather than mine to make for you. §14 tracks exactly what's been verified, what's pending, and what's already been found and fixed along the way.


### 02 // FEATURE MATRIX

Rocen ships five focused tools inside one brutalist shell:

| Feature | What it does |
|---|---|
| **QuickNote** | The core writing surface. Notes can optionally be password-encrypted and backed up to your own GitHub repo. |
| **To-Do List** | A minimal task list with an animated completion strikethrough — check something off, watch the line grow through it. |
| **Idea Inbox** | A calendar-anchored capture space for ideas and events tied to specific dates. |
| **Media Registry** | Browse your device gallery and import media into the app's local workspace. Media is **never** backed up remotely — see §4.6. |
| **Settings** | Password setup/rotation, GitHub backup configuration, recovery phrase management, and a full on-device Privacy Policy panel that reports your device's actual security posture (StrongBox vs. TEE, rooted/modified device detection). |

Every screen shares the same visual language: sharp 0.8px borders, uppercase monospace-leaning type, and a signature dark-red (`#5F0E0D`) accent used consistently for text selection across every input field in the app.


### 03 // TECHNICAL STACK

```
+-----------------------------------------------------------------------+
|                       ROCEN RUNTIME LAYER TREE                        |
+-----------------------------------------------------------------------+
| UTILITY LAYER:        Settings / Recovery / GitHub Backup Config      |
+-----------------------------------------------------------------------+
| INTERFACE SANDBOX:    QuickNote / To-Do / Idea Inbox / Media Registry |
+-----------------------------------------------------------------------+
| STATE CONTAINER:      Riverpod Reactive Notifier Engine               |
+-----------------------------------------------------------------------+
| CRYPTOGRAPHY LAYER:   Argon2id + AES-256-GCM, isolated + RAM-pinned   |
+-----------------------------------------------------------------------+
| HARDWARE TRUST LAYER: AndroidKeyStore (StrongBox / TEE)               |
+-----------------------------------------------------------------------+
| LOCAL DISK ENCLOSURE: Hive Embedded Key-Value Memory Box Containers   |
+-----------------------------------------------------------------------+
| SYNC LAYER:           GitHub REST API, certificate-pinned, per-user   |
+-----------------------------------------------------------------------+
| NATIVE SYSTEM ENGINE: Flutter / Dart, obfuscated release builds       |
+-----------------------------------------------------------------------+
```

- **UI:** Flutter, hardware-accelerated Skia/Impeller rendering, strict integer/0.8px sizing to keep every border crisp.
- **State:** Riverpod — no `setState` tree-walking, state mutations broadcast directly to listening widgets.
- **Local storage:** Hive, an embedded NoSQL key-value store. No SQL schema, no migrations to maintain, memory-resident once a box is opened.
- **Cryptography:** the `cryptography` Dart package (Argon2id, AES-GCM), `crypto` (SHA-256, used for certificate pin hashing), `ffi` (native RAM-locking).


### 04 // SECURITY ARCHITECTURE — THE FULL BREAKDOWN

This is the part that actually matters, so it gets the longest section. Every claim below reflects what the code actually does, not aspirational design goals.

#### 4.1 The Password

Your cryptography password is **8 to 32 ASCII characters**, with composition rules that are deliberately strict — not just "one of each type," but:

- 2 **unique** uppercase letters (not the same letter twice)
- 2 **unique** lowercase letters
- 2 **unique** digits
- 2 **unique** symbols
- The same letter can't appear as both its uppercase and lowercase form (no `Aa` pairs padding out two categories with what's visually one letter)

**In plain terms:** no character category can be satisfied by repeating the same key twice. `AA12!!bb` fails — the uppercase pair and symbol pair each repeat the same character. `AB12!@bc` passes — every character within each category is genuinely different from its pair.

At the 8-character floor, requiring 2 of each of 4 categories uses the entire minimum length — so at exactly 8 characters, this isn't "at least," it mathematically forces **exactly** 2 of each. Past 8 characters, the same 5 rules still apply (you still need at least 2 unique of each category somewhere in the password), but the extra characters up to the 32-character ceiling are free-form — any allowed character, in any position, is fine once the floor is met. The password-creation screen shows all 5 rules live, each one animating a strikethrough as it's satisfied.

**On length specifically:** the input is a single flowing field (not fixed character boxes — that changed from an earlier version of this app), obscured with the app's own `#` glyph rather than a generic dot, so there's no visual ceiling suggesting a fixed length. Argon2id's cost parameters do the heavy lifting against brute-force regardless of where in the 8–32 range you land, but length still matters on top of that — a longer password is a larger keyspace no matter how expensive each individual guess is. Previously this app enforced an exact 8-character length as a shipped constraint; that ceiling has since been lifted to 32, resolving the roadmap item that was tracked in §14 as of the last revision of this document.

#### 4.2 Key Derivation & Encryption

- **KDF:** Argon2id, both for the local authentication hash and for deriving the AES key used per encryption operation. Parameters are **adaptive**: standard cost on a normal device, automatically bumped to a higher memory/iteration cost if the device is detected as rooted (§4.5) — raising the bar for brute-force specifically on devices where the OS itself may already be compromised.
- **Cipher:** AES-256-GCM. Every encryption operation generates a fresh random salt and nonce — nothing is ever reused across notes or across saves of the same note.
- **Storage format:** `[version byte][salt][nonce][MAC][ciphertext]`, base64-encoded. Versioned from day one so the format can evolve without breaking old data.
- **Password verification:** constant-time comparison — no early-exit byte comparison that could leak timing information about how much of a guess was correct.
- **Brute-force throttling:** failed attempts trigger exponential lockout (30s → 60s → 300s, doubling from there), not a flat retry limit.

#### 4.3 Isolated Cryptography

Argon2id and AES-GCM never run on the UI thread. Every derive/encrypt/decrypt call runs inside a spawned Dart `Isolate` — a separate memory space from the main app, created fresh for that operation and torn down when it's done. This keeps the (relatively expensive, deliberately slow) Argon2id computation from ever freezing the interface, and keeps derived key material physically separated from the isolate handling your UI and network calls.

#### 4.4 Memory Hygiene: Zeroing and RAM Pinning

Two layers here, working together:

- **Explicit zeroing:** every sensitive byte buffer — derived keys, decrypted plaintext, the comparison hashes used during password verification — is overwritten with zeros the moment it's no longer needed, inside `try/finally` blocks so zeroing happens even if an error occurs mid-operation.
- **RAM pinning:** those same buffers are allocated on the *native* heap (outside Dart's garbage collector, via direct FFI calls to `mlock`/`munlock`) and best-effort locked into physical RAM so the OS can't page them out to disk/swap while they're live. This is genuinely best-effort — `mlock` is denied outright on plenty of stock Android ROMs (`RLIMIT_MEMLOCK` caps) — and when it's denied, encryption/decryption proceeds completely normally regardless. Pinning succeeding or failing never blocks or breaks the app; it's a bonus hardening layer, not a dependency.

**The one honest limitation this can't reach:** the password *as you type it*, and decrypted note text *as displayed on screen*, live in Dart's native `String` type at some point — and Dart Strings are immutable and garbage-collected, meaning they can't be forcibly zeroed or pinned by application code. This is a structural constraint of the language runtime, not a gap in effort — every byte buffer that *can* be controlled, is.

#### 4.5 Root & Tamper Detection

On launch, Rocen checks for common root indicators — `su` binaries in standard paths, known root-management packages (Magisk, SuperSU, and others), `test-keys` build tags. The response is **adaptive, not punitive**: a rooted device isn't locked out or feature-restricted. Detecting root silently raises the Argon2id cost parameters for that device, and the on-device Privacy Policy panel discloses the detection plainly to the user rather than pretending the device is in a fully trusted state.

#### 4.6 Hardware-Backed Key Storage (StrongBox / TEE)

Two AndroidKeyStore AES-256-GCM keys, separate aliases, one per purpose — **password verification** and **GitHub token protection** — with different protection models for each:

**Password verification chain:** hardware-bound directly. A correct password match is necessary but not sufficient — the app also has to successfully unwrap a hardware-encrypted copy of the stored hash using that device's specific Keystore key. If the Keystore entry is gone (app reinstall, factory reset, or the storage being moved to a different device entirely), that check **intentionally fails even with the correct password**, and the user is routed to recovery via the BIP-39 phrase (§4.7) instead. This means storage theft alone — pulling the Hive box off the device via root or ADB backup — is never enough to get in, even with a correct password in hand, because the hardware half of the check can't be extracted or replicated off-device. This check fails closed on any unexpected error from the platform Keystore call as well — an exception here denies the check rather than defaulting to pass, per the fix noted in §14.

**GitHub access token:** protected in two layers, not one. The token is always encrypted first with your password-derived key (the same software encryption used for your notes), and that already-encrypted blob is then additionally hardware-wrapped using the second Keystore alias. So the password-derived layer is the floor — always applied — and the hardware wrap is a second layer on top when the device's Keystore/StrongBox cooperates. **Current known gap:** if hardware-wrapping fails on a given device (Keystore unavailable, StrongBox error, OS quirk), the app currently falls back to storing the password-encrypted-only blob **without surfacing that failure to the user** — the token is never left unencrypted, but it can silently lose its second protective layer with no visible indication. Debug logging for this fallback exists for developer-side diagnosis; a user-facing indicator does not yet. Tracked in §14.

Key generation tries **StrongBox** first (a physically separate secure-element chip, where present) and falls back to the **TEE** (Trusted Execution Environment) if StrongBox isn't available on that specific device — the tier actually achieved is independently verified via `KeyInfo`, not just inferred from which code branch ran, and the Privacy Policy panel reports which tier your device landed on.

#### 4.7 Recovery: BIP-39

A 12-word recovery phrase is generated at setup. Combined with your password (concatenated into a single secret, not used as two separate independent checks), it's run through Argon2id to wrap your local authentication salt for cross-device recovery — this is the sanctioned path back in if local storage and hardware keys are both lost (new phone, factory reset, reinstall). Without both the password *and* the phrase together, there's no backdoor — including for the developer of this app.

**This path is software-only, not hardware-bound.** Unlike §4.6's password-verification check, recovery via the phrase doesn't involve the Keystore at all — its strength comes entirely from Argon2id's cost parameters plus the phrase's own entropy (~128 bits for a 12-word BIP-39 phrase), not from device-specific hardware. Practically, this means: an attacker who has both your password *and* your recovery phrase can decrypt your data on any device, not only your original one — which is the intended behavior for a recovery mechanism, but worth understanding plainly rather than assuming it inherits the same hardware-binding property described in §4.6.

#### 4.8 GitHub Backup: Zero-Knowledge By Architecture

If you choose to enable it, backup works like this:

```
      [ YOUR DEVICE ]                          [ YOUR GITHUB REPO ]
   password + AES-GCM  ------ciphertext------>   encrypted notes
   never leaves device        only                device_key.json
                          (your token,             (itself encrypted,
                        your repo, your auth)      Argon2id-wrapped)
```

- **You bring your own GitHub Personal Access Token and repository.** The developer of this app never sees, stores, receives, or has any access path to any user's token, repo, or data — there is no shared server in this picture at all.
- **Only ciphertext is ever written.** Note content is AES-GCM encrypted before it's pushed. `device_key.json` — the file that lets a *different* device recover access — is itself wrapped via Argon2id-derived-from-(password + recovery phrase), never stored raw.
- **Single-commit-amend sync strategy:** each sync force-pushes a fresh root commit rather than growing an ever-longer commit history — keeps the repo lean indefinitely regardless of how many times you sync over the years.
- **Certificate pinning:** the connection to `api.github.com` pins the server's actual certificate directly (loaded into a locked-down `SecurityContext` via `setTrustedCertificatesBytes`, with `badCertificateCallback` kept only as a defense-in-depth backstop) — so even a compromised or otherwise-OS-trusted rogue Certificate Authority can't transparently intercept sync traffic; nothing validates unless it presents that exact certificate. This is leaf-certificate pinning (a real `dart:io` platform constraint means true CA-level pinning isn't achievable in pure Dart) with two pin slots and, critically, an **auto-expiring, fail-open safety valve**: past a fixed date, or if no certificate is ever configured, pinning silently deactivates back to completely ordinary system TLS trust. It can only ever make an already-working connection *more* resistant to interception for a bounded window — it can never turn a working connection into a broken one, at any point, even if the pin is never renewed again.
- **Media is never synced.** Photos and other media stay 100% local, by design — git and GitHub's API aren't built for many-small-binary-blob workloads, and keeping media out of the sync payload entirely means the repo never bloats regardless of how much media you accumulate locally over time.

**Why this scales to any number of users with zero added cost or risk to anyone:** because every install talks only to its own owner's GitHub repo via its own owner's token, there is no shared backend to overload, no central database, and no server the developer runs or pays for. The load on GitHub's infrastructure from 10 installs versus 10 million installs is identical *per user* — there's no aggregation point where usage could ever bottleneck.

#### 4.9 Release Build Hardening

- **R8/ProGuard:** minification and resource shrinking enabled on release builds.
- **Dart obfuscation:** release APKs are built with `--obfuscate`, scrambling class/method/variable names in the compiled code, paired with `--split-debug-info` so crash stack traces can still be decoded from developer-held symbol files that are never shipped inside the APK itself.
- **Native symbol stripping:** handled automatically by the Android build toolchain (AGP) as part of a properly configured release build.

#### 4.10 The Honest Threat Model

Every security system protects against *something*, not *everything* — stating the boundary plainly is more trustworthy than pretending it doesn't exist.

**Rocen protects against:**
- Physical device theft or loss
- Storage extraction (ADB backup, direct file copy, forensic imaging of a powered-off device)
- A compromised or rogue Certificate Authority intercepting the GitHub sync connection
- Someone with read access to your GitHub repo (including the repo host itself) reading your actual note content
- Casual or automated scraping — there is no telemetry, no analytics, no tracking of any kind

**Rocen does not, and structurally cannot, protect against:**
- A fully compromised operating system — root-level malware or a hostile ROM reading its own process memory while the app is actively unlocked and running
- The moment of correct password entry itself being observed, keylogged, or shoulder-surfed
- A person being coerced into revealing their password or recovery phrase

If a device is rooted, Rocen doesn't lower its guard silently — it detects the condition, raises its own cost parameters in response, and discloses it to the user (§4.5). That's the most honest position available to any app running inside an environment it doesn't fully control.


### 05 // FAILSAFE & RECOVERY BEHAVIOR

If a local write is interrupted (a sudden battery cutout mid-save, for example), Rocen runs an integrity check on boot:

```
                  [ COLD RESTART INITIATION ]
                              |
                              v
                [ TEST CONTAINER INTEGRITY ]
                              |
             +----------------+----------------+
             |                                 |
    (Verification Clear)             (Exception Thrown)
             |                                 |
             v                                 v
   [ MOUNT APPLICATION ]             [ PURGE CORRUPT CONTAINER ]
                                               |
                                               v
                                     [ ALLOCATE EMPTY CELL ]
                                               |
                                               v
                                     [ ENGINE RESET BOOT ]
```

This prevents a single corrupted local write from ever hard-locking the app.


### 06 // PRIVACY POLICY

**What Rocen collects:** nothing. There is no analytics SDK, no crash reporter phoning home, no usage telemetry, no advertising identifier, no third-party tracking of any kind compiled into this app. This isn't a settings toggle you can find and disable — the code paths simply don't exist.

**What leaves your device:** only what you explicitly choose to back up, and only in encrypted form. If you never enable GitHub backup, nothing about your notes, tasks, or ideas ever touches a network connection. If you do enable it, the only things that leave your device are:
- AES-256-GCM encrypted note content (§4.2) — unreadable without your password
- `device_key.json` — your recovery data, itself wrapped via Argon2id-derived key material (§4.7), never stored in a usable raw form

**Who can access your data:** you, and only you, with your password (plus your 12-word recovery phrase if you're restoring on a new device). The developer of this app has no account system, no server, and no technical mechanism to view, access, or recover any user's data — GitHub sync goes directly from your device to a repository you own, using a token you generated and control. Support requests along the lines of "can you recover my notes" have exactly one honest answer: only if you still have your password or recovery phrase, because nobody else ever holds a copy of either.

**Media (photos/gallery imports):** stays 100% local, always. It is never included in any backup, never encrypted for transit, never leaves your device through this app under any circumstance — this is a deliberate design choice, not a missing feature (§4.8).

**Root/tamper detection:** the app checks for signs your device may be rooted or modified, purely to adapt its own encryption cost parameters upward (§4.5). This check never phones out, never reports anything to anyone — it's a purely local, defensive decision your device makes about itself.

**Third parties in this picture:** exactly one — GitHub, because that's where *you* chose to store *your* encrypted backup, under *your* account. Rocen's author is not a third party in your data's story at all; there is no path by which we receive it.


### 07 // HOW YOUR DATA IS ACTUALLY PROTECTED (PLAIN-LANGUAGE VERSION)

Section §04 above is the full technical breakdown. If you want the short version:

1. **Your notes are encrypted with a key derived from your password** — not the password itself, a key mathematically derived from it using Argon2id, a deliberately slow, memory-hungry algorithm built specifically to resist brute-force guessing.
2. **That password is also bound to your specific phone's hardware** — even someone who steals your password *and* your phone's storage still can't get in without the physical device's secure hardware chip cooperating (§4.6).
3. **If your device is compromised (rooted), the app doesn't pretend everything's fine** — it quietly makes the encryption harder to break as a direct response (§4.5).
4. **If you lose your phone entirely,** your 12-word recovery phrase — which only you have, written down somewhere safe — is the one and only way back in. There is no "forgot password" email link, because that would mean someone else could access your data too.
5. **If you back up to GitHub,** what lands there is meaningless ciphertext to anyone but you — including to GitHub itself, and including to the developer of this app.


### 08 // USER GUIDE — SETTING UP AND USING ROCEN AT MAXIMUM SECURITY

#### 8.1 First Launch: Creating Your Password

You'll be asked to create an 8–32 character password meeting 5 composition rules (§4.1) — the setup screen shows you live, animated feedback for each one as you type, so you'll know immediately what's still missing. A few honest notes:

- This password cannot be recovered by anyone if you forget it and also lose your recovery phrase. Choose something you can reliably remember, or store it in a password manager you trust — don't rely on memory alone for something this consequential.
- Longer is genuinely stronger here — Argon2id's computational cost is the main defense regardless of length, but a longer password within the 8–32 range still means a larger keyspace on top of that. There's no reason to stay at the 8-character floor if you're comfortable typing more.

#### 8.2 Your Recovery Phrase — The Single Most Important Step

Immediately after password setup, you'll be shown a 12-word BIP-39 recovery phrase (§4.7). This is not optional busywork:

- **Write it down physically.** Paper, notebook, whatever — something that isn't a screenshot, isn't in cloud photo backup, isn't in a notes app on the same or another connected device.
- **Store it somewhere separate from your phone.** If your phone and your recovery phrase are lost together, both are gone together.
- **Never type it into anything except Rocen's own recovery screen.** No legitimate reason will ever exist for this phrase to be requested by email, chat, or any website.
- **This phrase, combined with your password, is the only way to regain access** if your phone is lost, factory reset, or the app is reinstalled. There is no other recovery mechanism — that absence is what makes the encryption meaningful in the first place.

#### 8.3 Enabling GitHub Backup (Optional, Recommended for Cross-Device Safety)

1. Create a **dedicated GitHub repository** for this purpose — ideally **private**, and ideally not reused for anything else.
2. Generate a **Personal Access Token** scoped as narrowly as GitHub allows — repository-level access to that one repo is enough; avoid tokens with broad account-wide permissions if you can help it. A leaked narrow-scope token is a much smaller problem than a leaked broad one.
3. Enter the token and repository path in Rocen's settings. From this point, your notes sync automatically as encrypted ciphertext (§4.8).
4. If you ever suspect your token has leaked, **revoke it immediately** from GitHub's own settings (Settings → Developer settings → Personal access tokens) — this takes effect instantly and costs you nothing but re-entering a fresh token in the app.

#### 8.4 Daily Use

Encryption and decryption happen transparently once you're unlocked — you won't see Argon2id or AES-GCM at work, you'll just see your notes. A few things worth knowing:

- The app will feel briefly "slow" specifically during password verification and note decryption — that's Argon2id being deliberately expensive on purpose (§4.2). This is a feature working correctly, not a performance bug.
- Backup happens on your explicit action (saving a backup-enabled note, or manually refreshing) — not as a constant background process draining your battery or data.
- If you're offline, backup-dependent actions will tell you plainly rather than fail silently or queue up unpredictably.

#### 8.5 Changing Your Password

Settings → change password. Your existing notes remain accessible — the underlying encryption key derivation is re-anchored to your new password, not thrown away and rebuilt from scratch. Your recovery phrase stays valid throughout.

#### 8.6 If Something Goes Wrong

| Situation | What to do |
|---|---|
| Forgot your password, still have your phone | Use "Forgot Password" → recovery phrase flow in-app |
| Lost or replaced your phone | Install Rocen on the new device → recovery phrase + GitHub repo restores your data |
| Suspect your GitHub token leaked | Revoke it immediately in GitHub settings, generate a fresh one, re-enter it in Rocen |
| Suspect your device itself is compromised | Change your password from a device you trust, and treat anything typed on the suspect device as potentially exposed — no app-level fix changes that |
| Lost both your password AND your recovery phrase | There is no recovery path. This is intentional — the alternative would mean someone else could also get in |

#### 8.7 The "Maximum Security" Checklist

- [ ] Password meets all 5 composition rules (the app won't let you proceed otherwise)
- [ ] Recovery phrase written down physically, stored separately from your phone
- [ ] GitHub backup enabled to a **private**, dedicated repository
- [ ] GitHub token scoped as narrowly as possible
- [ ] You understand that a rooted or compromised device changes what this app can promise you, no matter how strong the encryption is (§4.10)
- [ ] You haven't stored your recovery phrase anywhere digital, searchable, or cloud-synced


### 09 // CROSS-DEVICE SYNC, OFFLINE ENCRYPTION & DATA PORTABILITY

**Cross-device use:** your notes aren't tied to one phone. Install Rocen on a new device, choose recovery during setup, enter your password and 12-word phrase, and the app pulls `device_key.json` from your GitHub repo, unwraps it, and reconstructs local access — same notes, same password, different hardware. The device-binding described in §4.6 is specific to *that device's* Keystore; the recovery phrase is what makes moving between devices possible at all.

**Offline encryption:** encryption and decryption are entirely local operations — Argon2id and AES-GCM run on-device regardless of whether you have a network connection. You can create, edit, and read encrypted notes with your phone in airplane mode all day long. The *only* thing that requires connectivity is the GitHub sync step itself — pushing or pulling ciphertext. If you're offline, the app tells you plainly (§8.4) rather than pretending to sync and failing silently.

**Data export & import:** independent of GitHub backup, Rocen can export your captured items (notes, tasks, ideas) to a portable JSON schema, and import from that same format back in. This exists as a personal-backup/migration path that doesn't depend on GitHub at all — useful if you want a local file copy, or you're moving data between two independently-configured installs. Note that export produces the data in the form the app holds it in at rest; if you have password-encrypted notes, exported content reflects that encryption, not plaintext.


### 10 // WHY THE INTERFACE FEELS SMOOTH (PERFORMANCE ARCHITECTURE)

None of this is accidental — each area got specific engineering attention:

**Media Registry (gallery):**
- Thumbnails are cached in-memory the first time they're loaded (keyed by asset ID), so scrolling back to an already-seen image never re-decodes it.
- `gaplessPlayback` is enabled on every thumbnail `Image` widget — this prevents the brief blank/flicker frame Flutter normally shows while an image is reloading or being replaced.
- Thumbnails are explicitly requested in **PNG format**, not the platform default (JPEG) — this matters specifically because JPEG has no alpha channel, so a transparent-background image would otherwise get flattened onto a black backing by the OS *before Flutter ever sees it*. Requesting PNG preserves real transparency all the way through.
- A loading-state tracker ensures the same thumbnail is never fetched twice concurrently if you scroll past it quickly and back.

**To-Do List:**
- Task completion uses a `TweenAnimationBuilder` driving a `ClipRect`/`Align(widthFactor: ...)` strikethrough that animates left-to-right over ~600ms with an `easeOutQuart` curve — the line doesn't just appear, it *grows through* the text.
- The checkbox itself uses `AnimatedContainer` for its fill/border transition — both animations run on the compositor, not via full-widget rebuilds, which is why they stay smooth even on modest hardware.

**Idea Inbox (calendar):**
- Date math (day-of-year, leap-year handling) is done with lightweight local calculation rather than pulling in a heavy date-arithmetic library — keeps the calendar view snappy since there's no library overhead on every render.
- "Add Event" capture is a focused two-field (title/description) flow rather than a heavy form, so idea capture stays fast specifically because it doesn't try to do more than it needs to.


### 11 // COMPLETE CRYPTOGRAPHIC WORKFLOW — STEP BY STEP

**What actually happens when you create your password:**
1. You type an 8–32 character password meeting all 5 composition rules (§4.1).
2. A random salt is generated.
3. Argon2id derives a hash from your password + that salt, using standard or hardened cost parameters depending on whether root was detected (§4.5) — this runs inside a spawned Isolate (§4.3), never on the UI thread.
4. The salt and hash are stored together (`salt:hash` format) — never your raw password.
5. That same hash gets hardware-wrapped (§4.6) using your device's password-purpose AndroidKeyStore key, and the wrapped result is stored alongside it as an additional device-binding layer.
6. A 12-word BIP-39 phrase is generated and shown to you once (§4.7) — combined with your password, it wraps your auth salt into `device_key.json`, ready to push to GitHub if/when you enable backup.

**What happens every time you unlock the app:**
1. You type your password.
2. Argon2id re-derives a hash from your input + your stored salt (same cost parameters as setup).
3. That result is compared to your stored hash using a **constant-time comparison** (§4.2) — timing-safe, so a partial match can't be inferred from response speed.
4. If it matches, the app additionally hardware-unwraps your stored wrapped-hash (§4.6) and confirms it matches too — both checks have to pass.
5. Every buffer touched in this process — the freshly derived hash, the stored comparison hash — is zeroed and RAM-unpinned the instant the comparison finishes (§4.4).

**What happens when you save an encrypted note:**
1. A fresh random salt and nonce are generated for *this specific save* — never reused, even for the same note's next edit.
2. Argon2id derives an AES-256 key from your password + that new salt, inside an isolate.
3. AES-GCM encrypts your note content with that key and nonce, producing ciphertext + an authentication tag (MAC).
4. Everything is packed into `[version][salt][nonce][MAC][ciphertext]` and base64-encoded for storage.
5. The derived key is zeroed and released from RAM-pinned memory immediately after the encrypt call returns.

**What happens when you open an encrypted note:**
1. The stored package is unpacked back into its salt/nonce/MAC/ciphertext components.
2. Argon2id re-derives the same AES key from your password + the note's stored salt.
3. AES-GCM decrypts and verifies the MAC in one step — if the ciphertext or MAC has been altered even slightly, decryption fails outright rather than returning corrupted plaintext.
4. The decrypted bytes are copied into RAM-pinned memory, decoded to text, and the original (unpinned) copy that crossed the isolate boundary is zeroed immediately (§4.4) — the one hop that can't be fully closed, by Dart's own design.


### 12 // SCREEN SECURITY: SCREENSHOT PREVENTION & BACKGROUND BLACKOUT

Rocen can toggle Android's native `FLAG_SECURE` window flag on sensitive screens. Two effects come from this one flag, together:

- **Screenshots and screen recordings are blocked system-wide** while it's active — any attempt returns a black or empty capture, enforced by Android itself, not something a malicious app on the same device could bypass through the screenshot API.
- **The app's preview in the Recents/app-switcher view is blanked to a black rectangle** instead of showing your actual notes — this is standard OS behavior tied to the same flag, not a separate mechanism Rocen built. The practical effect: someone picking up your unlocked phone and swiping through your open apps sees a blank tile where your notes would otherwise be visible, rather than a live preview of whatever you were last reading.


### 13 // THE GITHUB SYNC PIPELINE — FETCH, PUSH, AND WHY --AMEND

**Reading data (fetch):**
- `listNoteFiles()` — lists everything in your repo's contents directory.
- `fetchNoteFile(name)` — pulls one file, base64-decodes it, parses it back into structured data.

Both go through the certificate-pinned client (§4.8) and your Personal Access Token in the request headers — nothing here is anonymous or unauthenticated.

**Writing data (the sync/upload process):**
1. Fetch the current branch ref's commit SHA (if the branch already exists).
2. Fetch that commit's tree SHA — this becomes the `base_tree`, i.e., everything currently in the repo that isn't being touched by this particular sync.
3. Build a list of tree entries for whatever actually changed: files to upsert (new content), files to delete, files to rename.
4. Create a **new tree** combining the base tree with those changes.
5. Create a **new commit** pointing at that tree — with **no parent commit** (`parents: []`), meaning every single commit Rocen ever creates is a fresh root commit, not a continuation of history.
6. **Force-push** the branch reference to point at this new commit, overwriting whatever it pointed to a moment ago.

**Why this "force-push a fresh root commit" strategy, instead of normal incremental commits:**
- **Every save re-encrypts with a fresh random salt and nonce (§4.2 — nothing is ever reused), which means even a one-character edit produces an entirely different ciphertext blob for that note, not a small diff.** A normal incremental-commit strategy would mean daily use accumulates one full new ciphertext blob per save, indefinitely — years of daily notes would mean years of full encrypted blobs stacked in git history, growing the repo without bound. Force-pushing a fresh root commit means the repo only ever holds your *current* encrypted state, regardless of how many times you've saved.
- **No merge conflicts, ever** — since each push is a clean snapshot built from the *current* remote tree, there's no divergent-history scenario to reconcile.
- **Simpler mental model for a security tool specifically:** the repository *is* your current encrypted state, not an auditable log of every past state. For most apps that's a downside; for a zero-knowledge backup tool, minimizing how much old ciphertext lingers around by default is the right instinct.

**The honest caveat, stated plainly because this is a security document:** force-pushing over a ref doesn't *instantly* destroy the previous commit — the old commit object becomes unreachable ("dangling") from the branch, but it can still exist on GitHub's servers until their own periodic garbage collection eventually cleans it up. In practice this is a narrow, time-limited window and the dangling object is still just ciphertext (meaningless without your password), not a meaningful exposure — but "gone the instant you push" would be an overstatement, and this document would rather be exactly accurate than reassuring.


### 14 // KNOWN LIMITATIONS & ROADMAP — STATED PLAINLY

Every claim in §04–§13 describes what the code currently does. This section exists separately, to state clearly what hasn't happened yet and what's still a tradeoff, rather than let those items sit quietly inside sections that otherwise read as fully resolved.

**Resolved since this section was first written:**
- The password length cap (previously fixed at exactly 8 characters) has been raised to a range of 8–32, with the composition rules unchanged — see §4.1.
- A code-review pass found that the hardware-binding check in password verification (§4.6) failed open on an unexpected Keystore exception — meaning an error there could have been silently treated as a passed check rather than a failed one. This has been fixed to fail closed. It's mentioned here rather than left unstated because a security document that only ever describes success isn't a credible one — catching and fixing this is a normal, expected part of the process this README already asks readers to trust (§15's "read it, test it, find bugs").

These are removed from the list below because they're shipped, not because the wording was softened.

**Not yet independently verified.** Nothing in this document has been confirmed by a third-party security audit or penetration test. The cryptographic primitives (Argon2id, AES-256-GCM, hardware-backed Keystore) are standard and correctly chosen, and this README describes the implementation as accurately as possible — but a README is a claims document written by the author, not independent verification. Rocen is early (built over ~3 months by a single developer) and is being published publicly specifically so the implementation can be read, built, and tested by anyone who wants to check it — see §15 for exactly what that license permits. A completed third-party audit, once one happens, will be linked here.

**RAM pinning is best-effort, not guaranteed** (§4.4). On many stock Android ROMs, `mlock` is denied by the OS outright, and pinning silently fails without blocking the app. This is disclosed here directly: treat pinning as a bonus hardening layer that may or may not be active on your specific device, not a property you can rely on.

**Certificate pinning has a bounded, auto-expiring window** (§4.8). It's leaf-certificate pinning (a `dart:io` platform constraint, not a shortcut), and it's designed to fail open to ordinary system TLS trust past a fixed date or if unconfigured — meaning it can only make a working connection *more* resistant to interception for a bounded period, never turn a working connection into a broken one. Renewal depends on the developer shipping updated pins over time.

**Force-pushed commits can dangle on GitHub's servers temporarily** (§13). Force-pushing over a ref doesn't instantly erase the previous commit object — it becomes unreachable from the branch but may persist until GitHub's own garbage collection runs. The dangling object is ciphertext only, not plaintext, but "gone the instant you push" would overstate it.

**GitHub access token's hardware-wrap layer can fail silently to the user** (§4.6). The token is always protected by password-derived encryption — that layer is never skipped. On top of it, a second Keystore-backed hardware wrap is applied when the device supports it. If that second layer fails (Keystore unavailable, StrongBox error, OS quirk), the app currently falls back to the password-encrypted-only form without telling the user, though it does log this internally for developer-side diagnosis as of this writing. The token is never left unencrypted in either case — the gap is visibility into which protection tier is actually active on a given device, not exposure of the token itself. A user-facing indicator (matching the tier reporting already shown for password verification) is planned.

**Recovery-phrase path is software-only, not hardware-bound** (§4.7). Unlike password verification, restoring access via the 12-word phrase doesn't route through the Android Keystore — its strength rests on Argon2id's cost plus the phrase's own entropy. This is expected, correct behavior for a cross-device recovery mechanism (hardware-binding a *recovery* path to one specific device's chip would defeat its purpose) — stated here so it isn't assumed to inherit §4.6's hardware guarantee.

**Source is publicly viewable and forkable for testing, but not open-source in the OSI sense.** You can read it, build it, and modify your own copy (§15). You cannot publish a modified version, run it as a competing service, or redistribute it. This is a deliberate choice to allow real scrutiny while preventing resale — see §15 for the exact terms.

**No formal bug bounty program exists yet.** If you find a vulnerability, the intended path is a pull request or a direct email to the address in §15 — there's currently no structured disclosure process or reward beyond that.

This section will be updated as items resolve — a shipped fix means a section here changes from "planned" to gone, not softened language while nothing has actually shipped.


### 15 // LICENSE

**Rocen Proprietary Software License v1.1 — Copyright © 2026 Darshseraphic. All Rights Reserved.**

The full license text lives in the [`LICENSE`](./LICENSE) file at the root of this repository — read that for the complete, authoritative terms. The summary below is for orientation only and is not a substitute for it.

Publishing this source code publicly does not place it in the public domain. The license is written to encourage real, hands-on security review while stopping the code from being resold or repackaged elsewhere. Specifically:

- **Read it, build it, run it, break it.** You're welcome to clone or fork the repo, build it from source, and modify your own copy — for testing, bug-hunting, security review, or personal use.
- **Send fixes back.** If you find something, patches and pull requests to the official repository are the intended path — that's what this permission exists for.
- **Don't publish, distribute, or sell your fork.** Publishing a modified or unmodified copy anywhere other than back to this repository, running it as a service for others, incorporating it into another product, or any commercial use — is not permitted without prior written permission.
- **Don't misrepresent origin.** Claiming a fork or modified version as your own original work, or removing attribution, is not permitted.
- **Use of this code (or Rocen's name/branding) to train, fine-tune, or evaluate an AI/ML model is explicitly prohibited.**
- The software is provided with no warranty, and — specifically relevant given what this app is — **no guarantee that it protects against every possible security threat, device compromise, or data loss scenario.**

**In short:** test it as hard as you want, on your own machine. Don't republish it, run it as a competing service, or sell it.

For licensing requests, commercial permission, or anything not covered by the above: **Darsh.seraphic@gmail.com**

<p align="center">
DEVELOPED BY <b>DARSHSERAPHIC</b>
</p>