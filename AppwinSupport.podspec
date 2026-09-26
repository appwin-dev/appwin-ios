#
# CocoaPods podspec for AppwinSupport (ADR-0019, ADR-0020).
#
# Support product of the Appwin SDK. Depends on AppwinCore, which must be
# available in the host app's Podfile - through :path in development, or the
# same git URL in production.
#
# Development: `pod 'AppwinSupport', :path => '.../sdk/appwin-ios'` in the
# Podfile, and the same for AppwinCore - the four podspecs share that folder.
#
Pod::Spec.new do |s|
  s.name             = 'AppwinSupport'
  s.version          = '0.8.1'
  s.summary          = 'Appwin Support SDK - native iOS messenger, FAQ and conversations.'
  s.description      = <<-DESC
    Support module of the Appwin SDK. Native SwiftUI screens, stores,
    repositories and the `/sdk/support/v1/**` backend integration. Depends on
    AppwinCore for device identity and networking.
  DESC
  s.homepage         = 'https://appwin.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Appwin Studio' }
  s.author           = { 'Appwin' => 'lesignobles.studio@gmail.com' }
  # Trunk stores the podspec and fetches the sources from here, so a `:path`
  # cannot be published. The tag is the podspec version: the two move together,
  # both derived from `version.json` by the release script.
  s.source           = { :git => 'https://github.com/appwin-dev/appwin-ios.git', :tag => s.version.to_s }

  s.source_files     = 'Sources/AppwinSupport/**/*.swift'
  s.resource_bundles = {
    'AppwinSupport' => ['Sources/AppwinSupport/Resources/**/*']
  }
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.frameworks       = 'Foundation', 'UIKit', 'SwiftUI'

  # The `import AppwinCore` in the Support code requires this pod to be
  # available on the consumer side, in the host app's Podfile.
  s.dependency 'AppwinCore', s.version.to_s

  # Same package name as every other Appwin podspec and as `name:` in
  # Package.swift - `package` access is scoped by this string, so a mismatch
  # silently cuts this module off from Core's `package` symbols.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name Appwin',
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
