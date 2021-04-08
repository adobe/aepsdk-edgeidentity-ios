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
import AEPEdgeIdentity
import AEPIdentity
@testable import AEPServices
import XCTest

class EdgeIdentityAndIdentityDirectTests: XCTestCase {
    private let defaultIdentityConfiguration = [
        "global.privacy": "optedin",
        "experienceCloud.org": "1234@Adobe",
        "experienceCloud.server": "fakeTestServer"]

    override func setUp() {
        continueAfterFailure = false
        UserDefaults.clear()
        FileManager.default.clearCache()
        ServiceProvider.shared.reset()
        ServiceProvider.shared.networkService = FunctionalTestNetworkService()
        EventHub.reset()
        MobileCore.setLogLevel(LogLevel.trace)
    }

    override func tearDown() {
        let unregisterExpectation = XCTestExpectation(description: "unregister extensions")
        unregisterExpectation.expectedFulfillmentCount = 2
        MobileCore.unregisterExtension(AEPEdgeIdentity.Identity.self) {
            unregisterExpectation.fulfill()
        }
        MobileCore.unregisterExtension(AEPIdentity.Identity.self) {
            unregisterExpectation.fulfill()
        }

        wait(for: [unregisterExpectation], timeout: 2)

        // Clear persisted data
        UserDefaults.clear()
    }

    // MARK: test cases

