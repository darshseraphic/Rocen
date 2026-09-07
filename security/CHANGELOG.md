# Changelog

## [0.4.0-alpha] — Code Quality, Sync Safety, Recovery UX & Clipboard Media Overhaul

This release fixes analyzer-flagged code issues across several screens, closes a gap where syncing from GitHub could pull down and expose internal security files, resolves a case where an interrupted password change could leave the app permanently unable to complete a new password change, and adds full video support alongside a rebuilt zoom/rotation/edit/crop workflow in Clipboard's full-screen media viewer.

### Code Quality

- Resolved all outstanding `flutter analyze` warnings across `quicknote.dart`, `bookmarks.dart`, `clipboard.dart`, and `ideainbox.dart`:
  - Wrapped single-statement `if` bodies in braces per `curly_braces_in_flow_control_structures`.
  - Replaced deprecated `Color.withOpacity()` calls with `Color.withValues(alpha: ...)` throughout.
  - Migrated deprecated `Share.shareXFiles(...)` calls to `SharePlus.instance.share(ShareParams(...))`.
  - Removed an unnecessary `dart:typed_data` import already covered by `flutter/services.dart`.
  - Added `mounted` / `context.mounted` guards after `await` calls flagged by `use_build_context_synchronously`, ensuring dialogs and snackbars are never shown against a disposed `BuildContext`.

### GitHub Sync Safety

- Excluded `password_state.json` from the file list processed during a pull/refresh from GitHub, alongside the existing `device_key.json` exclusion, so neither internal security file can be surfaced to the user as a note, edited, or deleted through the notes UI.
- Confirmed the local title-uniqueness check (`titleExists`) only ever reads local device state and performs no GitHub lookup, so duplicate-title checks stay fully offline.

### Recovery & Password Change

- Fixed a case where cancelling the recovery-phrase step mid-password-change would leave the device correctly on the new password, but permanently unable to start another password change — the app would only show a dead-end **"PASSWORD CHANGE UNAVAILABLE"** dialog.
- Added a **CONTINUE** action to that dialog for this specific case, which re-prompts for the 12-word recovery phrase and, if accepted, finishes the interrupted change: re-wrapping and re-uploading `device_key.json` and confirming the pending password state with GitHub.
- Before finishing an interrupted change, the app re-checks `password_state.json` on GitHub first — if another device has since changed the password or the remote state otherwise disagrees, the existing reconciliation messaging is shown instead of publishing over it.
- Increased the height of each word box in the 12-word recovery-phrase dialogs (entry and display) from a cramped 6-words-per-row, 2-row layout to a 3-words-per-row, 4-row layout, without changing the dialog's width, so longer BIP-39 words are no longer clipped.
- Increased the font size of the words shown in the "write these down" recovery-phrase display dialog from 9 to 12 for better readability.
- Preserved all existing brutalist/minimal dialog styling (borders, spacing, button treatment) across these changes.

### Clipboard: Image + Video Support

- Clipboard's gallery and import pickers now request and accept both images and videos, not images only.
- Gallery and imported-media grids show a small play-icon overlay on video thumbnails.
- Added a full-screen video player (play, pause, seek via a scrubbable progress bar) using `video_player`, replacing the broken `Image.file` attempt on video files in the imported grid.
- Fixed video playback flicker on play/pause/replay: the video controller's `Future` was being recreated on every rebuild, which repeatedly bounced `FutureBuilder` back to its loading state; the future is now cached per item so this no longer happens.
- Fixed the video progress bar rendering mid-video instead of above the toolbar, and set its color to theme-aware black/white instead of the package's default red.
- Added ROTATE support for video (rotates only the video content, not the fixed controls), automatically hidden while that video is actively playing so it's never tappable mid-playback.

### Clipboard: Full-Screen Viewer, Zoom, Rotation & Toolbar

- Added double-tap zoom that anchors at the exact tap location (previously it always zoomed from a fixed corner regardless of where the user tapped).
- Zoom now bounces 1x → 2x → 3x → 2x → 1x on repeated double-taps, replacing an earlier wrap-around cycle.
- Manual pinch-to-zoom and the normal action toolbar's visibility are mutually exclusive, as originally specified; single-tap now fully blocks page-swipe navigation whenever the toolbar is hidden.
- Fixed the normal action toolbar to an exact 64px height with SHARE-EDIT-LIKE-BIN-COPY in five evenly divided slots, with safe-area inset handled as separate space outside that 64px rather than inflating it.
- Added image rotation (0°→90°→180°→270°→0°) that rotates only the media content; fixed navigation controls and toolbars never rotate.
- Fixed a gallery/imported-media loading performance issue: the app previously fetched every asset in the library in one call, taking 10-15+ seconds on a library of 3000+ photos and 500+ videos, and re-doing the same full fetch on every manual refresh. Loading is now windowed (90 assets per page), with more pages fetched automatically as the grid is scrolled near its end.
- Added a fast thumbnail-first display in the full-screen image viewer: the already-cached grid thumbnail shows instantly while the full-resolution file decodes in the background and fades in.

### Clipboard: Copy to Clipboard

- Implemented real system-clipboard image copying via `super_clipboard`, replacing the earlier non-functional attempt.
- Diagnosed and fixed the Android integration gap that made COPY silently do nothing while still showing a "COPIED" confirmation: the app's `minSdkVersion` was below `super_clipboard`'s required minimum of 23, and the required `super_native_extensions` content provider was missing from `AndroidManifest.xml`. Both are now correctly configured.
- COPY shows a brief "COPIED" notice (~500ms, auto-dismissing) only after a real clipboard write succeeds; genuine failures are reported honestly rather than shown as success.

### Clipboard: Crop

