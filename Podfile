platform :ios, '11.0'

# Comment the next line if you don't want to use dynamic frameworks
use_frameworks!

workspace 'AEPEdgeIdentity'
project 'AEPEdgeIdentity.xcodeproj'

pod 'SwiftLint', '0.44.0'

target 'AEPEdgeIdentity' do
  pod 'AEPCore', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPServices', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPRulesEngine', :git => 'git@github.com:adobe/aepsdk-rulesengine-ios.git', :branch => 'dev-v2.0.0'
end

target 'UnitTests' do
  pod 'AEPCore', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPServices', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
end

target 'FunctionalTests' do
  pod 'AEPCore', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPServices', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPIdentity', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPRulesEngine', :git => 'git@github.com:adobe/aepsdk-rulesengine-ios.git', :branch => 'dev-v2.0.0'
end

target 'TestApp' do
  pod 'AEPCore', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPServices', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPIdentity', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPLifecycle', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPSignal', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPAssurance'
  pod 'AEPEdge', :git => 'git@github.com:adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeIdentity', :git => 'git@github.com:adobe/aepsdk-edgeidentity-ios.git', :branch => 'dev'
  pod 'AEPEdgeConsent', :git => 'git@github.com:adobe/aepsdk-edgeconsent-ios.git', :branch => 'dev'
end

target 'TestApptvOS' do
  pod 'AEPCore', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPServices', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPIdentity', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPLifecycle', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPEdge', :git => 'git@github.com:adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeConsent', :git => 'git@github.com:adobe/aepsdk-edgeconsent-ios.git', :branch => 'dev'
end

target 'TestAppObjC' do
  pod 'AEPCore', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPServices', :git => 'git@github.com:adobe/aepsdk-core-ios.git', :branch => 'dev-v4.0.0'
  pod 'AEPEdge', :git => 'git@github.com:adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeConsent', :git => 'git@github.com:adobe/aepsdk-edgeconsent-ios.git', :branch => 'dev'
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
