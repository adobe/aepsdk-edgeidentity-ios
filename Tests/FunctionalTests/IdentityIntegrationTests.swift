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
            XCTAssertEqual(false, ecid?.isEmpty)
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
            XCTAssertEqual(false, ecid?.isEmpty)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetExperienceCloudIdWhenPrivacyOptedOutReturnsEmptyString() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedout"])
        Identity.getExperienceCloudId { ecid, error in
            XCTAssertEqual("", ecid)
            XCTAssertNil(error)
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

    func testGetExperienceCloudIdWhenPrivacyChanges() {
        initExtensionsAndWait()

        let expectation1 = XCTestExpectation(description: "getExperienceCloudId callback")
        var ecid1: String?
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedin"])
        Identity.getExperienceCloudId { ecid, _ in
            ecid1 = ecid
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1)

        // toggle privacy
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedout"])
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedin"])

        let configExpectation = XCTestExpectation(description: "getPrivacyStatus callback")
        MobileCore.getPrivacyStatus { _ in
            configExpectation.fulfill()
        }
        wait(for: [configExpectation], timeout: 1)

        let expectation2 = XCTestExpectation(description: "getExperienceCloudId callback")
        var ecid2: String?
        Identity.getExperienceCloudId { ecid, _ in
            ecid2 = ecid
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1)

        XCTAssertFalse(((ecid1?.isEmpty) == nil))
        XCTAssertFalse(((ecid2?.isEmpty) == nil))
        XCTAssertNotEqual(ecid1, ecid2)
    }

    func testGetIdentitiesWithECID() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getIdentities callback")
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedin"])
        Identity.getIdentities { identityMap, error in
            XCTAssertNil(error)
            XCTAssertNotNil(identityMap)
            XCTAssertEqual(1, identityMap?.getItems(withNamespace: "ECID")?.count)
            XCTAssertNotNil(identityMap?.getItems(withNamespace: "ECID")?[0].id)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetIdentitiesWhenPrivacyOptedOutReturnsEmptyIdentityMap() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getIdentities callback")
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedout"])
        Identity.getIdentities { identityMap, error in
            XCTAssertNotNil(identityMap)
            XCTAssertEqual(true, identityMap?.isEmpty)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}
