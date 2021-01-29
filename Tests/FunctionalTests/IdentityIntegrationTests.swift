//
// Copyright 2021 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

@testable import AEPCore
import AEPIdentityEdge
@testable import AEPServices
import XCTest

class IdentityIntegrationTests: XCTestCase {

    override func setUp() {
        UserDefaults.clear()
        FileManager.default.clearCache()
        ServiceProvider.shared.reset()
        EventHub.reset()
    }

    override func tearDown() {

        let unregisterExpectation = XCTestExpectation(description: "unregister extensions")
        unregisterExpectation.expectedFulfillmentCount = 1
        MobileCore.unregisterExtension(Identity.self) {
            unregisterExpectation.fulfill()
        }

        wait(for: [unregisterExpectation], timeout: 2)

    }

    func initExtensionsAndWait() {
        let initExpectation = XCTestExpectation(description: "init extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.registerExtensions([Identity.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    func testGetExperienceCloudId() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedin"])
        Identity.getExperienceCloudId { ecid, error in
            XCTAssertFalse(ecid!.isEmpty)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetExperienceCloudIdWhenPrivacyUnknown() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "unknown"])
        Identity.getExperienceCloudId { ecid, error in
            XCTAssertFalse(ecid!.isEmpty)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetExperienceCloudIdWhenPrivacyOptedOut() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedout"])
        Identity.getExperienceCloudId { ecid, error in
            XCTAssertNil(ecid)
            XCTAssertEqual(AEPError.unexpected, error as? AEPError)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetExperienceCloudIdWhenNoConfig() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        Identity.getExperienceCloudId { ecid, error in
            XCTAssertNil(ecid)
            XCTAssertEqual(AEPError.callbackTimeout, error as? AEPError)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
