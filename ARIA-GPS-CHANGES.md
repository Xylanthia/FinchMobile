# Finch 3.2 ARIA / GPS candidate

Uses the existing native SwiftUI, Observation and MVVM coordinator stack and the original 3.2 build script. ARIAClient URL, port, endpoints and protocol are unchanged.

## Artifacts

`ipa/FinchMobile.ipa` remains the original 3.2 build 35 binary. `ipa/FinchMobile-3.2-ARIA-GPS-working-copy.ipa` is an identical baseline copy, not a compiled update. SHA-256 evidence is in `ipa/ARIA-GPS-copy-manifest.json`.

On a Mac with Xcode, run `./BUILD_ARIA_GPS_IPA.sh`. It stages the current source and original build script in a fresh temporary directory and writes only `ipa/FinchMobile-3.2-ARIA-GPS.ipa`. It refuses to overwrite that candidate. Do not use the existing publishing workflow for this candidate: that workflow replaces the latest release.

## UI and connection

Engage opens Overview. Nearby, Tracks and Drone retain their screens. More contains Scan, Network, ARIA registry controls, Session / Export, and the existing Command tools. This resolves the request for five named bottom items plus two additional screens by placing the latter under More.

Overview contains the band links, radar, device counts and a shared header. RSSI ranges are estimates; bearings are illustrative, not directional measurements. UAS without RSSI is placed at the outer ring, not geolocated by radar. Unknown classification counts are shown as a dash. The sweep pauses in background and is omitted with Reduce Motion.

The existing local-network privacy declarations remain, with clearer usage text. Bonjour browsing of the already-declared `_http._tcp` performs the pre-flight; no `_aria` advertisement was found in the firmware. A missing SSID no longer blocks the fixed-endpoint probe. Foreground return rechecks connection, polling updates shared state, and all three screens offer refresh.

## GPS correlation

ARIA JSON share and Vault export add `finch_collection` to each dictionary observation in wifi, ble, subghz/captures, uas and rfid. Original firmware fields remain intact; raw source bytes are retained in the coordinator's session. Unchanged records in consecutive snapshots retain their first phone-receipt fix. Changed records receive a new receipt fix. Device capture time is not inferred from the phone polling time; buffered firmware observations may predate collection. A record removed from one snapshot and later reintroduced is treated as a new receipt.

Metadata contains collector role, source, UTC phone receipt time, GPS fix time, coordinates, horizontal accuracy, available altitude/vertical accuracy and fix age. Core Location may use fused positioning rather than satellite-only GPS. Fixes older than 15 seconds, invalid fixes, missing fixes and denied permission are explicitly marked unavailable; coordinates are omitted. The phone position is never represented as the target position.

BLE and network host models also retain `collectorLocation` through JSON/Vault exports. BLE dedicated JSON carries it, and SENTINEL host CSV adds corresponding columns. These models aggregate observations; their fields describe the latest merged sighting, not a historical event log. Existing remote UAS coordinates are preserved separately.

## Validation

In the Linux workspace: plist/asset parsing, unchanged transport diff, original/copy SHA-256 comparison, build-script shell syntax and `git diff --check` passed. No Swift compiler, Xcode, iOS SDK or attached iPhone was available, so the app has not been compiled or device-tested. GPS regression cases were added alongside the existing XCTest sources; this repository does not currently configure an XCTest target, so they require adding to a test target on macOS before running.

Device acceptance checks:

- Fresh install: see Join ARIA-Setup guidance and local-network prompt before ARIA HTTP; grant access, join the AP and return from Settings.
- Check SSID-hidden, permission-denied/re-enabled, AP-offline, reconnect and foreground-return cases; verify header updates and refresh completes.
- Exercise Scan chips, previous-scan refresh, Network refresh/actions/export, band links and More tools.
- Walk between two GPS fixes: unchanged ARIA captures must retain their receipt coordinates; updated BLE observations must receive the newer fix. Verify export timestamps/accuracy and preservation of drone target coordinates.
- Deny location or let the fix become stale: exports must mark GPS unavailable without fabricated coordinates.
- Validate VoiceOver, large text, landscape, Reduce Motion and radar performance on the target iPhone.
