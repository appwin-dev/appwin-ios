#
# CocoaPods podspec for AppwinSupport (ADR-0019, ADR-0020).
#
# Support product of the Appwin SDK. Depends on AppwinCore, which must be
# available in the host app's Podfile - through :path in development, or the
# same git URL in production.
#
# DEV : `pod 'AppwinSupport', :path => '.../sdk/support/AppwinSupport'`
# in the Podfile, and the same for AppwinCore.
#
Pod::Spec.new do |s|
  s.name             = 'AppwinSupport'
  s.version          = '0.1.0'
  s.summary          = 'SDK Support Appwin - messenger natif iOS (pattern Intercom).'
  s.description      = <<-DESC
    Module Support du SDK Appwin (cf. ADR-0019, ADR-0020). UI native
    SwiftUI, stores, repositories and the `/sdk/support/v1/**` backend
    integration. Depends on AppwinCore for device identity and networking.
  DESC
  s.homepage         = 'https://appwin.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Appwin Studio' }
  s.author           = { 'Appwin' => 'lesignobles.studio@gmail.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Sources/AppwinSupport/**/*.swift'
  s.resource_bundles = {
    'AppwinSupport' => ['Sources/AppwinSupport/Resources/**/*']
  }
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.frameworks       = 'Foundation', 'UIKit', 'SwiftUI'

  # The `import AppwinCore` in the Support code requires this pod to be
  # available on the consumer side, in the host app's Podfile.
  s.dependency 'AppwinCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
