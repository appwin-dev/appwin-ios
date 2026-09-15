#
# CocoaPods podspec for AppwinCore (ADR-0020).
#
# Firebase/FlutterFire pattern: Core ships as its own pod. The Flutter wrappers
# declare `s.dependency 'AppwinCore'` rather than compiling its sources
# directly, which makes it a genuinely separate Swift module, so `import
# AppwinCore` works in both products and plugins.
#
# Development: referenced as `pod 'AppwinCore', :path => '…/sdk/core/AppwinCore'`
# in the host app's Podfile, so CocoaPods compiles from source on every rebuild
# and the feedback loop stays fast.
#
# Distribution (later): a prebuilt XCFramework
# (`s.vendored_frameworks = 'AppwinCore.xcframework'`) will coexist with this
# podspec, and the studio picks whichever it needs.
#
Pod::Spec.new do |s|
  s.name             = 'AppwinCore'
  s.version          = '0.6.0'
  s.summary          = 'Appwin Core SDK - device identity, networking, storage.'
  s.description      = <<-DESC
    Core module of the Appwin SDK (ADR-0020), shared by every product SDK
    (Support, Community, …). Provides device identity (keychain deviceId,
    DeviceInfo), the canonical HTTP client (ClientApi), local storage
    (KeychainStore) and the S3 bucket uploader (BucketUploader).
  DESC
  s.homepage         = 'https://appwin.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Appwin Studio' }
  s.author           = { 'Appwin' => 'lesignobles.studio@gmail.com' }
  # Trunk stores the podspec and fetches the sources from here, so a `:path`
  # cannot be published. The tag is the podspec version: the two move together,
  # both derived from `version.json` by the release script.
  s.source           = { :git => 'https://github.com/appwin-dev/appwin-ios.git', :tag => s.version.to_s }

  s.source_files     = 'Sources/AppwinCore/**/*.swift'
  s.platform         = :ios, '16.0'
  s.swift_version    = '6.0'
  s.frameworks       = 'Foundation', 'UIKit', 'Security'

  # Zero external dependencies since ADR-0028: realtime runs on
  # `URLSessionWebSocketTask` (RealtimeSocket) and Socket.IO is gone. This
  # podspec must stay aligned with `Package.swift` - a dependency declared on
  # only one side breaks one of the two builds, or drags in a library nobody
  # uses any more.

  # Explicit Swift module, required so consumers can `import AppwinCore`
  # instead of referencing flat symbols.
  # `-package-name` is not optional: `AppwinCore+Analytics.swift` declares its
  # analytics entry points `package`, and the compiler rejects that access level
  # unless a package name is given. SwiftPM passes one derived from `name:` in
  # Package.swift; CocoaPods passes nothing, so without this line NO pods-based
  # consumer can compile Core at all (this is what broke 0.5.0).
  #
  # The value must be the SAME in every Appwin podspec, and equal to `name:` in
  # Package.swift ("Appwin"): `package` means "same package", so a podspec with a
  # different name puts that target in another package and loses the access.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name Appwin',
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name Appwin',
  }
end
