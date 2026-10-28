# Architecture

Saptak uses SwiftUI, AVFoundation, MediaPlayer and native Apple document-provider APIs, with no third-party runtime dependency.

## Portable core

`Sources/SaptakCore` contains immutable track/folder models, recursive scanning reports and the playback queue state machine. Scanning preserves hierarchy, ignores symbolic links and unsupported files, sorts naturally with deterministic tie breaks, and reports unreadable descendants without hiding readable tracks. Root failures are errors rather than empty libraries.

`PlaybackQueue` owns selection, shuffle/order restoration and repeat-off/all/one transitions. Natural completion honors Repeat One; manual Next advances. The core does not import UI, AVFoundation or file-provider APIs.

## File access and library lifecycle

`LibraryModel` owns the selected root and bookmark, refresh state and warnings. `FolderAccess` retains balanced security-scoped access while scans and playback need it. macOS bookmarks request read-only scope; iOS uses native document-provider bookmark options. Stale bookmarks are renewed without deleting existing data on failure.

Provider reads are coordinated and run away from the UI actor. iCloud files may need an OS-managed download before playback. Cancellation/generation checks discard obsolete results; a blocked provider call may still take time to return. Transient refresh failures retain the last successful tree and saved selection. Retry does not require reselecting the folder.

## Playback and system controls

`PlayerModel` is main-actor isolated and owns one AVPlayer. The core queue selects the next original URL; the player retains permission through asynchronous preparation. Failures preserve queue context and offer retry/Next. Selecting a row starts the displayed playlist there; recursive Play all includes descendants.

The current queue is a snapshot. Refresh updates folder playlists without silently changing an active queue; starting playback again uses refreshed contents. Gapless playback is not promised.

`SystemPlayback` publishes title, artwork, timing and queue context, and routes native play/pause/next/previous/seek/stop commands to PlayerModel. Only the app opts into native command ownership; injected test outputs do not claim system controls. Metadata omits file URLs and folder paths, and excludes suggestions where supported.

## Interface and project configuration

SwiftUI views use shared semantic styling and scalable typography. Mac has sidebar navigation, Tracks/Up Next tabs and a persistent player. `MacLibraryColumn` explicitly bounds header/content/footer regions so scrolling content cannot displace controls. iOS uses hierarchical navigation and an expanded player.

`project.yml` defines both native targets and shared schemes. XcodeGen also generates `Config/iOS-Info.plist`; background audio, launch metadata and versions are validated in the processed bundle. Keep account/team configuration local. Both platforms use `com.playsaptak.app`.

## Validation boundary

The package tests compile the same integration/UI sources through a Mac test wrapper. Isolated stores and injected bookmark/scan/media outputs exercise lifecycle and transport logic; they do not validate native permission grants, system command ownership, cloud providers or hardware routes. See [testing](TESTING.md) and [privacy](PRIVACY.md).

## Mobile navigation and player layout

The mobile browser uses one value-driven NavigationStack with an explicit folder-URL path. Ancestor breadcrumbs jump to a validated prefix, and refresh trims routes whose folders disappeared. Navigation titles stay inline; folder actions are available at every depth. Browsing does not replace the active playback queue.

A two-region PlayerDockLayout reserves the compact player's measured height beneath the entire navigation viewport. The player is a sibling, rather than a safe-area overlay attached outside the stack; every pushed list receives the reduced viewport. Shared mobile row styling supplies consistent content/separator insets, avoiding icon-dependent native separator offsets. Bounds and ancestry logic have automated coverage; native scrolling/gesture/accessibility acceptance remains distinct.

Mobile navigation uses a compact logo/serif brand in the toolbar while retaining the current folder's title for native Back history. The visible folder heading belongs with counts/actions in the content below its parent breadcrumbs. In the expanded iOS playback card, AirPlay is a separate header action; the five transport controls share the row below the seek bar. This keeps routing separate from playback order and leaves the Mac control layout unchanged.

Cloud-folder guidance is optional and does not intercept folder selection. Welcome copy explains native Files/Finder locations; a shared help sheet covers provider setup, provider-specific folder grants and OS-managed downloads/storage. Help is also available in the mobile folder-actions menu and Mac Change folder context menu. No provider account/token integration is implied by native picker access.

Playback recovery stores a bounded last-session queue and position in local app preferences, never audio or credentials. Recovery resolves saved track URLs only against the currently authorized scanned library, restores paused, and drops missing tracks. Positions are checkpointed during playback and on pause/background/termination. No additional file permissions are persisted. iOS interruption policy remembers playback intent, resumes only with the system's permission, and cancels automatic resumption after user actions or output disconnection.

Library search matches track/folder names across the current scanned root (case/diacritic insensitive, all query words required), without reading audio, networking or persisting queries. Results carry relative ancestry for disambiguation. Searching never alters playback; selecting a track starts its containing folder's recursive playlist at that track. Refresh replaces the searchable snapshot. Original-file sharing is explicitly user initiated, prepares native provider access off the UI actor, retains scoped access while presented and delegates to the OS sharing UI; Saptak creates no permanent import.

Playback metadata is optional presentation data, loaded asynchronously from the already-prepared current asset after playback starts. Missing/corrupt tags never block audio; filename and folder fallbacks remain. Titles/artist/album and bounded thumbnail artwork are donated to native media controls without file paths. Metadata is transient and generation-guarded, and browsing/search continue to use filenames so scanning never materializes cloud audio for tags.

Foreground library refresh uses the existing coordinated scanner with a 30-second minimum interval between automatic attempts, no overlapping automatic scans and an unrestricted manual Retry/Refresh. Failed scans preserve the last successful snapshot. Navigation falls back to the nearest surviving ancestor, search queries survive same-root refresh, and queue snapshots are never replaced by scans. Removed queued files use normal explicit playback errors and Next/retry recovery rather than silently rebuilding the queue.

## Shared typography

Alice Regular is bundled with its OFL license for app-owned text on iOS and macOS. A shared font factory registers the bundled resource and maps semantic styles to Dynamic Type; already-scaled role sizes use fixed custom fonts to avoid scaling twice. Hierarchy uses sizes, spacing and existing selected-state indicators rather than synthetic bold/italic weights. Unsupported-script glyphs may use native font fallback. OS document pickers, share sheets and system media surfaces remain platform-controlled. Font loading must fail gracefully, while packaging/registration tests catch missing resources before release.
