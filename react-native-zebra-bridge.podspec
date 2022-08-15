require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-zebra-bridge"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  react-native-zebra-bridge
                   DESC
  s.homepage     = "https://github.com/github_account/react-native-zebra-bridge"
  # brief license entry:
  s.license      = "MIT"
  # optional - use expanded license entry instead:
  # s.license    = { :type => "MIT", :file => "LICENSE" }
  s.authors      = { "Ciro Pedrini" => "ciro.pedrini@gmail.com" }
  s.platforms    = { :ios => "9.0" }
  s.source       = { :git => "https://github.com/github_account/react-native-zebra-bridge.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,c,m,swift}", "ios/BRLMPrinterKit.framework/Headers/*.h"
  s.requires_arc = true

  s.dependency "React"
  s.dependency "ImageMagick", ">= 6.8pre"
  s.dependency "libpng"

  s.ios.vendored_libraries = 'ios/lib/libZSDK_API.a'
  s.ios.vendored_frameworks = 'ios/BRLMPrinterKit.framework', 'ios/BrotherObjCFramework.framework'
  s.xcconfig = {
    'USER_HEADER_SEARCH_PATHS' => [
      '"${SRCROOT}/../../node_modules/react-native-zebra-bridge/ios/lib"/**',
      '"${SRCROOT}/ImageMagick/include"/**'
    ]
  }
end

