#!/usr/bin/env ruby
# One-shot: adds the ShareExtension app-extension target to Runner.xcodeproj
# (issue #343). Uses the xcodeproj gem so the pbxproj stays internally
# consistent rather than being hand-edited.
require 'xcodeproj'

project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

ext_name = 'ShareExtension'
app_group = 'group.org.callerscompendium.compendiumApp'
runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

if project.targets.any? { |t| t.name == ext_name }
  warn "#{ext_name} target already exists; nothing to do."
  exit 0
end

# --- Files -----------------------------------------------------------------
group = project.main_group.find_subpath(ext_name, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(ext_name)
swift_ref = group.new_reference('ShareViewController.swift')
plist_ref = group.new_reference('Info.plist')
group.new_reference('ShareExtension.entitlements')

# --- Target ----------------------------------------------------------------
ext = project.new_target(
  :app_extension, ext_name, :ios, '14.0', project.products_group, :swift
)
ext.source_build_phase.add_file_reference(swift_ref)

ext.build_configurations.each do |config|
  s = config.build_settings
  s['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.callerscompendium.compendiumApp.ShareExtension'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['CODE_SIGN_ENTITLEMENTS'] = 'ShareExtension/ShareExtension.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['MARKETING_VERSION'] = '1.0'
  s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
  s['CLANG_ENABLE_MODULES'] = 'YES'
  s['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config.name == 'Debug'
end

_ = plist_ref # referenced so it's tracked in the group

# --- Embed the .appex into the app -----------------------------------------
runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(ext.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Embed the extension BEFORE Flutter's "Thin Binary" script phase, otherwise
# the copy and the thin-binary step form a build-dependency cycle.
runner.build_phases.delete(embed)
thin_index = runner.build_phases.index do |ph|
  ph.respond_to?(:name) && ph.name == 'Thin Binary'
end
runner.build_phases.insert(thin_index || -1, embed)

# --- App group entitlement on the host app ---------------------------------
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.save
puts "Added #{ext_name} target and embedded it into Runner."
puts "App Group: #{app_group}"
