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

@testable import AEPEdgeIdentity
import AEPServices
import XCTest

class IdentityPropertiesTests: XCTestCase {

    var mockDataStore: MockDataStore {
        return ServiceProvider.shared.namedKeyValueService as! MockDataStore
    }

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
    }

    /// When all properties all nil, the xdm data should be empty
    func testToXdmDataEmpty() {
        // setup
        let properties = IdentityProperties()

        // test
        let xdmData = properties.toXdmData()

        // verify
        XCTAssertTrue(xdmData.isEmpty)
    }

    /// Test that xdm data is populated correctly when all properties are non-nil
    func testToXdmDataFull() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.advertisingIdentifier = "test-ad-id"

        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.updateCustomerIdentifiers(identityMap)

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid else {
            XCTFail("properties.ecid is nil, which is unexpected.")
            return
        }

        // verify
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(ecidString)", "authenticatedState": "ambiguous", "primary": 0] ],
                "IDFA": [ ["id": "test-ad-id", "authenticatedState": "ambiguous", "primary": 0] ],
                "custom": [ ["id": "identifier", "authenticatedState": "ambiguous", "primary": 0] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testToXdmDataDoesNotIncludeEmptyValues() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.advertisingIdentifier = ""

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid else {
            XCTFail("properties.ecid is nil, which is unexpected.")
            return
        }

        // verify
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(ecidString)", "authenticatedState": "ambiguous", "primary": 0] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testSetPrimaryECIDPreservesSecondaryECID() {
        // setup
        let primaryEcid = ECID()
        let secondaryEcid = ECID()

        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.ecidSecondary = secondaryEcid.ecidString

        // test
        properties.ecid = primaryEcid.ecidString
        let xdmData = properties.toXdmData()

        // verify
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(primaryEcid.ecidString)", "authenticatedState": "ambiguous", "primary": 0],
                          ["id": "\(secondaryEcid.ecidString)", "authenticatedState": "ambiguous", "primary": 0]]
            ]]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testSetSecondaryECID() {
        // setup
        let primaryEcid = ECID()
        let secondaryEcid = ECID()

        var properties = IdentityProperties()
        properties.ecid = primaryEcid.ecidString
        properties.ecidSecondary = ECID().ecidString

        // test
        properties.ecidSecondary = secondaryEcid.ecidString
        let xdmData = properties.toXdmData()

        // verify
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(primaryEcid.ecidString)", "authenticatedState": "ambiguous", "primary": 0],
                          ["id": "\(secondaryEcid.ecidString)", "authenticatedState": "ambiguous", "primary": 0]]
            ]]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testClearPrimaryECIDAlsoClearsSecondaryECID() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.ecidSecondary = ECID().ecidString

        // test
        properties.ecid = nil
        let xdmData = properties.toXdmData()

        // verify
        let expectedResult: [String: Any] = [:]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testCannotSetSecondaryECIDIfPrimaryNotSet() {
        // setup
        var properties = IdentityProperties()
        properties.ecidSecondary = ECID().ecidString

        // test
        properties.ecid = nil
        let xdmData = properties.toXdmData()

        // verify
        let expectedResult: [String: Any] = [:]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testSaveToPersistenceLoadFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.advertisingIdentifier = "test-ad-id"
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.updateCustomerIdentifiers(identityMap)

        // test
        properties.saveToPersistence()

        // test
        var props = IdentityProperties()
        props.loadFromPersistence()

        // verify
        XCTAssertEqual(1, mockDataStore.dict.count)
        XCTAssertNotNil(props.ecid)
        XCTAssertEqual(properties.ecid, props.ecid)
        XCTAssertEqual(properties.advertisingIdentifier, props.advertisingIdentifier)
        XCTAssertEqual("identifier", props.identityMap.getItems(withNamespace: "custom")?[0].id)
        XCTAssertEqual(.ambiguous, props.identityMap.getItems(withNamespace: "custom")?[0].authenticatedState)
        XCTAssertEqual(false, props.identityMap.getItems(withNamespace: "custom")?[0].primary)
    }

    func testSaveToPersistenceHasIdentityMap() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.advertisingIdentifier = "test-ad-id"
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.updateCustomerIdentifiers(identityMap)

        // test
        properties.saveToPersistence()

        XCTAssertEqual(1, mockDataStore.dict.count)
        guard let data = mockDataStore.dict[IdentityConstants.DataStoreKeys.IDENTITY_PROPERTIES] as? Data else {
            XCTFail("Failed to find identity.properties in mock data store.")
            return
        }

        // parse persisted data as dictionary
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            XCTFail("Failed to decode identity.properties to dictionary.")
            return
        }

        let decodedProperties = json as? [String: Any]
        let decodedMap = decodedProperties?["identityMap"] as? [String: [Any]]

        // verify
        // IdentityMap has 3 items, and each item has only 1 item
        XCTAssertEqual(3, decodedMap?.count)
        XCTAssertEqual(1, decodedMap?["ECID"]?.count)
        XCTAssertEqual(1, decodedMap?["IDFA"]?.count)
        XCTAssertEqual(1, decodedMap?["custom"]?.count)

        XCTAssertEqual(properties.ecid, (decodedMap?["ECID"]?[0] as? [String: Any])?["id"] as? String)
        XCTAssertEqual("test-ad-id", (decodedMap?["IDFA"]?[0] as? [String: Any])?["id"] as? String)
        XCTAssertEqual("identifier", (decodedMap?["custom"]?[0] as? [String: Any])?["id"] as? String)
        XCTAssertEqual("ambiguous", (decodedMap?["IDFA"]?[0] as? [String: Any])?["authenticatedState"] as? String)
        XCTAssertEqual(false, (decodedMap?["IDFA"]?[0] as? [String: Any])?["primary"] as? Bool)
    }

    func testGetEcidFromDirectIdentityPersistenceWhenNoDirectIdentityDatastoreReturnsNil() {
        let properties = IdentityProperties()
        XCTAssertNil(properties.getEcidFromDirectIdentityPersistence())
    }

    func testGetEcidFromDirectIdentityPersistenceReturnsEcid() {
        let legacyEcid = ECID()
        addLegacyEcidToPersistence(ecid: legacyEcid)

        let properties = IdentityProperties()
        XCTAssertEqual(legacyEcid.ecidString, properties.getEcidFromDirectIdentityPersistence()?.ecidString)
    }

    func testGetEcidFromDirectIdentityPersistenceReturnsEcidNil() {
        addLegacyEcidToPersistence(ecid: nil)

        let properties = IdentityProperties()
        XCTAssertNil(properties.getEcidFromDirectIdentityPersistence())
    }

    private func addLegacyEcidToPersistence(ecid: ECID?) {
        let data: [String: ECID?] = ["ecid": ecid]
        let jsonData = try? JSONEncoder().encode(data)
        mockDataStore.dict["identity.properties"] = jsonData
    }

}
