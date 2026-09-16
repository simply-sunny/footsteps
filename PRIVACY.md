# Privacy

Footsteps is a source-only, local-first iOS location diary. It has no app account, analytics SDK, advertising, developer-operated server, or CloudKit sync.

## What stays on your device

The app stores raw Core Location observations in a versioned SwiftData store: coordinates, timestamps, reported accuracy, altitude, speed, course, floor, sensor-source flags, reception time, session ID, and foreground/background state. Negative sensor sentinels are retained. Derived routes and places are computed locally.

The store uses iOS file protection `completeUntilFirstUserAuthentication`. Unlock the device once after each reboot before background recording can access the store. This is not a promise of uninterrupted background recording.

## Apple services and backups

MapKit may contact Apple to load map content. Location and Health services operate under Apple's permissions and privacy policies. “Local-first” does not mean zero network requests across all system frameworks. The app does not exclude its store from iOS device backups; your Apple backup settings apply.

## Permissions you control

- Location: allow access to record your diary. For background use, choose Always and enable Precise Location in iOS Settings. You can turn off Background Recording in the app's Settings.
- Health: optional, read-only step counts requested when you tap a Health step button in a detail view. Footsteps does not write Health data. Missing or unreadable data displays as unavailable, not zero.
- Revoke permissions in iOS Settings at any time. Removing the app removes its local container; copies in device backups may remain according to your backup settings.

## Limits

No cloud recovery or in-app export is shipped yet. Do not delete or reinstall the app to troubleshoot without preserving data you need. High-fidelity location recording uses energy; battery impact has not been established by a controlled field test.

This documentation site is hosted by GitHub Pages, whose hosting privacy terms apply. It uses bundled scripts, no analytics, and synthetic preview data. Document switching makes no network requests.
