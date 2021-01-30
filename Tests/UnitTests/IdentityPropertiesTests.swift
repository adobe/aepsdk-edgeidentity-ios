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
        properties.advertisingIdentifier = "test-ad-id"

        // test
        let eventData = properties.toEventData()

        // verify
        XCTAssertEqual(2, eventData.count)
        XCTAssertEqual(properties.ecid?.ecidString, eventData[IdentityConstants.EventDataKeys.VISITOR_ID_ECID] as? String)
        XCTAssertEqual(properties.advertisingIdentifier, eventData[IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
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

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid?.ecidString else {
            XCTFail("properties.ecid is nil, which is unexpected.")
            return
        }

        // verify
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(ecidString)"] ],
                "IDFA": [ ["id": "test-ad-id"] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
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
