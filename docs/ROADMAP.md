# Roadmap

A checked implementation item does not imply all platform/device acceptance is complete. Saptak remains in development.

## Phase 0 — Technical Validation
- Goal/deliverables: native folder selection, persistent access, recursive scanning, direct playback and codec validation without permanent imports.
- [x] Mac and iOS Simulator SDK builds; deterministic scanning, queue, permissions-lifecycle and source-read tests.
- [x] Basic Mac selection/relaunch, playback, refresh and OPUS manual acceptance.
- [ ] iOS local/iCloud selection/relaunch and real playback acceptance.
- [ ] Cloud-only/inaccessible files, unchanged originals across playback, and supported-OS/container matrix.
- Dependencies: Xcode, signed device access and representative providers/audio.
- Status: In progress. Risks: provider availability, scope expiry, downloads and codec/container differences.

## Phase 1 — Core MVP
- Goal/deliverables: usable folder browsing, recursive playlists, queue, shuffle/repeat, seeking, AirPlay and native interfaces.
- [x] Implementation and automated regression coverage; basic Mac manual acceptance.
- [x] Mobile ancestry/route validation and bounded player layout implemented with regression coverage.
- [x] Initial physical iOS-to-Mac AirPlay playback verified.
- [ ] Remaining iOS/device, additional AirPlay routes, accessibility and complete platform acceptance.
- Dependencies: Phase 0 file-access guarantees and native playback.
- Status: Implementation present, acceptance incomplete. Risks: asynchronous transitions, unavailable tracks and hardware routing.

## Phase 2 — Playback Experience
- Goal/deliverables: background listening, system controls, persistence and metadata/refresh improvements.
- [x] Native Now Playing/remote commands and automated tests; basic Mac Control Center/media-key acceptance.
- [x] Basic physical iOS Control Center and lock-screen playback-control acceptance.
- [ ] Background/interruptions and detailed system ownership/cleanup acceptance.
- [x] Last-session queue/position recovery implemented; restore paused against the authorized library with missing-track handling.
- [x] iOS interruption/headphone-disconnection policy implemented with automated regression coverage.
- [x] Basic saved-position recovery across quit/relaunch verified by tester.
- [x] Basic call-interruption behavior verified by tester.
- [ ] Recovery edge cases (missing/cloud-only files), manual-pause interruption cases and output-disconnection/route acceptance.
- [x] On-playback embedded metadata/artwork with filename fallbacks and bounded thumbnails.
- [x] Throttled foreground refresh, preserved navigation/search, and nearest-surviving-folder recovery.
- [ ] Device/provider metadata and foreground-refresh acceptance.
- Dependencies: stable core queue and lifecycle behavior.
- Status: In progress. Risks: system command ownership, interruptions and stale URLs.

## Phase 3 — Offline Experience
- Goal/deliverables: explicit availability controls, safe cache management, original/download distinction and storage visibility.
- [ ] Implement and validate all storage/availability controls.
- Dependencies: provider availability model and stable MVP.
- Status: Deferred; retain current provider-managed availability. Risks: provider eviction and storage accounting.

## Phase 4 — Cloud Integrations
- Goal/deliverables: optional direct Google Drive integration beyond native Files/Finder access, provider abstraction, secure authentication and reliable playback.
- [ ] Design, implement and validate provider/authentication behavior.
- Dependencies: provider architecture, credentials and storage semantics.
- Status: Not started. Risks: token security, API limits and maintenance.

## Phase 5 — Chromecast
- Goal/deliverables: Google Cast integration, remote playback and authorized receiver-accessible media.
- [ ] Validate discovery, routing and playback on hardware.
- Dependencies: casting architecture decision, hardware and stable provider interfaces.
- Status: Not started. Risks: receiver access to private files and dependency scope.

## Phase 6 — Product Polish
- Goal/deliverables: search, accessibility, refined UI, original-file sharing and distribution/open-source preparation.
- [x] Native theme, icon and bounded Mac layout with automated tests.
- [x] Bundled Alice typography and accessible in-app font license.
- [ ] Updated typography acceptance on physical devices, including large text and unsupported-script fallback.
- [x] Search tracks and folders by name throughout the selected library, with relative paths and folder-playlist playback context.
- [x] Original-file sharing via native transfer UI, provider preparation and retained scoped access.
- [x] Basic iOS search verified by tester.
- [ ] Mac search UI, search edge cases and native share/provider acceptance, including cloud-only files and share destinations.
- [ ] Full accessibility acceptance.
- [x] TestFlight build distributed (availability confirmed by tester).
- [x] Reproducible screenshot capture with synthetic audio; helpers excluded from Release builds.
- [x] Prepare reviewed iPhone, iPad and Mac screenshot sets and README previews.
- [ ] Upload selected App Store screenshots.
- [x] Prepare a responsive product website, screenshots and public-facing privacy page.
- [x] Publish the [product website](https://gogrinimish.github.io/Saptak/).
- [x] Release the [MIT-licensed source repository](https://github.com/gogrinimish/Saptak).
- [ ] Complete App Store preparation and submission.
- Dependencies: stable MVP, release-account access and review.
- Status: In progress. Risks: device acceptance and distribution requirements.
