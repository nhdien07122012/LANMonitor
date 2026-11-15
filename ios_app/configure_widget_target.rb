require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

extension_name = 'LANMonitorWidget'
extension_dir = 'LANMonitorWidget'
main_target_name = 'Runner'
ios_version = '15.0'

main_target = project.targets.find { |t| t.name == main_target_name }
raise "Main target '#{main_target_name}' not found!" unless main_target

existing = project.targets.find { |t| t.name == extension_name }
if existing
  puts "Target #{extension_name} already exists in project, skipping."
  exit 0
end

extension_target = project.new_target(
  :app_extension,
  extension_name,
  :ios,
  ios_version
)

extension_group = project.main_group.find_subpath(extension_dir, true)
extension_group.set_source_tree('<group>')

swift_file = "#{extension_dir}/LANMonitorWidget.swift"
if File.exist?("ios/#{swift_file}")
  ref_swift = extension_group.new_file(swift_file)
  extension_target.source_build_phase.add_file_reference(ref_swift)
end

frameworks_phase = extension_target.frameworks_build_phase
['WidgetKit', 'SwiftUI', 'Foundation'].each do |fw|
  ref_fw = project.frameworks_group.new_file("System/Library/Frameworks/#{fw}.framework")
  ref_fw.source_tree = 'SDKROOT'
  frameworks_phase.add_file_reference(ref_fw)
end

extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.lanmonitor.lanMonitor.#{extension_name}"
  config.build_settings['INFOPLIST_FILE'] = "#{extension_dir}/Info.plist"
  config.build_settings['PRODUCT_NAME'] = extension_name
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios_version
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['DEVELOPMENT_TEAM'] = 'LANMONITOR0'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
end

main_target.add_dependency(extension_target)

embed_phase = main_target.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :plugins
end

unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed App Extensions'
  embed_phase.symbol_dst_subfolder_spec = :plugins
  main_target.build_phases << embed_phase
end

extension_product_ref = extension_target.product_reference
build_file = embed_phase.add_file_reference(extension_product_ref)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "Successfully added #{extension_name} native Xcode target to #{project_path}!"
