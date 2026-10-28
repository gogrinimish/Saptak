# Privacy and File Ownership

Saptak has no account system, analytics, advertising, subscriptions or application backend. It does not upload your audio to a Saptak service or permanently import it into a private library.

## Files and permissions

You choose the audio folder. Original files remain in place and are opened read-only. Native bookmarks retain permission to reopen the selected folder. The app stores selection/bookmark preferences and the last playback queue, file URLs and position locally in its own defaults; it does not use them for tracking.

iCloud Drive and other document providers may download/cache files through operating-system services. These downloads can use local storage and are subject to provider eviction. AirPlay and document providers may use the network; this does not imply a Saptak cloud service.

## Search and sharing

Search uses names and paths in the current local library scan. Queries are not saved or sent to a service. Sharing requires an explicit action and hands the original audio to the system share interface. The OS or chosen destination may create an export copy or upload it; this is distinct from importing files into Saptak. Cloud files may need to download before sharing.

## System integration

Now Playing shares the track title, embedded artist/album and bounded artwork (when present), timing and queue context with native system media controls. It does not publish file URLs, full paths or inferred folder names as metadata. Embedded tags are read only for the current prepared playback asset and are not written back; missing artwork falls back to app artwork where available. Metadata is excluded from suggestions where the OS supports that option. System playback surfaces and Apple-managed diagnostics remain subject to operating-system behavior/settings.

The privacy manifest declares no tracking or collected data, and declares app-only UserDefaults access for retaining the selected folder and playback recovery state. Revisit the manifest and disclosures if adding dependencies or features changes these practices.

## Beta testing

TestFlight distribution and tester feedback are operated by Apple. Do not attach private audio or sensitive screenshots to public issues. Use synthetic examples when reporting problems.
