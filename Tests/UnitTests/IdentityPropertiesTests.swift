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
        properties.pushIdentifier = "push-id"
        properties.blob = "blob"
        properties.locationHint = "locationHint"
        properties.lastSync = Date.init()
        properties.ttl = TimeInterval(3600)
        properties.customerIds = [CustomIdentity.init(origin: "origin", type: "type", identifier: "id", authenticationState: .authenticated)]

        // test
        let eventData = properties.toEventData()

        // verify
        // Event Data will contain all the IdentityProperties
        XCTAssertEqual(7, eventData.count)
        XCTAssertEqual(properties.ecid?.ecidString, eventData[IdentityConstants.EventDataKeys.VISITOR_ID_ECID] as? String)
        XCTAssertEqual(properties.advertisingIdentifier, eventData[IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertEqual(properties.pushIdentifier, eventData[IdentityConstants.EventDataKeys.PUSH_IDENTIFIER] as? String)
        XCTAssertEqual(properties.blob, eventData[IdentityConstants.EventDataKeys.VISITOR_ID_BLOB] as? String)
        XCTAssertEqual(properties.locationHint, eventData[IdentityConstants.EventDataKeys.VISITOR_ID_LOCATION_HINT] as? String)
        XCTAssertNotNil(eventData[IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]])
        XCTAssertEqual(properties.lastSync?.timeIntervalSince1970, eventData[IdentityConstants.EventDataKeys.VISITOR_IDS_LAST_SYNC] as? TimeInterval)
    }

    func testToEventDataDoesNotIncludeEmptyValues() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.advertisingIdentifier = ""

        // test
        let eventData = properties.toEventData()

        // verify
        XCTAssertEqual(1, eventData.count)
        XCTAssertEqual(properties.ecid?.ecidString, eventData[IdentityConstants.EventDataKeys.VISITOR_ID_ECID] as? String)
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
        properties.pushIdentifier = "push-id"
        properties.blob = "blob"
        properties.locationHint = "locationHint"
        properties.lastSync = Date.init()
        properties.ttl = TimeInterval(3600)
        properties.customerIds = [CustomIdentity.init(origin: "origin", type: "type", identifier: "id", authenticationState: .authenticated)]

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid?.ecidString else {
            XCTFail("properties.ecid is nil, which is unexpected.")
            return
        }

        // verify
        // XDM data only contains ECID and IDFA from IdentityProperties
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(ecidString)"] ],
                "IDFA": [ ["id": "test-ad-id"] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testToXdmDataDoesNotIncludeEmptyValues() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.advertisingIdentifier = ""

        // test
        let xdmData = properties.toXdmData()

        guard let ecidString = properties.ecid?.ecidString else {
            XCTFail("properties.ecid is nil, which is unexpected.")
            return
        }

        // verify
        let expectedResult: [String: Any] =
            [ "identityMap": [
                "ECID": [ ["id": "\(ecidString)"] ]
            ]
            ]

        XCTAssertEqual(expectedResult as NSObject, xdmData as NSObject)
    }

    func testSaveToPersistenceLoadFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.advertisingIdentifier = "test-ad-id"
        properties.pushIdentifier = "push-id"
        properties.blob = "blob"
        properties.locationHint = "locationHint"
        properties.lastSync = Date.init()
        properties.ttl = TimeInterval(3600)
        properties.customerIds = [CustomIdentity.init(origin: "origin", type: "type", identifier: "id", authenticationState: .authenticated)]

        // test
        properties.saveToPersistence()

        var props = IdentityProperties()
        props.loadFromPersistence()

        //verify
        XCTAssertEqual(1, mockDataStore.dict.count)
        XCTAssertNotNil(props.ecid)
        XCTAssertEqual(properties.ecid?.ecidString, props.ecid?.ecidString)
        XCTAssertEqual("test-ad-id", props.advertisingIdentifier)
        XCTAssertEqual("push-id", props.pushIdentifier)
        XCTAssertEqual("blob", props.blob)
        XCTAssertEqual("locationHint", props.locationHint)
        XCTAssertEqual(properties.lastSync, props.lastSync)
        XCTAssertEqual(TimeInterval(3600), props.ttl)
        XCTAssertNotNil(props.customerIds)

    }

}
