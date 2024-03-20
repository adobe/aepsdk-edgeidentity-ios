platform :ios, '12.0'

# Comment the next line if you don't want to use dynamic frameworks
use_frameworks!

workspace 'AEPEdgeIdentity'
project 'AEPEdgeIdentity.xcodeproj'

pod 'SwiftLint', '0.52.0'

def core_pods
  pod 'AEPServices'
  pod 'AEPCore'
end

def edge_pods
  pod 'AEPEdge', :git => 'https://github.com/adobe/aepsdk-edge-ios.git', :branch => 'staging'
  pod 'AEPEdgeConsent', :git => 'https://github.com/adobe/aepsdk-edgeconsent-ios.git', :branch => 'staging'
end

target 'AEPEdgeIdentity' do
  core_pods
end

target 'UnitTests' do
  core_pods
  pod 'AEPTestUtils', :git => 'https://github.com/adobe/aepsdk-testutils-ios.git', :tag => '5.0.0'
end

target 'FunctionalTests' do
  core_pods
  pod 'AEPIdentity'
  pod 'AEPTestUtils', :git => 'https://github.com/adobe/aepsdk-testutils-ios.git', :tag => '5.0.0'
end

target 'TestApp' do
  core_pods
  edge_pods
  pod 'AEPIdentity'
  pod 'AEPAssurance', :git => 'https://github.com/adobe/aepsdk-assurance-ios.git', :branch => 'staging'
  pod 'AEPEdgeIdentity', :path => './AEPEdgeIdentity.podspec'
end

target 'TestApptvOS' do
  core_pods
  edge_pods
  pod 'AEPIdentity'
end

target 'TestAppObjC' do
  core_pods
  edge_pods
  pod 'AEPIdentity'
end

post_install do |pi|
  pi.pods_project.targets.each do |t|
    t.build_configurations.each do |bc|
        bc.build_settings['TVOS_DEPLOYMENT_TARGET'] = '12.0'
        bc.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator appletvos appletvsimulator'
        bc.build_settings['TARGETED_DEVICE_FAMILY'] = "1,2,3"
    end
  end
end
