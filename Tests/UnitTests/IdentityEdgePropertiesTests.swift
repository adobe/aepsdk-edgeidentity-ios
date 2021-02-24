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

@testable import AEPIdentityEdge
import AEPServices
import XCTest

class IdentityEdgePropertiesTests: XCTestCase {

    var mockDataStore: MockDataStore {
        return ServiceProvider.shared.namedKeyValueService as! MockDataStore
    }

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
    }

    /// When all properties all nil, the xdm data should be empty
    func testToXdmDataEmpty() {
        // setup
        let properties = IdentityEdgeProperties()

        // test
        let xdmData = properties.toXdmData()

        // verify
        XCTAssertTrue(xdmData.isEmpty)
    }

    /// Test that xdm data is populated correctly when all properties are non-nil
    func testToXdmDataFull() {
        // setup
        var properties = IdentityEdgeProperties()
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
                "ECID": [ ["id": "\(ecidString)", "authenticationState": "ambiguous", "primary": 1] ],
                "IDFA": [ ["id": "test-ad-id", "authenticationState": "ambiguous", "primary": 0] ],
                "custom": [ ["id": "identifier", "authenticationState": "ambiguous", "primary": 0] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testToXdmDataDoesNotIncludeEmptyValues() {
        // setup
        var properties = IdentityEdgeProperties()
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
                "ECID": [ ["id": "\(ecidString)", "authenticationState": "ambiguous", "primary": 1] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testSaveToPersistenceLoadFromPersistence() {
        // setup
        var properties = IdentityEdgeProperties()
        properties.ecid = ECID().ecidString
        properties.advertisingIdentifier = "test-ad-id"
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.updateCustomerIdentifiers(identityMap)

        // test
        properties.saveToPersistence()

        // test
        var props = IdentityEdgeProperties()
        props.loadFromPersistence()

        //verify
        XCTAssertEqual(1, mockDataStore.dict.count)
        XCTAssertNotNil(props.ecid)
        XCTAssertEqual(properties.ecid, props.ecid)
        XCTAssertEqual(properties.advertisingIdentifier, props.advertisingIdentifier)
        XCTAssertEqual("identifier", props.propertyMap.getItems(withNamespace: "custom")?[0].id)
        XCTAssertEqual(.ambiguous, props.propertyMap.getItems(withNamespace: "custom")?[0].authenticationState)
        XCTAssertEqual(false, props.propertyMap.getItems(withNamespace: "custom")?[0].primary)
    }

    func testSaveToPersistenceIsIdentityMap() {
        // setup
        var properties = IdentityEdgeProperties()
        properties.ecid = ECID().ecidString
        properties.advertisingIdentifier = "test-ad-id"
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.updateCustomerIdentifiers(identityMap)

        // test
        properties.saveToPersistence()

        XCTAssertEqual(1, mockDataStore.dict.count)
        guard let data = mockDataStore.dict[IdentityEdgeConstants.DataStoreKeys.IDENTITY_PROPERTIES] as? Data else {
            XCTFail("Failed to find identity.properties in mock data store.")
            return
        }

        guard let identities = try? JSONDecoder().decode(IdentityMap.self, from: data) else {
            XCTFail("Failed to decode identity.properties to IdentityMap.")
            return
        }

        // verify
        XCTAssertEqual(properties.ecid, identities.getItems(withNamespace: IdentityEdgeConstants.Namespaces.ECID)?[0].id)
        XCTAssertEqual("test-ad-id", identities.getItems(withNamespace: IdentityEdgeConstants.Namespaces.IDFA)?[0].id)
        XCTAssertEqual("identifier", identities.getItems(withNamespace: "custom")?[0].id)
        XCTAssertEqual(.ambiguous, identities.getItems(withNamespace: "custom")?[0].authenticationState)
        XCTAssertEqual(false, identities.getItems(withNamespace: "custom")?[0].primary)
    }

}
