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
@testable import AEPEdgeIdentity
import AEPServices
import XCTest

class IdentityEdgeTests: XCTestCase {
    var identity: Identity!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        continueAfterFailure = false
        let savedLogFilterValue = Log.logFilter
        Log.logFilter = .trace
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
        
    }

    // MARK: handleIdentityRequest
    func testGenericIdentityRequestSetsAdId() {
        // Save previous log filter value
        let savedLogFilterValue = Log.logFilter
        Log.logFilter = .trace
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.advertisingIdentifier = "oldAdId"
        props.saveToPersistence()
        
        // simulate bootup as mockRuntime bypasses call to readyForEvent
        let testEvent = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(testEvent))

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "adId"])

        
        // no longer calls bootupIfReady
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("adId", identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid ?? "")", "authenticatedState": "ambiguous", "primary": 0]],
                    "IDFA": [["id": "adId", "authenticatedState": "ambiguous", "primary": 0]]
                ]
            ]
        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty) // no Consent event dispatched
        Log.logFilter = savedLogFilterValue
    }

    func testGenericIdentityRequestClearsAdId() {
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.advertisingIdentifier = "oldAdId"
        props.saveToPersistence()
        
        // simulate bootup as mockRuntime bypasses call to readyForEvent
        let testEvent = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(testEvent))

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid ?? "")", "authenticatedState": "ambiguous", "primary": 0]]
                ]
            ]
        
        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)
        
    }
    // TODO: more e2e tests that trigger different states
    // consent integration, dispatching consent event correctly (test above will not trigger this behavior)
    // need trigger consent y & consent n
    // need test for not sending out consent in the case of having existing adid & updating to new one (consent hasnt changed, dont need to emit event)
    // if persisted adid is blank & pass in all 0, shouldnt dispatch (treat all 0 as a blank string; that is, value hasn't changed, and adid should be treated logically as nil)
    // test to make sure you cant set IDFA directly using update APIs or remove (should already exist, verify - updatecustomidentifiers, removeidentiteswithreservednamespaces)
        // only way to update ADID should be setADID APIs 
    // current tests show that old ad id is set/cleared correctly
    // - only testing that setting various values updates correctly; can be done through unit testing through identity properties
}