- Added interactive image cropping: a draggable, resizable crop rectangle with a handle on all four corners (previously only the bottom-right corner was resizable, and dragging the rectangle itself only worked when grabbing its exact border pixels rather than anywhere inside it).
- Fixed cropped images never appearing anywhere — not in the app, not in the device's file manager — despite the save reporting success. The original implementation wrote into the device-gallery asset's own plugin-managed cache directory, which is volatile, private, and not something other tools can see. Cropped images are now saved through `saver_gallery` into the device's public Pictures/Rocen album via MediaStore, exactly like a normal saved photo.
- Fixed a crop-quality bug where repeatedly re-cropping an already-cropped image would leave a visible black gap between the photo and its frame, most noticeable on small images: the crop overlay's sizing was locked in from its very first layout pass and never recalculated; it now recalculates until the user starts actively dragging, and rotation-aware sizing is now computed explicitly rather than relying on implicit widget layout behavior.
- Fixed a black-screen flicker when opening the crop tool: the image dimension lookup was being redone from scratch on every rebuild and briefly hid the photo behind a blank loading screen; it's now computed once, and the photo stays visible with a small spinner while it resolves.
- Added a "DONE" confirmation notice after a successful crop, matching the existing "COPIED" notice style.
- Repositioned the crop confirm/cancel buttons and the edit toolbar's CROP control, which the 64px toolbar change had left overlapping the crop image and, in some cases, floating mid-image instead of just above the toolbar.
- CROP remains visibly disabled and non-interactive for video, per the original design.

### Android Configuration

- Added the `READ_MEDIA_VIDEO` permission so video assets are genuinely returned after permission approval, alongside the existing `READ_MEDIA_IMAGES` and `READ_MEDIA_VISUAL_USER_SELECTED` permissions.
- Added the `super_native_extensions` content provider declaration required by `super_clipboard`, using the project's actual `applicationId`.
- Raised `minSdkVersion` to 23 via `flutter.minSdkVersion` in `local.properties`, the required floor for `super_clipboard`.
- Diagnosed and fixed an unrelated pre-existing build issue found during this work: a casing mismatch between `namespace` (`Rocen`) and `applicationId` (`rocen`) in `build.gradle.kts` was causing `ClassNotFoundException: MainActivity` on install; aligned both to lowercase `rocen` to match the Kotlin package folder and the app's existing channel-name convention.

### Dependencies

- Added `video_player`, `image`, `super_clipboard`, and `saver_gallery` — no existing dependency covered video playback, pixel-level image cropping, or binary/gallery clipboard writes.

## [0.4.0] — Security, Backup & UI/UX Overhaul

This release focuses on stabilizing GitHub backup setup, strengthening failure handling and diagnostics, refining password validation, and improving the settings interface.

### Security & Cryptography

- Improved the first-time cryptographic password setup flow and its integration with the recovery-key system.
- Preserved the existing password hashing, key derivation, encryption, hardware binding, and secure-storage architecture while refining password validation behavior.
- Removed the **“NO SAME LETTER IN UPPER + LOWER”** password restriction.
  - The rule rejected passwords when the same alphabetic letter appeared in both uppercase and lowercase forms.
  - The restriction was removed from the displayed password requirements and from the actual password-validity checks.
  - All other password requirements remain in place.
- Kept the 12-word recovery phrase as part of the password recovery flow.
- Improved failure handling so unsuccessful GitHub setup does not leave a failed credential configuration treated as a completed backup setup.

### GitHub Backup

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

### GitHub Request & Network Security

- Kept GitHub communication restricted to `https://api.github.com`.
- Preserved public-key/SPKI certificate pinning through the existing `smart_dev_pinning_plugin`.
- Fixed the custom pinned HTTP client so request data required by GitHub is passed correctly to the native secure client.
- Added an explicit `User-Agent` for GitHub API requests.
- Added explicit `Content-Type: application/json` handling for GitHub JSON requests.
- Corrected GitHub request construction for empty-repository initialization.
- Preserved UTF-8 request/response handling and Base64 processing used by the GitHub and cryptographic flows.
- Added the missing `dart:convert` import required by the pinning layer for Base64 and UTF-8 operations.
- Kept certificate-pinning behavior intact while improving request compatibility.

### GitHub Diagnostics

- Reworked GitHub 403 diagnostics so the app reports which backup operation was denied instead of always showing a generic failure.
- Distinguished repository-access failures from contents read/write failures.
- Avoided presenting hardcoded permission information as though it came directly from GitHub when the custom pinning plugin does not expose response headers.
- Included the actual GitHub response body in diagnostics where appropriate so future authorization problems can be investigated from the server's returned message.
- Added clearer messaging for cases where GitHub can see a repository but denies a specific operation.

### Settings & UI/UX

- Improved dialog typography across the settings interface.
- Dialog headlines remain bold.
- Dialog body text is displayed at regular weight rather than semi-bold.
- Preserved the existing button styling and other settings UI typography.
- Preserved the existing brutalist/minimal settings visual language while improving readability.
- Kept password requirement indicators, progress feedback, and recovery dialogs intact while adjusting the password-policy behavior.

### Reliability & Code Quality

- Corrected several integration issues encountered while stabilizing the GitHub flow, including:
  - missing declarations for repository state fields
  - missing `dart:convert` imports
  - invalid bare `return;` statements in boolean-returning asynchronous logic
  - malformed string literals in diagnostics
- Kept the current working source files aligned after successful build/run/test validation.
- The final working configuration was verified by building and testing the app successfully.

### Result

The release resolves the GitHub backup setup failure encountered during fresh installation with an empty repository, improves diagnostics for token/repository authorization failures, retains the secure pinned GitHub connection, simplifies the password policy by removing an unnecessary restriction, and refines settings dialog presentation.