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
