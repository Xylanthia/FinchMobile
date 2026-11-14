#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
swiftc -D FINCH_EXPORT_TEST FinchMobile/Models/ARIAModels.swift \
    FinchMobile/Models/ARIA/ARIAExportJSON.swift \
    FinchMobile/Models/ARIA/ARIAHistoryStore.swift \
    tests/export-json/ExportJSONTests.swift -o "$scratch/export"
"$scratch/export"
