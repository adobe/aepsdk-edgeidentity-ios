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
        properties.ecid = ECID()
        properties.advertisingIdentifier = "test-ad-id"

        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.customerIdentifiers = identityMap

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid?.ecidString else {
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
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.advertisingIdentifier = ""
        properties.customerIdentifiers = IdentityMap()

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid?.ecidString else {
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
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.advertisingIdentifier = "test-ad-id"
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "custom")
        properties.customerIdentifiers = identityMap

        // test
        properties.saveToPersistence()

        // test
        var props = IdentityProperties()
        props.loadFromPersistence()

        //verify
        XCTAssertEqual(1, mockDataStore.dict.count)
        XCTAssertNotNil(props.ecid)
        XCTAssertEqual(properties.ecid?.ecidString, props.ecid?.ecidString)
        XCTAssertEqual(properties.advertisingIdentifier, props.advertisingIdentifier)
        XCTAssertNotNil(props.customerIdentifiers)
        XCTAssertEqual("identifier", props.customerIdentifiers?.getItems(withNamespace: "custom")?[0].id)
        XCTAssertEqual(.ambiguous, props.customerIdentifiers?.getItems(withNamespace: "custom")?[0].authenticationState)
        XCTAssertEqual(false, props.customerIdentifiers?.getItems(withNamespace: "custom")?[0].primary)
    }

}