    func testGetExperienceCloudId() {
        registerEdgeIdentityAndStart()

        let expectation = XCTestExpectation(description: "getExperienceCloudId callback")
        AEPEdgeIdentity.Identity.getExperienceCloudId { ecid, error in
            XCTAssertEqual(false, ecid?.isEmpty)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testGetIdentitiesWithECID() {
        registerEdgeIdentityAndStart()

        let expectation = XCTestExpectation(description: "getIdentities callback")
        Identity.getIdentities { identityMap, error in
            XCTAssertNil(error)
            XCTAssertNotNil(identityMap)
            XCTAssertEqual(1, identityMap?.getItems(withNamespace: "ECID")?.count)
            XCTAssertNotNil(identityMap?.getItems(withNamespace: "ECID")?[0].id)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    /// Test Edge Identity bootup will load ECID from legacy Identity direct extension
    func testLegacyEcidLoadedOnBootup() {
        registerIdentityDirectAndStart() // register Identity Direct first to allow bootup and shared state creation
        let ecidLegacy = getLegacyEcidFromIdentity()

        registerEdgeIdentityAndWait() // register Edge Identity alone
        let ecidEdge = getEcidFromEdgeIdentity()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)
    }

    /// Test Edge Identity will include legacy ECID in IdentityMap when read from Identity Direct shared state
    func testLegacyEcidAddedToIdentityMapAfterBootup() {
        registerEdgeIdentityAndStart() // register and boot Edge Identity
        let ecidEdge = getEcidFromEdgeIdentity()

        registerIdentityDirectAndWait()
        let ecidLegacy = getLegacyEcidFromIdentity()

        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertNotEqual(ecidLegacy, ecidEdge)

        let (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertEqual(false, primaryEcidItem?.primary)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
        XCTAssertEqual(false, legacyEcidItem?.primary)
    }

    /// Test Edge Identity and IdentityDirect have same ECID on bootup, and after resetIdentities call ECIDs are different
    func testEcidsAreDifferentAfterReset() {
        // 1) Register Identity then Edge Identity and verify both have same ECID
        registerIdentityDirectAndStart()
        var ecidLegacy = getLegacyEcidFromIdentity()

        registerEdgeIdentityAndWait()
        let ecidEdge = getEcidFromEdgeIdentity()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)

        // 2) Reset Edge Identity identifiers and verify ECIDs are different
        MobileCore.resetIdentities()
        var (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNil(legacyEcidItem) // Legacy ECID is not set yet as it was cleared but no state change from Identity
        XCTAssertNotEqual(ecidLegacy, primaryEcidItem?.id)

        // 3) Identity Direct state change will add legacy ECID to Identity Map
        Identity.syncIdentifiers(identifiers: ["email": "email@example.com"])
        ecidLegacy = getLegacyEcidFromIdentity() // causes test to wait for state change from sync call

        (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNotNil(legacyEcidItem)
        XCTAssertNotEqual(legacyEcidItem?.id, primaryEcidItem?.id)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
    }

    /// Test Edge Identity and IdentityDirect have same ECID on bootup, and after privacy change ECIDs are different
    func testEcidsAreDifferentAfterPrivacyChange() {
        // 1) Register Identity then Edge Identity and verify both have same ECID
        registerIdentityDirectAndStart()
        var ecidLegacy = getLegacyEcidFromIdentity()

        registerEdgeIdentityAndWait()
        let ecidEdge = getEcidFromEdgeIdentity()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)

        // 2) Toggle privacy and verify legacy ECID added to IdentityMap
        toggleGlobalPrivacy()
        ecidLegacy = getLegacyEcidFromIdentity()
        let (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNotNil(legacyEcidItem)
        XCTAssertNotEqual(legacyEcidItem?.id, primaryEcidItem?.id)
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
    }

    /// Test Edge Identity and IdentityDirect have same ECID on bootup, and after resetIdentities and privacy change ECIDs are different
    func testEcidsAreDifferentAfterResetIdentitiesAndPrivacyChange() {
        // 1) Register Identity then Edge Identity and verify both have same ECID
        registerIdentityDirectAndStart()
        var ecidLegacy = getLegacyEcidFromIdentity()

        registerEdgeIdentityAndWait()
        var ecidEdge = getEcidFromEdgeIdentity()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)

        // 2) Reset identities and toggle privacy and verify legacy ECID added to IdentityMap
        MobileCore.resetIdentities()
        toggleGlobalPrivacy()
        ecidLegacy = getLegacyEcidFromIdentity()
        ecidEdge = getEcidFromEdgeIdentity()

        let (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNotNil(legacyEcidItem)
        XCTAssertNotEqual(legacyEcidItem?.id, primaryEcidItem?.id)
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
    }

    /// Test legacy ECID is removed when privacy is opted out
    func testLegacyEcidIsRemovedOnPrivacyOptOut() {
        // 1) Register Edge Identity then Identity and verify ECIDs are different
        registerEdgeIdentityAndStart() // register and boot Edge Identity
        let ecidEdge = getEcidFromEdgeIdentity()

        registerIdentityDirectAndWait()
        var ecidLegacy = getLegacyEcidFromIdentity()

        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertNotEqual(ecidLegacy, ecidEdge)

        var (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()

        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNotNil(legacyEcidItem)
        XCTAssertNotEqual(legacyEcidItem?.id, primaryEcidItem?.id)
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)

        // 2) Set privacy opted-out and verify legacy ECID is removed
        setPrivacyStatus(PrivacyStatus.optedOut)
        ecidLegacy = getLegacyEcidFromIdentity() // call gives time for Edge Identity to process Identity state change
        (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertNil(legacyEcidItem)
    }

    // MARK: helper funcs

    /// Register Edge Identity + Configuration
    func registerEdgeIdentityAndStart() {
        let initExpectation = XCTestExpectation(description: "init Edge Identity extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.registerExtensions([AEPEdgeIdentity.Identity.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    /// Register Identity direct + Configuration
    func registerIdentityDirectAndStart() {
        let initExpectation = XCTestExpectation(description: "init Identity Direct extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.updateConfigurationWith(configDict: defaultIdentityConfiguration)
        MobileCore.registerExtensions([AEPIdentity.Identity.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    /// Register AEPEdgeIdentity. Should be called after one of the 'init' functions above.
    func registerEdgeIdentityAndWait() {
        let initExpectation = XCTestExpectation(description: "register Edge Identity extensions")
        MobileCore.registerExtension(AEPEdgeIdentity.Identity.self) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    /// Register Identity direct. Should be called after one of the 'init' functions above.
    func registerIdentityDirectAndWait() {
        let initExpectation = XCTestExpectation(description: "init Identity Direct extensions")
        MobileCore.updateConfigurationWith(configDict: defaultIdentityConfiguration)
        MobileCore.registerExtension(AEPIdentity.Identity.self) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    func getEcidFromEdgeIdentity() -> String? {
        let expectation = XCTestExpectation(description: "AEPEdgeIdentity.Identity.getExperienceCloudId callback")
        var ecid: String?
        AEPEdgeIdentity.Identity.getExperienceCloudId { id, _ in
            ecid = id
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return ecid
    }

    func getLegacyEcidFromIdentity() -> String? {
        let expectation = XCTestExpectation(description: "AEPIdentity.Identity.getExperienceCloudId callback")
        var ecid: String?
        AEPIdentity.Identity.getExperienceCloudId { id, _ in
            ecid = id
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return ecid
    }

    func getPrimaryAndLegacyEcidIdentityItems() -> (IdentityItem?, IdentityItem?) {
        let expectation = XCTestExpectation(description: "AEPEdgeIdentity.Identity.getIdentities callback")
        var identities: IdentityMap?
        Identity.getIdentities { identityMap, _ in
            identities = identityMap
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        guard let identityMap = identities, let ecids = identityMap.getItems(withNamespace: "ECID") else {
            return (nil, nil)
        }

        if ecids.count == 1 {
            return (ecids[0], nil)
        } else {
            return (ecids[0], ecids[1])
        }
    }

    func toggleGlobalPrivacy() {
        MobileCore.setPrivacyStatus(PrivacyStatus.optedOut)
        MobileCore.setPrivacyStatus(PrivacyStatus.optedIn)
        let expectation = XCTestExpectation(description: "getPrivacyStatus callback")
        MobileCore.getPrivacyStatus { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func setPrivacyStatus(_ privacyStatus: PrivacyStatus) {
        MobileCore.setPrivacyStatus(privacyStatus)
        let expectation = XCTestExpectation(description: "getPrivacyStatus callback")
        MobileCore.getPrivacyStatus { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}

class FunctionalTestNetworkService: Networking {
    public func connectAsync(networkRequest: NetworkRequest, completionHandler: ((HttpConnection) -> Void)?) {
        if let closure = completionHandler {
            Log.trace(label: "TestNetworkService", "Received and ignoring request to '\(networkRequest.url)")
            let response = HTTPURLResponse(url: networkRequest.url, statusCode: 200, httpVersion: nil, headerFields: nil)
            let httpConnection = HttpConnection(data: "{}".data(using: .utf8), response: response, error: nil)
            closure(httpConnection)
        }
    }
}
