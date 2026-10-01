#!/bin/sh
set -eu
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc_bin="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
sdk_path="$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
work_dir="$(mktemp -d /tmp/danarapi-export-parity.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT INT TERM
"$swiftc_bin" -swift-version 6 -module-cache-path "$work_dir/cache" -sdk "$sdk_path" \
  apps/ios/Sources/DanarapiContracts/Money.swift apps/ios/Sources/DanarapiContracts/Split.swift \
  apps/ios/Sources/DanarapiContracts/ItemSplit.swift apps/ios/DanarapiApp/Domain/Models.swift \
  apps/ios/DanarapiApp/Services/ExportService.swift tests/integration/swift-export.swift -o "$work_dir/export-parity"
node --experimental-strip-types tests/integration/export-parity.ts "$work_dir/export-parity" "$work_dir"
