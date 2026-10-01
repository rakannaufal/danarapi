#!/bin/sh
set -eu

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc_bin="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
sdk_path="$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
work_dir="$(mktemp -d /tmp/danarapi-swift.XXXXXX)"
machine="$(uname -m)"
trap 'rm -rf "$work_dir"' EXIT INT TERM

"$swiftc_bin" \
  -module-cache-path "$work_dir/cache" \
  -sdk "$sdk_path" \
  -target "$machine-apple-macosx14.0" \
  apps/ios/Sources/DanarapiContracts/Money.swift \
  apps/ios/Sources/DanarapiContracts/Split.swift \
  tests/swift/main.swift \
  -o "$work_dir/golden-check"
"$work_dir/golden-check"
