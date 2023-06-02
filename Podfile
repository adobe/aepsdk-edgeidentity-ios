platform :ios, '11.0'

# Comment the next line if you don't want to use dynamic frameworks
use_frameworks!

workspace 'AEPEdgeIdentity'
project 'AEPEdgeIdentity.xcodeproj'

pod 'SwiftLint', '0.52.0'

target 'AEPEdgeIdentity' do
  pod 'AEPCore'
  pod 'AEPServices'
end

target 'UnitTests' do
  pod 'AEPCore'
  pod 'AEPServices'
end

target 'FunctionalTests' do
  pod 'AEPCore'
  pod 'AEPServices'
  pod 'AEPIdentity'
end

target 'TestApp' do
  pod 'AEPCore'
  pod 'AEPServices'
  pod 'AEPIdentity'
  pod 'AEPAssurance'
  pod 'AEPEdge', :git => 'https://github.com/adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeConsent', :git => 'https://github.com/adobe/aepsdk-edgeconsent-ios.git', :branch => 'dev'
  pod 'AEPEdgeIdentity', :path => './AEPEdgeIdentity.podspec'

end

target 'TestApptvOS' do
  pod 'AEPCore'
  pod 'AEPServices'
  pod 'AEPIdentity'
  pod 'AEPEdge', :git => 'https://github.com/adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeConsent', :git => 'https://github.com/adobe/aepsdk-edgeconsent-ios.git', :branch => 'dev'
end

target 'TestAppObjC' do
  pod 'AEPCore'
  pod 'AEPServices'
  pod 'AEPEdge', :git => 'https://github.com/adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeConsent', :git => 'https://github.com/adobe/aepsdk-edgeconsent-ios.git', :branch => 'dev'
end

post_install do |pi|
  pi.pods_project.targets.each do |t|
    t.build_configurations.each do |bc|
        bc.build_settings['TVOS_DEPLOYMENT_TARGET'] = '11.0'
        bc.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator appletvos appletvsimulator'
        bc.build_settings['TARGETED_DEVICE_FAMILY'] = "1,2,3"
    end
  end
end
