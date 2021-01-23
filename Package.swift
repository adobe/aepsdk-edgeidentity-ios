// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

/*
 Copyright 2021 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import PackageDescription

let package = Package(
    name: "AEPIdentityEdge",
    platforms: [.iOS(.v10)],
    products: [
        .library(name: "AEPIdentityEdge", targets: ["AEPIdentityEdge"])
    ],
    dependencies: [
        .package(url: "https://github.com/adobe/aepsdk-core-ios.git", .branch("main"))
    ],
    targets: [
        .target(name: "AEPIdentityEdge",
                dependencies: ["AEPCore"],
                path: "Sources"),
        .testTarget(name: "AEPIdentityEdgeSampleApp",
                    dependencies: ["AEPIdentityEdge"],
                    path: "SampleApps/AEPIdentityEdgeSampleApp"),
        .testTarget(name: "FunctionalTests",
                    dependencies: ["AEPIdentityEdge"],
                    path: "Tests/FunctionalTests"),
        .testTarget(name: "UnitTests",
                    dependencies: ["AEPIdentityEdge"],
                    path: "Tests/UnitTests")
    ]
)
