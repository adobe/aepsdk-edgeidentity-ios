//
// Copyright 2022 Adobe. All rights reserved.
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

class IdentityAdIDTests: XCTestCase {
    var identity: Identity!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        continueAfterFailure = false
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
    }

    // MARK: handleIdentityRequest
    /// Test ad ID is updated from old to new valid value, and consent true is dispatched
    func testGenericIdentityRequest_whenValidAdId_thenNewValidAdId() {
        // Save previous log filter value
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
    }
    
    /// Test ad ID stays the same with same new valid value, and consent event is not dispatched
    func testGenericIdentityRequest_whenValidAdId_thenSameValidAdId() {
        // Save previous log filter value
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
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "oldAdId"])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("oldAdId", identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid ?? "")", "authenticatedState": "ambiguous", "primary": 0]],
                    "IDFA": [["id": "oldAdId", "authenticatedState": "ambiguous", "primary": 0]]
                ]
            ]
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[0] as NSObject?)

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty) // no Consent event dispatched
    }
    
    /// Test ad ID stays the same with non-ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenValidAdId_thenNoAdId() {
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
                          data: ["somekey": "someValue"])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("oldAdId", identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid ?? "")", "authenticatedState": "ambiguous", "primary": 0]],
                    "IDFA": [["id": "oldAdId", "authenticatedState": "ambiguous", "primary": 0]]
                ]
            ]

        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[0] as NSObject?)
    }

    /// Test ad ID is updated from valid to nil, and consent event is dispatched
    func testGenericIdentityRequest_whenValidAdId_thenEmptyAdId() {
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
        
        let expectedConsent: [String: Any] =
            [
                "consents": [
                    "adID": [
                        "val": "n",
                        "idType": "IDFA"
                    ]
                ]
            ]
        XCTAssertEqual(EventType.edgeConsent, mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual(EventSource.updateConsent, mockRuntime.dispatchedEvents[0].source)
        XCTAssertEqual(expectedConsent as NSObject, mockRuntime.dispatchedEvents[0].data as NSObject?)
    }
    
    /// Test ad ID is updated from valid to nil, and consent event is dispatched
    func testGenericIdentityRequest_whenValidAdId_thenAllZerosId() {
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
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID])

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
    
    // MARK: - Starting from no ad ID
    /// Test ad ID is updated from nil to valid, and consent event is dispatched
    func testGenericIdentityRequest_whenNoAdId_thenNewValidAdId() {
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.saveToPersistence()

        // simulate bootup as mockRuntime bypasses call to readyForEvent
        let testEvent = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(testEvent))

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "AdId"])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("AdId", identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid ?? "")", "authenticatedState": "ambiguous", "primary": 0]],
                    "IDFA": [["id": "AdId", "authenticatedState": "ambiguous", "primary": 0]]
                ]
            ]

        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)
    }
    
    /// Test ad ID remains nil with non-ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenNoAdId_thenNoAdId() {
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.saveToPersistence()

        // simulate bootup as mockRuntime bypasses call to readyForEvent
        let testEvent = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(testEvent))

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: ["somekey": "someValue"])

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

        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[0] as NSObject?)
    }
    
    /// Test ad ID remains nil with nil ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenNoAdId_thenEmptyAdId() {
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
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

        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[0] as NSObject?)
    }
    
    /// Test ad ID remains nil with nil ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenNoAdId_thenAllZerosId() {
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.saveToPersistence()

        // simulate bootup as mockRuntime bypasses call to readyForEvent
        let testEvent = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(testEvent))

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID])

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

        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[0] as NSObject?)
    }
}
