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
  s.authors      = { "Your Name" => "yourname@email.com" }
  s.platforms    = { :ios => "9.0" }
  s.source       = { :git => "https://github.com/github_account/react-native-zebra-bridge.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,c,m,swift}", "ios/BRLMPrinterKit.framework/Headers/*.h", "ios/BrotherObjCFramework.framework/Headers/*.h", "ios/opencv2.framework/Headers/*.{h,c,m,swift}"
  s.requires_arc = true

  s.dependency "React"
  s.dependency "OpenCV2"
  # ...
  # s.dependency "..."

  s.ios.vendored_libraries = 'ios/lib/libZSDK_API.a'
end

