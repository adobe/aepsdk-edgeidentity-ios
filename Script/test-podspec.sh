#!/bin/bash
#
# Copyright 2021 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

set -e # Any subsequent(*) commands which fail will cause the shell script to exit immediately

PROJECT_NAME=TestProject

# Clean up.
rm -rf $PROJECT_NAME

mkdir -p $PROJECT_NAME && cd $PROJECT_NAME

# Create a new Xcode project.
swift package init
swift package generate-xcodeproj

# Create a Podfile with our pod as dependency.
echo "
platform :ios, '11.0'
target '$PROJECT_NAME' do
  use_frameworks!
  pod 'AEPCore', '~> 4.0'
  pod 'AEPIdentity', '~> 4.0'
  pod 'AEPServices', '~> 4.0'
  pod 'AEPRulesEngine', '~> 4.0'
  pod 'AEPEdge', :git => 'https://github.com/adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeIdentity', :path => '../AEPEdgeIdentity.podspec'
end
" >>Podfile

# Install the pods.
pod install

# Archive for generic iOS device
echo '############# Archive for generic iOS device ###############'
xcodebuild archive -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=iOS'

# Build for generic iOS device
echo '############# Build for generic iOS device ###############'
xcodebuild clean build -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=iOS'

# Archive for x86_64 simulator
echo '############# Archive for iOS simulator ###############'
xcodebuild archive -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=iOS Simulator'

# Build for x86_64 simulator
echo '############# Build for iOS simulator ###############'
xcodebuild clean build -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=iOS Simulator'

# Clean up.
cd ../
rm -rf $PROJECT_NAME

# tvOS
mkdir -p $PROJECT_NAME && cd $PROJECT_NAME
# Create a new Xcode project.
swift package init
swift package generate-xcodeproj

# Create a Podfile with our pod as dependency.
echo "
platform :tvos, '11.0'
target '$PROJECT_NAME' do
  use_frameworks!
  pod 'AEPCore', '~> 4.0'
  pod 'AEPIdentity', '~> 4.0'
  pod 'AEPServices', '~> 4.0'
  pod 'AEPRulesEngine', '~> 4.0'
  pod 'AEPEdge', :git => 'https://github.com/adobe/aepsdk-edge-ios.git', :branch => 'dev'
  pod 'AEPEdgeIdentity', :path => '../AEPEdgeIdentity.podspec'
end
" >>Podfile

# Install the pods.
pod install
# Archive for generic tvOS device
echo '############# Archive for generic tvOS device ###############'
xcodebuild archive -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=tvOS'

# Build for generic tvOS device
echo '############# Build for generic tvOS device ###############'
xcodebuild build -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=tvOS'

# Archive for generic tvOS device
echo '############# Archive for generic tvOS device ###############'
xcodebuild archive -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=tvOS Simulator'

# Build for generic tvOS simulator
echo '############# Build for x86_64 tvOS simulator ###############'
xcodebuild build -scheme TestProject-Package -workspace TestProject.xcworkspace -destination 'generic/platform=tvOS Simulator'

# Clean up.
cd ../
rm -rf $PROJECT_NAME
