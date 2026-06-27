#!/usr/bin/env ruby
# Adds the "VoxClawWidgets" WidgetKit app-extension target to VoxClawIOS.xcodeproj
# and embeds it into the host app. Idempotent: re-running is a no-op if the target
# already exists. Source files live in VoxClawIOS/VoxClawWidgets/ and are listed
# explicitly here (the host app uses synchronized groups, but the extension does not).
#
# Usage:  ruby Scripts/add_widget_extension.rb
require "xcodeproj"

PROJECT  = "VoxClawIOS/VoxClawIOS.xcodeproj"
EXT_NAME = "VoxClawWidgets"
APP_NAME = "VoxClawIOS"
BUNDLE   = "com.malpern.voxclaw.widgets"
SOURCES  = ["VoxClawWidgets/VoxClawWidgets.swift"]

project = Xcodeproj::Project.open(PROJECT)

if project.targets.any? { |t| t.name == EXT_NAME }
  puts "Target #{EXT_NAME} already exists — nothing to do."
  exit 0
end

app = project.targets.find { |t| t.name == APP_NAME } or abort "App target #{APP_NAME} not found"

ext = project.new_target(:app_extension, EXT_NAME, :ios, "26.0", nil, :swift)

ext.build_configurations.each do |config|
  bs = config.build_settings
  bs["PRODUCT_BUNDLE_IDENTIFIER"] = BUNDLE
  bs["PRODUCT_NAME"]              = "$(TARGET_NAME)"
  bs["INFOPLIST_FILE"]           = "VoxClawWidgets/Info.plist"
  bs["GENERATE_INFOPLIST_FILE"]  = "NO"
  bs["IPHONEOS_DEPLOYMENT_TARGET"] = "26.0"
  bs["SWIFT_VERSION"]            = "6.0"
  bs["SKIP_INSTALL"]             = "YES"
  bs["TARGETED_DEVICE_FAMILY"]   = "1,2"
  bs["SWIFT_EMIT_LOC_STRINGS"]   = "YES"
  bs["CODE_SIGN_STYLE"]          = "Automatic"
  bs["LD_RUNPATH_SEARCH_PATHS"]  = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
end

# Source group + file references (relative to the group's path).
group = project.main_group.find_subpath(EXT_NAME, true)
group.set_source_tree("<group>")
group.set_path(EXT_NAME)
SOURCES.each do |rel|
  ref = group.new_reference(File.basename(rel))
  ext.source_build_phase.add_file_reference(ref)
end
group.new_reference("Info.plist") # referenced via INFOPLIST_FILE, not built

# Host app depends on + embeds the extension.
app.add_dependency(ext)
embed = app.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins }
embed ||= app.new_copy_files_build_phase("Embed Foundation Extensions")
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ""
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

project.save
puts "Added #{EXT_NAME} target and embedded it into #{APP_NAME}."
