#!/bin/sh
set -eu

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftc_bin="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
platform_path="$developer_dir/Platforms/MacOSX.platform/Developer"
sdk_path="$platform_path/SDKs/MacOSX.sdk"
work_dir="$(mktemp -d /tmp/danarapi-swift-typecheck.XXXXXX)"
machine="$(uname -m)"
target="$machine-apple-macosx14.0"
trap 'rm -rf "$work_dir"' EXIT INT TERM

"$swiftc_bin" \
  -parse-as-library -emit-module \
  -emit-module-path "$work_dir/DanarapiContracts.swiftmodule" \
  -module-cache-path "$work_dir/cache" \
  -module-name DanarapiContracts -enable-testing \
  -swift-version 6 -strict-concurrency=complete \
  -sdk "$sdk_path" -target "$target" \
  apps/ios/Sources/DanarapiContracts/*.swift

"$swiftc_bin" \
  -typecheck -module-cache-path "$work_dir/cache" \
  -swift-version 6 -strict-concurrency=complete \
  -sdk "$sdk_path" -target "$target" \
  -I "$work_dir" -I "$platform_path/usr/lib" \
  -F "$platform_path/Library/Frameworks" \
  apps/ios/Tests/DanarapiContractsTests/*.swift

echo "Swift source and XCTest type-check passed."

ios_platform="$developer_dir/Platforms/iPhoneSimulator.platform/Developer"
ios_sdk="$ios_platform/SDKs/iPhoneSimulator.sdk"
ios_target="arm64-apple-ios17.0-simulator"

find apps/ios/DanarapiApp apps/ios/Sources/DanarapiContracts -name '*.swift' -print0 |
  xargs -0 "$swiftc_bin" \
    -parse-as-library -emit-module -enable-testing -Xfrontend -disable-sandbox \
    -swift-version 6 -strict-concurrency=complete \
    -target "$ios_target" -sdk "$ios_sdk" \
    -module-cache-path "$work_dir/ios-cache" -module-name Danarapi \
    -emit-module-path "$work_dir/Danarapi.swiftmodule"

"$swiftc_bin" \
  -typecheck -Xfrontend -disable-sandbox \
  -swift-version 6 -strict-concurrency=complete \
  -target "$ios_target" -sdk "$ios_sdk" \
  -module-cache-path "$work_dir/ios-cache" \
  -I "$work_dir" -I "$ios_platform/usr/lib" \
  -F "$ios_platform/Library/Frameworks" \
  apps/ios/DanarapiAppTests/*.swift

"$swiftc_bin" \
  -typecheck -Xfrontend -disable-sandbox \
  -swift-version 6 -strict-concurrency=complete \
  -target "$ios_target" -sdk "$ios_sdk" \
  -module-cache-path "$work_dir/ios-cache" \
  -I "$ios_platform/usr/lib" \
  -F "$ios_platform/Library/Frameworks" \
  apps/ios/DanarapiAppUITests/*.swift

echo "Full iOS app, XCTest, and UI test source type-check passed."
