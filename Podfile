platform :ios, '10.0'

# Comment the next line if you don't want to use dynamic frameworks
use_frameworks!

workspace 'AEPEdgeIdentity'
project 'AEPEdgeIdentity.xcodeproj'

pod 'SwiftLint', '0.44.0'

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
  pod 'AEPLifecycle'
  pod 'AEPSignal'
  pod 'AEPAssurance'
  pod 'AEPEdge'
  pod 'AEPEdgeConsent', '1.0.0'
end

target 'TestAppObjC' do
  pod 'AEPCore'
  pod 'AEPServices'
end
