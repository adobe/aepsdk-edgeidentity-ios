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

class IdentityEdgeIntegrationTests: XCTestCase {

    override func setUp() {
        UserDefaults.clear()
        FileManager.default.clearCache()
        ServiceProvider.shared.reset()
        EventHub.reset()
    }

    override func tearDown() {

        let unregisterExpectation = XCTestExpectation(description: "unregister extensions")
        unregisterExpectation.expectedFulfillmentCount = 1
        MobileCore.unregisterExtension(IdentityEdge.self) {
            unregisterExpectation.fulfill()
        }

        wait(for: [unregisterExpectation], timeout: 2)

    }

    func initExtensionsAndWait() {
        let initExpectation = XCTestExpectation(description: "init extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.registerExtensions([IdentityEdge.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    func testGetExperienceCloudId() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        IdentityEdge.getExperienceCloudId { ecid, error in
            XCTAssertEqual(false, ecid?.isEmpty)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetIdentitiesWithECID() {
        initExtensionsAndWait()

        let expectation = XCTestExpectation(description: "getIdentities callback")
        IdentityEdge.getIdentities { identityMap, error in
            XCTAssertNil(error)
            XCTAssertNotNil(identityMap)
            XCTAssertEqual(1, identityMap?.getItems(withNamespace: "ECID")?.count)
            XCTAssertNotNil(identityMap?.getItems(withNamespace: "ECID")?[0].id)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}
