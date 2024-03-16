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
import AEPTestUtils
import XCTest

class IdentityAdIDTests: XCTestCase, AnyCodableAsserts {
    var identity: Identity!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        continueAfterFailure = false
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
    }

    func createGenericIdentityRequestEvent(withData: [String: Any]?) -> Event {
        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: withData)
        return event
    }

    func testAdIDEmpty_whenInt() {
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: 1])
        XCTAssertEqual(event.adId, "")
    }

    func testAdIDEmpty_whenDouble() {
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: 1.1])
        XCTAssertEqual(event.adId, "")
    }

    func testAdIDEmpty_whenAllZeros() {
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID])
        XCTAssertEqual(event.adId, "")
    }

    func testAdIDValid_whenValid() {
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "adID"])
        XCTAssertEqual(event.adId, "adID")
    }

    func testIsAdIDEventTrue_whenKeyPresent() {
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "adID"])
        XCTAssertTrue(event.isAdIdEvent)
    }

    func testIsAdIDEventFalse_whenKeyAbsent() {
        let event = createGenericIdentityRequestEvent(withData: ["somekey": "someValue"])
        XCTAssertFalse(event.isAdIdEvent)
    }

    func testIsAdIDEventFalse_whenNoData() {
        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: nil)
        XCTAssertFalse(event.isAdIdEvent)
    }

    // MARK: - Starting from valid ad ID
    /// Test ad ID is updated from old to new valid value, and consent event is not dispatched
    func testGenericIdentityRequest_whenValidAdId_thenNewValidAdId() {
        let newAdID = "adID"
        setupIdentity(withAdID: "initialAdID")
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: newAdID])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertEqual(newAdID, identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ],
            "IDFA": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(newAdID)",
                "primary": false
              }
            ]
          }
        }
        """#

        // 2 Shared states expected:
        // 1. Bootup (ECID + initial ad ID)
        // 2. Request content event with new valid ad ID (ECID + new ad ID)
        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[1])))
        // No dispatched events because consent event should not happen
        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    /// Test ad ID stays the same with same new valid value, and consent event is not dispatched
    func testGenericIdentityRequest_whenValidAdId_thenSameValidAdId() {
        let initialAdID = "initialAdID"
        setupIdentity(withAdID: initialAdID)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: initialAdID])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertEqual(initialAdID, identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ],
            "IDFA": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(initialAdID)",
                "primary": false
              }
            ]
          }
        }
        """#
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[0])))
        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    /// Test ad ID stays the same with non-ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenValidAdId_thenNoAdId() {
        let initialAdID = "initialAdID"
        setupIdentity(withAdID: initialAdID)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: ["somekey": "someValue"])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertEqual(initialAdID, identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ],
            "IDFA": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(initialAdID)",
                "primary": false
              }
            ]
          }
        }
        """#
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[0])))
        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    /// Test ad ID is updated from valid to nil, and consent event is dispatched
    func testGenericIdentityRequest_whenValidAdId_thenEmptyAdId() {
        let initialAdID = "initialAdID"
        setupIdentity(withAdID: initialAdID)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)
        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ]
          }
        }
        """#

        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[1])))

        // Consent event should be dispatched; check that the event body matches expected format
        let expectedConsentJSON = #"""
        {
          "consents": {
            "adID": {
              "idType": "IDFA",
              "val": "n"
            }
          }
        }
        """#
        XCTAssertEqual(EventType.edgeConsent, mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual(EventSource.updateConsent, mockRuntime.dispatchedEvents[0].source)
        assertEqual(expected: getAnyCodable(expectedConsentJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.dispatchedEvents[0].data)))
    }

    /// Test ad ID is updated from valid to nil, and consent event is dispatched
    func testGenericIdentityRequest_whenValidAdId_thenAllZerosId() {
        setupIdentity(withAdID: "initialAdID")
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ]
          }
        }
        """#

        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[1])))

        let expectedConsentJSON = #"""
        {
          "consents": {
            "adID": {
              "idType": "IDFA",
              "val": "n"
            }
          }
        }
        """#
        XCTAssertEqual(EventType.edgeConsent, mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual(EventSource.updateConsent, mockRuntime.dispatchedEvents[0].source)
        assertEqual(expected: getAnyCodable(expectedConsentJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.dispatchedEvents[0].data)))
    }

    // MARK: - Starting from no ad ID
    /// Test ad ID is updated from nil to valid, and consent event is dispatched
    func testGenericIdentityRequest_whenNoAdId_thenNewValidAdId() {
        let newAdID = "adID"
        setupIdentity(withAdID: nil)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: newAdID])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertEqual(newAdID, identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ],
            "IDFA": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(newAdID)",
                "primary": false
              }
            ]
          }
        }
        """#
        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[1])))

        let expectedConsentJSON = #"""
        {
          "consents": {
            "adID": {
              "idType": "IDFA",
              "val": "y"
            }
          }
        }
        """#
        XCTAssertEqual(EventType.edgeConsent, mockRuntime.dispatchedEvents[0].type)
        XCTAssertEqual(EventSource.updateConsent, mockRuntime.dispatchedEvents[0].source)
        assertEqual(expected: getAnyCodable(expectedConsentJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.dispatchedEvents[0].data)))
    }

    /// Test ad ID remains nil with non-ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenNoAdId_thenNoAdId() {
        setupIdentity(withAdID: nil)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: ["somekey": "someValue"])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ]
          }
        }
        """#
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[0])))
        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    /// Test ad ID remains nil with empty string ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenNoAdId_thenEmptyAdId() {
        setupIdentity(withAdID: nil)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ]
          }
        }
        """#
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[0])))
        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    /// Test ad ID remains nil with all-zero ad ID event, and consent event is not dispatched
    func testGenericIdentityRequest_whenNoAdId_thenAllZerosId() {
        setupIdentity(withAdID: nil)
        let propsECID = getECIDFromIdentityProperties()
        let event = createGenericIdentityRequestEvent(withData: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID])

        // Test
        mockRuntime.simulateComingEvents(event)

        // Verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)

        let expectedIdentityJSON = #"""
        {
          "identityMap": {
            "ECID": [
              {
                "authenticatedState": "ambiguous",
                "id": "\#(propsECID)",
                "primary": false
              }
            ]
          }
        }
        """#
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
        assertEqual(expected: getAnyCodable(expectedIdentityJSON)!,
                    actual: AnyCodable(AnyCodable.from(dictionary: mockRuntime.createdXdmSharedStates[0])))
        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    // MARK: Test helpers
    /// Sets up the IdentityProperties with the desired advertising identifier
    private func setupIdentity(withAdID: String?) {
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.advertisingIdentifier = withAdID
        props.saveToPersistence()

        // Simulate bootup as mockRuntime.simulateComingEvent bypasses call to readyForEvent
        let testEvent = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(testEvent))
    }

    private func getECIDFromIdentityProperties() -> String {
        guard let propsECID = identity.state.identityProperties.ecid else {
            XCTFail("ECID saved to Identity properties is not valid")
            return ""
        }
        return propsECID
    }
}
