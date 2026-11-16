require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

extension_name = 'LANMonitorWidgetExtension'
extension_dir = 'LANMonitorWidget'
ios_version = '15.0'

existing = project.targets.find { |t| t.name == extension_name }
if existing
  puts "Target #{extension_name} already exists in project, skipping."
  exit 0
end

# 1. Create native App Extension target
extension_target = project.new_target(
  :app_extension,
  extension_name,
  :ios,
  ios_version
)

# 2. Add source group and files
extension_group = project.main_group.find_subpath(extension_dir, true)
extension_group.set_source_tree('<group>')

swift_file = "#{extension_dir}/LANMonitorWidget.swift"
if File.exist?("ios/#{swift_file}")
  ref_swift = extension_group.new_file(swift_file)
  extension_target.source_build_phase.add_file_reference(ref_swift)
end

# 3. Add Frameworks
frameworks_phase = extension_target.frameworks_build_phase
['WidgetKit', 'SwiftUI', 'Foundation'].each do |fw|
  ref_fw = project.frameworks_group.new_file("System/Library/Frameworks/#{fw}.framework")
  ref_fw.source_tree = 'SDKROOT'
  frameworks_phase.add_file_reference(ref_fw)
end

# 4. Configure build settings
extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.lanmonitor.lanMonitor.#{extension_name}"
  config.build_settings['INFOPLIST_FILE'] = "#{extension_dir}/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{extension_dir}/LANMonitorWidget.entitlements"
  config.build_settings['GENERATE_INFOPLIST_KEY_CFBundleDisplayName'] = 'LAN Monitor'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios_version
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['CODE_SIGN_IDENTITY'] = ''
  config.build_settings['DEVELOPMENT_TEAM'] = 'LANMONITOR0'
  config.build_settings['SKIP_INSTALL'] = 'NO'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
end

# NOTE: Do NOT add extension_target to Runner.dependencies and do NOT add Embed App Extensions phase.
# Building the extension via xcodebuild independently prevents any dependency cycle with Flutter Thin Binary!

project.save
puts "Successfully configured independent native target #{extension_name} in #{project_path}!"
