#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint deepar.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'deepar_flutter_plus'
  s.version          = '0.2.1'
  s.summary          = 'Enhanced Flutter SDK for DeepAR with extended functionality.'
  s.description      = <<-DESC
An enhanced version of the official DeepAR Flutter SDK that adds support for loading AR effects from multiple sources including assets, file paths, and URLs with automatic caching.
                       DESC
  s.homepage         = 'https://deepar.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Deepar.ai' => 'support@deepar.ai' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.resources    = ['Assets/**.*']
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'FRAMEWORK_SEARCH_PATHS' => '$(PODS_ROOT)/../../ios'
  }
  s.module_name = 'deepar_flutter_plus'
  s.swift_version = '5.0'

  s.preserve_paths = 'DeepAR.framework/**/*'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework DeepAR' }
  s.vendored_frameworks = 'DeepAR.framework'
end
