//
// Copyright 2022 Adobe. All rights reserved.
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
import AEPEdgeIdentity
@testable import AEPServices
import XCTest

class IdentityGetUrlVariablesTest: XCTestCase {
    var identity: Identity!
    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        continueAfterFailure = false
        reset()
        registerEdgeIdentityAndStart()
    }

    override func tearDown() {
        let unregisterExpectation = XCTestExpectation(description: "unregister extensions")
        unregisterExpectation.expectedFulfillmentCount = 1
        MobileCore.unregisterExtension(AEPEdgeIdentity.Identity.self) {
            unregisterExpectation.fulfill()
        }

        wait(for: [unregisterExpectation], timeout: 2)
    }

    private func reset() {
        ServiceProvider.shared.reset()
        ServiceProvider.shared.networkService = FunctionalTestNetworkService()
        EventHub.reset()

        // Clear persisted data
        UserDefaults.clear()
        FileManager.default.clearCache()
    }

    // MARK: test cases

    func testGetUrlVariablesWhenECIDAndOrgIdAvailable() {
        MobileCore.updateConfigurationWith(configDict: ["experienceCloud.org": "1234@Adobe"])

        let expectation = XCTestExpectation(description: "getUrlVariables callback")
        Identity.getUrlVariables { urlVariablesString, error in
            guard let urlVariablesString = urlVariablesString else {
                XCTFail("urlVariable string was nil")
                return
            }

            XCTAssertFalse(urlVariablesString.isEmpty)
            XCTAssertNil(error)

            let urlParams = self.getParamsFrom(urlVariablesString: urlVariablesString)

            XCTAssertFalse((urlParams["ts"] ?? "").isEmpty)
            XCTAssertFalse((urlParams["ecid"] ?? "").isEmpty)
            XCTAssertEqual("1234%40Adobe", (urlParams["orgId"] ?? ""))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetUrlVariablesWhenOrgIdNotAvailableReturnsNil() {
        MobileCore.updateConfigurationWith(configDict: ["global.privacy": "optedin"])
        let expectation = XCTestExpectation(description: "getUrlVariables callback should return with nil urlVariablesString")
        Identity.getUrlVariables { urlVariablesString, error in
            guard urlVariablesString != nil else {
                expectation.fulfill()
                XCTAssertNotNil(error)
                return
            }
        }
        wait(for: [expectation], timeout: 1)
    }

    // MARK: Helpers
    private func registerEdgeIdentityAndStart() {
        let initExpectation = XCTestExpectation(description: "init Edge Identity extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.registerExtensions([AEPEdgeIdentity.Identity.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    private func getParamsFrom(urlVariablesString: String) -> [String: String] {
        var params = [String: String]()
        do {
            let regex = try NSRegularExpression(pattern: "adobe_mc=TS%3D(.*)%7CMCMID%3D(.*)%7CMCORGID%3D(.*)", options: .caseInsensitive)
            if let match = regex.firstMatch(in: urlVariablesString, range: NSRange(urlVariablesString.startIndex..., in: urlVariablesString)) {
                params["ts"] = String(urlVariablesString[Range(match.range(at: 1), in: urlVariablesString)!])
                params["ecid"] = String(urlVariablesString[Range(match.range(at: 2), in: urlVariablesString)!])
                params["orgId"] = String(urlVariablesString[Range(match.range(at: 3), in: urlVariablesString)!])
            }
        } catch let error as NSError {
            print("#getParamsFrom - Error while extracting params from urlVariablesString: \(error.localizedDescription)")
        }

        return params
    }
}
