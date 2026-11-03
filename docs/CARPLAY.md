# CarPlay

## Version 0.2.0 scope

CarPlay uses Apple's native list and Now Playing templates to browse the already selected audio folder, start recursive playlists, select tracks, view the queue and control shuffle/repeat. It shares the phone's library, player, security-scoped folder access, metadata and recovery store. No second player, imports, account, network service or new dependency is introduced. Show in Files/Finder remains a phone/Mac action, never a driving interaction.

The app creates its models once and registers them with the CarPlay scene bridge during app initialization. A CarPlay-only launch restores the library and paused playback checkpoint without requiring a phone view to appear. Connecting refreshes the library through the existing throttle. Disconnecting checkpoints playback and removes scene subscriptions, without stopping audio or releasing grants still held by playback.

The Folders and Up Next tabs use bounded lists and explicit paging within vehicle item limits. When the vehicle reports restricted lists, browsing/paging is withheld and only existing playback is offered; paging never overrides that restriction. Folder navigation updates the folder list with a parent action rather than adding unbounded template depth. Selecting a track starts that folder's recursive playlist at that track. Refresh reconciles removed folders to a surviving ancestor. Queue selections verify the current snapshot before selecting. No document picker, original-file sharing/moving, typing, or source-folder selection is offered on the vehicle display. Missing access instructs the user to choose a folder on the iPhone while parked. Provider/playback errors remain recoverable.

## Distribution gate

Request Apple's audio entitlement for the existing iOS app identifier. The target declares `com.apple.developer.carplay-audio`; adding this key alone does not grant access. Device/archive signing requires Apple approval and a matching provisioning profile. Approval and a correctly entitled signed archive remain release gates.

Follow [Requesting CarPlay entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements) and [Displaying content in CarPlay](https://developer.apple.com/documentation/carplay/displaying-content-in-carplay). Native Now Playing consumes the existing MediaPlayer metadata/commands. No custom SwiftUI typography or colors are imposed on the driving UI.

## Development environment

Xcode 27.2 Device Hub currently requires a USB-connected iPhone for CarPlay; iOS Simulator is not supported for that connection. See [Apple's release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes). Use an approved entitlement/profile and physical phone with Device Hub or a vehicle; earlier Simulator workflows depend on the installed Xcode version. A generic iOS Simulator SDK build is not a CarPlay session test.

## Acceptance before release

- [ ] Apple entitlement approved; distribution profile and signed archive contain the audio entitlement.
- [ ] CarPlay Simulator: icon, phone-first and CarPlay-first launch, folder/parent navigation, large-list paging and Up Next.
- [ ] Vehicle: select tracks and folders, shuffle/repeat, steering-wheel controls, Now Playing artwork, connect/disconnect/reconnect.
- [ ] Locked phone: saved folder permissions, background playback, interruptions and provider availability; no spontaneous autoplay on connection.
- [ ] Refresh/remove/move files, unavailable provider, empty library and errors recover without a stuck selection spinner.
- [ ] iPhone/iPad scene behavior and Mac remain intact; Show in Files/Finder accepted separately.

Automated catalog/queue tests and SDK builds establish implementation behavior only, not native template or hardware acceptance.
