#
# CocoaPods podspec for AppwinNotifications (ADR-0020).
#
# Exists for the wrappers - Flutter plugins and the React Native bridge - whose
# iOS chain still goes through CocoaPods. A native iOS app does not need it: it
# installs through Swift Package Manager.
#
# This podspec is **not** published to the CocoaPods Trunk. It is consumed by
# path, from the package that embeds it, so the Trunk going read-only on
# 2 December 2026 does not affect us.
#
Pod::Spec.new do |s|
  s.name             = 'AppwinNotifications'
  s.version          = '0.8.0'
  s.summary          = 'Appwin Notifications SDK - push token, events, in-app messages.'
  s.description      = <<-DESC
    Notifications module of the Appwin SDK. Registers the device token, emits
    the events that trigger automations, and fetches the pending in-app
    messages. Depends on AppwinCore for identity and
    le transport.
  DESC
  s.homepage         = 'https://appwin.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Appwin Studio' }
  s.author           = { 'Appwin' => 'lesignobles.studio@gmail.com' }
  # Trunk stores the podspec and fetches the sources from here, so a `:path`
  # cannot be published. The tag is the podspec version: the two move together,
  # both derived from `version.json` by the release script.
  s.source           = { :git => 'https://github.com/appwin-dev/appwin-ios.git', :tag => s.version.to_s }

  s.source_files     = 'Sources/AppwinNotifications/**/*.swift'
  s.resource_bundles = {
    'AppwinNotifications' => ['Sources/AppwinNotifications/Resources/**/*']
  }
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.frameworks       = 'Foundation'

  s.dependency 'AppwinCore', s.version.to_s

  # Same package name as every other Appwin podspec and as `name:` in
  # Package.swift - `package` access is scoped by this string, so a mismatch
  # silently cuts this module off from Core's `package` symbols.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name Appwin',
    'DEFINES_MODULE' => 'YES'
  }
end
