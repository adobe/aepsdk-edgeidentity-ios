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
import AEPIdentity
import AEPIdentityEdge
@testable import AEPServices
import XCTest

class IdentityEdgeIntegrationTests: XCTestCase {
    private let defaultIdentityConfiguration = [
        "global.privacy": "optedin",
        "experienceCloud.org": "1234@Adobe",
        "experienceCloud.server": "fakeTestServer"]

    override func setUp() {
        continueAfterFailure = false
        UserDefaults.clear()
        FileManager.default.clearCache()
        ServiceProvider.shared.reset()
        EventHub.reset()
    }

    override func tearDown() {
        let unregisterExpectation = XCTestExpectation(description: "unregister extensions")
        unregisterExpectation.expectedFulfillmentCount = 2
        MobileCore.unregisterExtension(IdentityEdge.self) {
            unregisterExpectation.fulfill()
        }
        MobileCore.unregisterExtension(Identity.self) {
            unregisterExpectation.fulfill()
        }

        wait(for: [unregisterExpectation], timeout: 2)

    }

    // MARK: test cases

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

    /// Test IdentityEdge bootup will load ECID from legacy Identity direct extension
    func testLegacyEcidLoadedOnBootup() {
        initIdentityDirectAndWait() // register Identity Direct first to allow bootup and shared state creation
        let ecidLegacy = getLegacyEcidFromIdentity()

        registerIdentityEdgeAndWait() // register Identity Edge alone
        let ecidEdge = getEcidFromIdentityEdge()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)
    }

    /// Test IdentityEdge will include legacy ECID in IdentityMap when read from Identity Direct shared state
    func testLegacyEcidAddedToIdentityMapAfterBootup() {
        initExtensionsAndWait() // register and boot IdentityEdge
        let ecidEdge = getEcidFromIdentityEdge()

        registerIdentityDirectAndWait()
        let ecidLegacy = getLegacyEcidFromIdentity()

        let expectation2 = XCTestExpectation(description: "IdentityEdge.getIdentities callback")
        var identities: IdentityMap?
        IdentityEdge.getIdentities { identityMap, _ in
            identities = identityMap
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1)

        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertNotEqual(ecidLegacy, ecidEdge)

        XCTAssertNotNil(identities)

        var (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertEqual(true, primaryEcidItem?.primary)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
        XCTAssertEqual(false, legacyEcidItem?.primary)
    }

    /// Test IdentityEdge and IdentityDirect have same ECID on bootup, and after resetIdentities call ECIDs are different
    func testEcidsAreDifferentAfterReset() {
        // 1) Register Identity then IdentityEdge and verify both have same ECID
        initIdentityDirectAndWait()
        var ecidLegacy = getLegacyEcidFromIdentity()

        registerIdentityEdgeAndWait()
        let ecidEdge = getEcidFromIdentityEdge()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)

        // 2) Reset IdentityEdge identifiers and verify ECIDs are different
        IdentityEdge.resetIdentities()
        var (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNil(legacyEcidItem) // Legacy ECID is not set yet as it was cleared but no state change from Identity
        XCTAssertNotEqual(ecidLegacy, primaryEcidItem?.id)

        // 3) Identity Driect state change will add legacy ECID to Identity Map
        Identity.syncIdentifiers(identifiers: ["email": "email@example.com"])
        ecidLegacy = getLegacyEcidFromIdentity() // causes test to wait for state change from sync call

        (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNotNil(legacyEcidItem)
        XCTAssertNotEqual(legacyEcidItem?.id, primaryEcidItem?.id)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
    }

    /// Test IdentityEdge and IdentityDirect have same ECID on bootup, and after privacy change ECIDs are different
    func testEcidsAreDifferentAfterPrivacyChange() {
        // 1) Register Identity then IdentityEdge and verify both have same ECID
        initIdentityDirectAndWait()
        var ecidLegacy = getLegacyEcidFromIdentity()

        registerIdentityEdgeAndWait()
        let ecidEdge = getEcidFromIdentityEdge()

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

    /// Test IdentityEdge and IdentityDirect have same ECID on bootup, and after resetIdentities and privacy change ECIDs are different
    func testEcidsAreDifferentAfterResetIdentitiesAndPrivacyChange() {
        // 1) Register Identity then IdentityEdge and verify both have same ECID
        initIdentityDirectAndWait()
        var ecidLegacy = getLegacyEcidFromIdentity()

        registerIdentityEdgeAndWait()
        var ecidEdge = getEcidFromIdentityEdge()

        // verify ECIDs from both extensions are the same
        XCTAssertNotNil(ecidEdge)
        XCTAssertNotNil(ecidLegacy)
        XCTAssertEqual(ecidEdge, ecidLegacy)

        // 2) Reset identities and toggle privacy and verify legacy ECID added to IdentityMap
        IdentityEdge.resetIdentities()
        toggleGlobalPrivacy()
        ecidLegacy = getLegacyEcidFromIdentity()
        ecidEdge = getEcidFromIdentityEdge()

        let (primaryEcidItem, legacyEcidItem) = getPrimaryAndLegacyEcidIdentityItems()
        XCTAssertNotNil(primaryEcidItem)
        XCTAssertNotNil(legacyEcidItem)
        XCTAssertNotEqual(legacyEcidItem?.id, primaryEcidItem?.id)
        XCTAssertEqual(ecidEdge, primaryEcidItem?.id)
        XCTAssertEqual(ecidLegacy, legacyEcidItem?.id)
    }

    // MARK: helper funcs

    /// Register IdentityEdge + Configuration
    func initExtensionsAndWait() {
        let initExpectation = XCTestExpectation(description: "init Identity Edge extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.registerExtensions([IdentityEdge.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    /// Register Identity direct + Configuration
    func initIdentityDirectAndWait() {
        let initExpectation = XCTestExpectation(description: "init Identity Direct extensions")
        MobileCore.setLogLevel(.trace)
        MobileCore.updateConfigurationWith(configDict: defaultIdentityConfiguration)
        MobileCore.registerExtensions([Identity.self]) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    /// Register IdentityEdge. Should be called after one of the 'init' functions above.
    func registerIdentityEdgeAndWait() {
        let initExpectation = XCTestExpectation(description: "register Identity Edge extensions")
        MobileCore.registerExtension(IdentityEdge.self) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    /// Register Identity direct. Should be called after one of the 'init' functions above.
    func registerIdentityDirectAndWait() {
        let initExpectation = XCTestExpectation(description: "init Identity Direct extensions")
        MobileCore.updateConfigurationWith(configDict: defaultIdentityConfiguration)
        MobileCore.registerExtension(Identity.self) {
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 1)
    }

    func getEcidFromIdentityEdge() -> String? {
        let expectation = XCTestExpectation(description: "IdentityEdge.getExperienceCloudId callback")
        var ecid: String?
        IdentityEdge.getExperienceCloudId { id, _ in
            ecid = id
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return ecid
    }

    func getLegacyEcidFromIdentity() -> String? {
        let expectation = XCTestExpectation(description: "Identity.getExperienceCloudId callback")
        var ecid: String?
        Identity.getExperienceCloudId { id, _ in
            ecid = id
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        return ecid
    }

    func getPrimaryAndLegacyEcidIdentityItems() -> (IdentityItem?, IdentityItem?) {
        let expectation = XCTestExpectation(description: "IdentityEdge.getIdentities callback")
        var identities: IdentityMap?
        IdentityEdge.getIdentities { identityMap, _ in
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
            let primaryIndex = ecids[0].primary ? 0 : 1
            let legacyIndex = ecids[0].primary ? 1 : 0
            return (ecids[primaryIndex], ecids[legacyIndex])
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
}
