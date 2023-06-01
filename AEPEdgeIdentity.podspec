Pod::Spec.new do |s|
  s.name             = "AEPEdgeIdentity"
  s.version          = "4.0.0"
  s.summary          = "Experience Platform Edge Identity extension for Adobe Experience Platform Mobile SDK. Written and maintained by Adobe."

  s.description      = <<-DESC
                       The Experience Platform Edge Identity extension enables handling Identity data from a mobile device using the Adobe Experience Platform SDK.
                       DESC

  s.homepage         = "https://github.com/adobe/aepsdk-identityedge-ios.git"
  s.license          = { :type => "Apache License, Version 2.0", :file => "LICENSE" }
  s.author           = "Adobe Experience Platform SDK Team"
  s.source           = { :git => "https://github.com/adobe/aepsdk-identityedge-ios.git", :tag => s.version.to_s }

  s.ios.deployment_target = '11.0'
  s.tvos.deployment_target = '11.0'

  s.swift_version = '5.1'

  s.pod_target_xcconfig = { 'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES' }
  s.dependency 'AEPCore', '>= 4.0.0'

  s.source_files = 'Sources/**/*.swift'
end