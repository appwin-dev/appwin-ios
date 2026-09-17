#
# CocoaPods podspec for AppwinAttribution (ADR-0038).
#
Pod::Spec.new do |s|
  s.name             = 'AppwinAttribution'
  s.version          = '0.7.0'
  s.summary          = 'Appwin Attribution SDK - acquisition signals.'
  s.description      = <<-DESC
    Attribution module of the Appwin SDK: SKAdNetwork / AdAttributionKit
    conversion values, advertising identity (IDFA) under an opt-in consent,
    and the optional ad-network adapters. A product in its own right; it
    shares only Core's event pipeline with Analytics.
  DESC
  s.homepage         = 'https://appwin.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Appwin Studio' }
  s.author           = { 'Appwin' => 'lesignobles.studio@gmail.com' }
  # Trunk stores the podspec and fetches the sources from here, so a `:path`
  # cannot be published. The tag is the podspec version: the two move together,
  # both derived from `version.json` by the release script.
  s.source           = { :git => 'https://github.com/appwin-dev/appwin-ios.git', :tag => s.version.to_s }

  s.source_files     = 'Sources/AppwinAttribution/**/*.swift'
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.frameworks       = 'Foundation'

  s.dependency 'AppwinCore', s.version.to_s

  # Same package name as every other Appwin podspec and as `name:` in
  # Package.swift - `package` access is scoped by this string, and this module
  # crosses it: `AppwinAttribution.swift` calls `AppwinCore.startAttribution`,
  # `.setAdvertisingConsent` and `.requestTrackingAuthorization`, all declared
  # `package` in Core. A mismatch here does not warn, it reports those symbols
  # as not found.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name Appwin',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
