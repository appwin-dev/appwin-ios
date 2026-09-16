#
# CocoaPods podspec for AppwinAnalytics (ADR-0020, ADR-0036).
#
# Fifth product of the package, and the last to get a podspec: it shipped as an
# SPM product only from 0.5.0, so pods consumers could not reach analytics at
# all. It is also the reason Core's analytics entry points are `package` rather
# than internal, which makes the shared package name below load-bearing here.
#
Pod::Spec.new do |s|
  s.name             = 'AppwinAnalytics'
  s.version          = '0.6.1'
  s.summary          = 'Appwin Analytics SDK - behavioral events, sessions, consent.'
  s.description      = <<-DESC
    Analytics module of the Appwin SDK: track, screen, flush and consent. The
    pipeline itself (persisted queue, batching, offline buffering, sessions)
    lives in AppwinCore; this product is the public surface, like AppwinSupport
    or AppwinNotifications for theirs.
  DESC
  s.homepage         = 'https://appwin.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Appwin Studio' }
  s.author           = { 'Appwin' => 'lesignobles.studio@gmail.com' }
  # Trunk stores the podspec and fetches the sources from here, so a `:path`
  # cannot be published. The tag is the podspec version: the two move together,
  # both derived from `version.json` by the release script.
  s.source           = { :git => 'https://github.com/appwin-dev/appwin-ios.git', :tag => s.version.to_s }

  s.source_files     = 'Sources/AppwinAnalytics/**/*.swift'
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.frameworks       = 'Foundation'

  s.dependency 'AppwinCore', s.version.to_s

  # Same package name as every other Appwin podspec and as `name:` in
  # Package.swift - `package` access is scoped by this string, and this module
  # is the one that actually crosses it: `AppwinAnalytics.swift` calls
  # `AppwinCore.startAnalytics`, `.track`, `.screen`, `.flush` and
  # `.setConsent`, all declared `package` in Core. A mismatch here does not warn,
  # it reports those symbols as not found.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name Appwin',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
