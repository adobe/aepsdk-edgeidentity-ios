# Adobe Experience Platform Edge Identity Mobile Extension

[![SPM](https://img.shields.io/github/v/release/adobe/aepsdk-edgeidentity-ios?label=SPM&logo=apple&logoColor=white&color=orange)](https://github.com/adobe/aepsdk-edgeidentity-ios/releases)
[![CircleCI](https://img.shields.io/circleci/project/github/shushinde/aepsdk-edgeidentity-ios/main.svg?label=Build&logo=circleci)](https://circleci.com/gh/shushinde/workflows/aepsdk-edgeidentity-ios)
[![Code Coverage](https://img.shields.io/codecov/c/github/adobe/aepsdk-edgeidentity-ios/main.svg?label=Coverage&logo=codecov)](https://codecov.io/gh/adobe/aepsdk-edgeidentity-ios/branch/main)

## About this project

The AEP Edge Identity mobile extension enables handling of user identity data from a mobile application when using the [Adobe Experience Platform SDK](https://developer.adobe.com/client-sdks) and the Edge Network extension.

## Requirements
- Xcode 15 (or newer)
- Swift 5.1 (or newer)

## Installation

### [Swift Package Manager](https://github.com/apple/swift-package-manager)

To add the AEPEdgeIdentity Package to your application, from the Xcode menu select:

`File > Add Packages...`

> **Note** 
>  The menu options may vary depending on the version of Xcode being used.

Enter the URL for the AEPEdgeIdentity package repository: `https://github.com/adobe/aepsdk-edgeidentity-ios.git`.

When prompted, input a specific version or a range of version for Version rule.

Alternatively, if your project has a `Package.swift` file, you can add AEPEdgeIdentity directly to your dependencies:

```
dependencies: [
	.package(url: "https://github.com/adobe/aepsdk-edgeidentity-ios.git", .upToNextMajor(from: "5.0.0"))
],
targets: [
   	.target(name: "YourTarget",
    		dependencies: ["AEPEdgeIdentity"],
          	path: "your/path")
]
```

### Binaries

To generate an `AEPEdgeIdentity.xcframework`, run the following command:

```sh
make archive
make zip
```

This generates `build/AEPEdgeIdentity.xcframework` and
`build/AEPEdgeIdentity.xcframework.zip`, including iOS and tvOS device/simulator
slices and debug symbols. The archive uses Swift Package Manager dependencies;
CocoaPods is not required. Add the XCFramework to your app along with compatible
Mobile Core dependency frameworks.

GitHub releases attach the XCFramework zip while retaining the source tag for
Swift Package Manager consumers. CircleCI also builds and stores the zip on
branches to validate binary distribution independently of SPM integration.

For local SDKs that no longer accept the historical deployment targets, use
`make archive ARCHIVE_BUILD_SETTINGS="IPHONEOS_DEPLOYMENT_TARGET=15.0 TVOS_DEPLOYMENT_TARGET=15.0"`.
This override does not change the package's supported platform minimums.

## Development

The first time you clone or download the project, you should run the following from the root directory to setup the environment:

~~~
make setup
~~~

Subsequently, you can make sure your environment is updated by running the following:

~~~
swift package update
~~~

#### Open the Xcode workspace
Open the workspace in Xcode by running the following command from the root directory of the repository:

~~~
make open
~~~

#### Command line integration

You can run all the test suites from command line:

~~~
make test
~~~

## Related Projects

| Project                                                      | Description                                                  |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| [AEPCore Extensions](https://github.com/adobe/aepsdk-core-ios) | The AEPCore and AEPServices represent the foundation of the Adobe Experience Platform SDK. |
| [AEPEdge Extension](https://github.com/adobe/aepsdk-edge-ios) | The AEPEdge extension allows you to send data to the Adobe Experience Platform (AEP) from a mobile application. |
| [AEP SDK Sample App for iOS](https://github.com/adobe/aepsdk-sample-app-ios) | Contains iOS sample apps for the AEP SDK. Apps are provided for both Objective-C and Swift implementations. |
| [AEP SDK Sample App for Android](https://github.com/adobe/aepsdk-sample-app-android) | Contains Android sample app for the AEP SDK.                 |
## Contributing

Contributions are welcomed! Read the [Contributing Guide](./.github/CONTRIBUTING.md) for more information.

## Licensing

This project is licensed under the Apache V2 License. See [LICENSE](LICENSE) for more information.
