# ARIA (iOS)

Companion app for the ARIA handheld, built only from the handheld's own captures (live snapshot, `/api/log` history, `/api/stream`, decoded evidence pages). Joins the handheld over its ARIA-Setup Wi-Fi.

Build: GitHub Actions on macOS (`.github/workflows/build-ipa.yml`) runs XcodeGen from `project.yml`, then `BUILD_UNSIGNED_IPA.sh`.
