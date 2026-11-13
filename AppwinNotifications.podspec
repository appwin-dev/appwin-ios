#
# CocoaPods podspec for AppwinNotifications (ADR-0020).
#
# No longer published: CocoaPods trunk is read-only from 2026-12-02 and the
# iOS SDK ships through Swift Package Manager only (the versions already on
# trunk stay installable). It serves the monorepo's showcases, by `:path`, and
# the published Flutter plugins, which read it to compile the same sources.
#
Pod::Spec.new do |s|
  s.name             = 'AppwinNotifications'
  s.version          = '1.3.0'
  s.summary          = 'Appwin Notifications SDK - push token, events, in-app messages.'
  s.description      = <<-DESC
    Notifications module of the Appwin SDK. Asks for the push permission,
    registers the APNs token, routes Appwin pushes, and fetches and presents
    the pending in-app messages. Depends on AppwinCore for identity and
    transport.
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
