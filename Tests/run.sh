#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
sources=(ARIA/Sources/ARIA/ARIAListFilter.swift ARIA/Sources/ARIA/ARIAModels.swift ARIA/Sources/ARIA/ARIAActionCommand.swift ARIA/Sources/ARIA/ARIAOverviewCatalog.swift)
swiftc "${sources[@]}" Tests/OverviewTests.swift -o "$scratch/overview"
"$scratch/overview"
swiftc "${sources[@]}" Tests/ActionTests.swift -o "$scratch/actions"
"$scratch/actions"
swiftc "${sources[@]}" ARIA/Sources/ARIA/ARIAHistoryStore.swift Tests/BootSessionTests.swift -o "$scratch/session"
"$scratch/session"
