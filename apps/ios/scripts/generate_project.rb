#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "Danarapi.xcodeproj")
signing_team = ENV["DANARAPI_SIGNING_TEAM"]
if File.exist?(File.join(project_path, "project.pbxproj"))
  existing = Xcodeproj::Project.open(project_path)
  signing_team ||= existing.targets.find { |target| target.name == "Danarapi" }&.build_configurations&.first&.build_settings&.fetch("DEVELOPMENT_TEAM", nil)
end
project = Xcodeproj::Project.new(project_path)

base_config = project.main_group.new_file("Configuration/Base.xcconfig")

app = project.new_target(:application, "Danarapi", :ios, "17.0")
share = project.new_target(:app_extension, "DanarapiShare", :ios, "17.0")
app.add_dependency(share)
embed = app.new_copy_files_build_phase("Embed App Extensions")
embed.dst_subfolder_spec = "13"
embed.add_file_reference(share.product_reference).settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
unit_tests = project.new_target(:unit_test_bundle, "DanarapiAppTests", :ios, "17.0")
ui_tests = project.new_target(:ui_test_bundle, "DanarapiAppUITests", :ios, "17.0")
unit_tests.add_dependency(app)
ui_tests.add_dependency(app)

# xcodeproj may emit a version-pinned SDK path from the gem's build-time Xcode.
# Keep system framework references portable across installed Xcode versions.
project.files.select { |file| file.path&.end_with?("Foundation.framework") }.each do |file|
  file.path = "System/Library/Frameworks/Foundation.framework"
  file.source_tree = "SDKROOT"
end

app_group = project.main_group.new_group("Application")
app_sources = Dir.glob(File.join(root, "DanarapiApp/**/*.swift")) + Dir.glob(File.join(root, "Sources/DanarapiContracts/*.swift"))
app_refs = app_sources.sort.map { |path| app_group.new_file(path.delete_prefix(root + "/")) }
app.add_file_references(app_refs)

shared_group = project.main_group.new_group("Share Intake")
shared_refs = Dir.glob(File.join(root, "SharedIntake/*.swift")).sort.map { |path| shared_group.new_file(path.delete_prefix(root + "/")) }
app.add_file_references(shared_refs)
share.add_file_references(shared_refs)
extension_group = project.main_group.new_group("Share Extension")
share.add_file_references(Dir.glob(File.join(root, "DanarapiShare/*.swift")).sort.map { |path| extension_group.new_file(path.delete_prefix(root + "/")) })
extension_group.new_file("DanarapiShare/Info.plist")
extension_group.new_file("Configuration/Share.entitlements")

test_group = project.main_group.new_group("Tests")
unit_refs = Dir.glob(File.join(root, "DanarapiAppTests/*.swift")).sort.map { |path| test_group.new_file(path.delete_prefix(root + "/")) }
ui_refs = Dir.glob(File.join(root, "DanarapiAppUITests/*.swift")).sort.map { |path| test_group.new_file(path.delete_prefix(root + "/")) }
unit_tests.add_file_references(unit_refs)
ui_tests.add_file_references(ui_refs)

resources = project.main_group.new_group("Shared Resources")
privacy = resources.new_file("DanarapiApp/PrivacyInfo.xcprivacy")
tokens = resources.new_file("../../contracts/design-tokens.json")
fixture = resources.new_file("../../tests/fixtures/demo-seed-v1.json")
import_fixture = resources.new_file("../../tests/fixtures/import-v1.json")
ledger_fixture = resources.new_file("../../tests/fixtures/ledger-v1.json")
item_fixture = resources.new_file("../../tests/fixtures/item-split-v1.json")
[privacy, tokens, fixture, import_fixture, ledger_fixture, item_fixture].each { |ref| app.resources_build_phase.add_file_reference(ref) }
share.resources_build_phase.add_file_reference(privacy)
app.resources_build_phase.add_file_reference(resources.new_file("DanarapiApp/Assets.xcassets"))
app.resources_build_phase.add_file_reference(resources.new_file("../../contracts/product-content.json"))
app.resources_build_phase.add_file_reference(resources.new_file("../../contracts/calculators/catalog.json"))
app.resources_build_phase.add_file_reference(resources.new_file("../../contracts/calculators/engine.js"))
Dir.glob(File.join(root, "DanarapiApp/Resources/*")).sort.each do |path|
  app.resources_build_phase.add_file_reference(resources.new_file(path.delete_prefix(root + "/")))
end
app.resources_build_phase.add_file_reference(resources.new_file("../../apps/web/public/licenses/Google-Sans-OFL.txt"))

project.build_configurations.each { |configuration| configuration.base_configuration_reference = base_config }
app.build_configurations.each do |configuration|
  configuration.base_configuration_reference = base_config
  configuration.build_settings.merge!(
    "INFOPLIST_FILE" => "DanarapiApp/Info.plist",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "PRODUCT_BUNDLE_IDENTIFIER" => "id.danarapi.app",
    "PRODUCT_NAME" => "Danarapi",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "TARGETED_DEVICE_FAMILY" => "1,2",
    "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
    "DEVELOPMENT_ASSET_PATHS" => ""
  )
  configuration.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  configuration.build_settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  configuration.build_settings["CODE_SIGN_ENTITLEMENTS"] = "Configuration/Share.entitlements"
end

share.build_configurations.each do |configuration|
  configuration.base_configuration_reference = base_config
  configuration.build_settings.merge!(
    "INFOPLIST_FILE" => "DanarapiShare/Info.plist",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "PRODUCT_BUNDLE_IDENTIFIER" => "id.danarapi.app.share",
    "PRODUCT_NAME" => "DanarapiShare",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete",
    "TARGETED_DEVICE_FAMILY" => "1,2",
    "APPLICATION_EXTENSION_API_ONLY" => "YES",
    "SKIP_INSTALL" => "YES",
    "CODE_SIGN_ENTITLEMENTS" => "Configuration/Share.entitlements"
  )
end

unit_tests.build_configurations.each do |configuration|
  configuration.base_configuration_reference = base_config
  configuration.build_settings.merge!(
    "GENERATE_INFOPLIST_FILE" => "YES",
    "PRODUCT_BUNDLE_IDENTIFIER" => "id.danarapi.app.tests",
    "SWIFT_VERSION" => "6.0",
    "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/Danarapi.app/Danarapi",
    "BUNDLE_LOADER" => "$(TEST_HOST)"
  )
end

ui_tests.build_configurations.each do |configuration|
  configuration.base_configuration_reference = base_config
  configuration.build_settings.merge!(
    "GENERATE_INFOPLIST_FILE" => "YES",
    "PRODUCT_BUNDLE_IDENTIFIER" => "id.danarapi.app.uitests",
    "SWIFT_VERSION" => "6.0",
    "TEST_TARGET_NAME" => "Danarapi"
  )
end

project.targets.each do |target|
  target.build_configurations.each do |configuration|
    configuration.build_settings["DEVELOPMENT_TEAM"] = signing_team if signing_team
    configuration.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  end
end
project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, unit_tests, launch_target: true)
scheme.launch_action.xml_element.attributes["selectedDebuggerIdentifier"] = ""
scheme.launch_action.xml_element.attributes["selectedLauncherIdentifier"] = "Xcode.IDEFoundation.Launcher.PosixSpawn"
scheme.add_build_target(ui_tests, false)
scheme.add_test_target(ui_tests)
scheme.save_as(project_path, "Danarapi", true)

puts "Generated #{project_path}"
