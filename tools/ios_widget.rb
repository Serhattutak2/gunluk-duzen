# Xcode projesine widget eklentisini, paylaşılan dosyaları ve yetkileri ekler.
# Derlemeden önce CI'da çalışır; tekrar çalıştırılırsa bir şey değiştirmez.
require 'xcodeproj'

root = File.expand_path('../mobile/ios/App', __dir__)
proj = Xcodeproj::Project.open(File.join(root, 'App.xcodeproj'))
app = proj.targets.find { |t| t.name == 'App' } or abort('App hedefi yok')
if proj.targets.any? { |t| t.name == 'GunlukWidget' }
  puts 'Widget zaten ekli'
  exit 0
end

mv = app.build_configurations.map { |c| c.build_settings['MARKETING_VERSION'] }.compact.first || '1.0'
app_grp = proj.main_group['App'] or abort('App grubu yok')
shared_grp = proj.main_group.new_group('Shared', 'Shared')
w_grp = proj.main_group.new_group('GunlukWidget', 'GunlukWidget')

shared = shared_grp.new_file('BahceShared.swift')
app_files = %w[BahcePlugin.swift MainViewController.swift Shortcuts.swift].map { |f| app_grp.new_file(f) }
app.add_file_references(app_files + [shared])
app_grp.new_file('App.entitlements')

w = proj.new_target(:app_extension, 'GunlukWidget', :ios, '17.0', nil, :swift)
w.add_file_references([w_grp.new_file('GunlukWidget.swift'), shared])
w.add_resources([w_grp.new_file('Assets.xcassets')])
w_grp.new_file('Info.plist')
w_grp.new_file('GunlukWidget.entitlements')

w.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.serhattutak.gunlukduzen.widget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'GunlukWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'GunlukWidget/GunlukWidget.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['MARKETING_VERSION'] = mv
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

app.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/App.entitlements'
end

app.add_dependency(w)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(w.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

proj.save
puts "Widget eklendi (sürüm #{mv})"
