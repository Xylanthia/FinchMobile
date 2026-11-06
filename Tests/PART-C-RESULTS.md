# Part C — ARIA Overview

Implemented C1–C7 in ARIA-iOS only. No firmware or FinchMobile changes.

The old card read only Wi-Fi decode.fingerprint_attempts[].device_class. The typed Wi-Fi/BLE models did not retain the firmware category. BLE was never included in phone/computer counts. Models now preserve category, and the Overview projection consumes it without inferring device type from Apple/Samsung/HP/Microsoft vendor names.

The card groups nonempty categories, shows numeric LIVE NOW / TOTAL SEEN, prioritizes ALPR/gunshot/drone, and includes successful Sub-GHz decodes only. Validated Remote ID identities are deduplicated by UAS ID; fingerprint detections are deduplicated against radio records by radio/address. Control-link candidates are excluded. The footer retains the existing history/radio explanation and adds the fingerprint-only qualification.

The read-only capabilities endpoint supplies detections and validated RID observations to an Overview-only persistent catalog. Existing exports and radio-list data paths are unchanged. Firmware device last_seen_ms is an age; detection/RID last_seen_ms and capture ts_ms are uptime values. The projection converts those to sighting dates and expires live counts at 60 seconds. Historical records without a known sighting time count only toward totals. Disconnected live counts are zero. Totals survive app relaunch in Application Support/aria-overview.json.

Priority rows reuse ARIAWiFiDetail with a category-filtered record selector and the existing field/JSON components. Default Wi-Fi navigation remains unchanged. The radar and other tabs/screens were not edited.

Validation:
- Swift 6 compilation and executable regression tests: PASS (ARIAModels + ARIAOverviewCatalog + Tests/OverviewTests.swift).
- Regression coverage: 101 BLE phones, vendor-only exclusion, category preservation, unknown-device retention, BLE history address normalization, decode status filtering, duplicate RID/detection identities, priority ordering, raw matched-pattern retention, persistence, empty rows, disconnection, stale/future sightings and exact 60-second cutoff.
- Swift syntax parse of modified coordinator/views: PASS.
- Protected-source comparisons and git diff --check: PASS.
- Full iOS build/IPA: submitted separately to the existing macOS build-ipa.yml workflow for build 7. Linux Swift checks do not type-check SwiftUI against the iOS SDK.
- Real iPhone navigation/rendering/live handheld acceptance: NOT RUN.

IPA build requested; installation remains a user step. Existing vendor-only captures remain unclassified until firmware supplies category; vendor names are not proof of phone/computer class.
