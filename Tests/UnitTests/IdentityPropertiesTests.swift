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

    /// When all properties all nil, the event data should be empty
    func testToEventDataEmpty() {
        // setup
        let properties = IdentityProperties()

        // test
        let eventData = properties.toEventData()

        // verify
        XCTAssertTrue(eventData.isEmpty)
    }

    /// Test that event data is populated correctly when all properties are non-nil
    func testToEventDataFull() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()

        // test
        let eventData = properties.toEventData()

        // verify
        XCTAssertEqual(1, eventData.count)
        XCTAssertEqual(properties.ecid?.ecidString, eventData[IdentityEdgeConstants.EventDataKeys.VISITOR_ID_ECID] as? String)
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

        // test
        let xdmData = properties.toXdmData()

        // verify
        XCTAssertEqual(1, xdmData.count)

        guard let jsonData = try? JSONSerialization.data(withJSONObject: xdmData) else {
            XCTFail("Failed to serialize dictionary to JSON data")
            return
        }

        let decoder = JSONDecoder()

        guard let identityMap = try? decoder.decode(IdentityMap.self, from: jsonData) else {
            XCTFail("Failed to decode JSON data to IdentityMap")
            return
        }

        let ecidItem = identityMap.getItemsFor(namespace: IdentityEdgeConstants.Namespaces.ECID)
        XCTAssertNotNil(ecidItem)
        XCTAssertEqual(1, ecidItem?.count)
        XCTAssertEqual(properties.ecid?.ecidString, ecidItem?[0].id)
        XCTAssertNil(ecidItem?[0].authenticationState)
        XCTAssertNil(ecidItem?[0].primary)
    }

    func testSaveToPersistenceLoadFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()

        let ecidString = properties.ecid?.ecidString

        // test
        properties.saveToPersistence()

        // reset
        properties.ecid = nil

        // test
        properties.loadFromPersistence()

        //verify
        XCTAssertEqual(1, mockDataStore.dict.count)
        XCTAssertNotNil(properties.ecid)
        XCTAssertEqual(ecidString, properties.ecid?.ecidString)
    }

}
