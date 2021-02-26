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
@testable import AEPIdentityEdge
import AEPServices
import XCTest

class IdentityEdgeTests: XCTestCase {
    var identityEdge: IdentityEdge!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identityEdge = IdentityEdge(runtime: mockRuntime)
        identityEdge.onRegistered()
    }

    // MARK: handleIdentifiersRequest

    /// Tests that when identity edge receives a identity request identity event with empty event data that we dispatch a response event with the identifiers
    func testIdentityEdgeRequestIdentifiersHappy() {
        // setup
        let event = Event(name: "Test Request Identifiers",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: nil)
        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.CONFIGURATION,
                                        event: event,
                                        data: (["testKey": "testVal"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    /// Tests that when identity edge receives a identity request identity event with empty event data and no config that we dispatch a response event with the identifiers
    func testIdentityEdgeRequestIdentifiersNoConfig() {
        // setup
        let event = Event(name: "Test Request Identifiers",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: nil)

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    // MARK: handleRequestContent

    /// Tests that when identity receives a generic identity request content event with an advertising ID, that the ID is updated
    func testGenericIdentityRequestWithAdId() {
        // setup
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityEdgeConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "newAdId"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("newAdId", identityEdge.state?.identityEdgeProperties.advertisingIdentifier)
    }

    /// Tests that when identity receives a generic identity request content event without an advertising ID, that the ID is not changed
    func testGenericIdentityRequestWithoutAdId() {
        // setup
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: ["someKey": "newAdId"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identityEdge.state?.identityEdgeProperties.advertisingIdentifier)
    }

    // MARK: handleUpdateIdentity

    /// Tests when Identity receives an update identity event with valid data the customer identifiers are updated
    func testIdentityUpdateIdentityWithValidData() {
        // setup
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")

        let event = Event(name: "Test Update Identity",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: identityMap.asDictionary())
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
        XCTAssertEqual("id", identityEdge.state?.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)
    }

    /// Tests when Identity receives an update identity event without valid data the customer identifiers are not updated
    func testIdentityUpdateIdentityWithNilData() {
        // setup
        let event = Event(name: "Test Update Identity",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
    }

    // MARK: handleRemoveIdentity

    /// Tests when Identity receives a remove identity event with valid data the customer identifiers are removed
    func testIdentityRemoveIdentityWithValidData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identityEdge.state?.identityEdgeProperties.customerIdentifiers = defaultIdentities
        // verify setup
        XCTAssertNotNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
        XCTAssertEqual("id", identityEdge.state?.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)

        // setup
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")

        let event = Event(name: "Test Remove Identity",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: identityMap.asDictionary())
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
        XCTAssertEqual(true, identityEdge.state?.identityEdgeProperties.customerIdentifiers?.isEmpty)
    }

    /// Tests when Identity receives a remove identity event without valid data the customer identifiers are not modified
    func testIdentityRemoveIdentityWithNilData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identityEdge.state?.identityEdgeProperties.customerIdentifiers = defaultIdentities
        // verify setup
        XCTAssertNotNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
        XCTAssertEqual("id", identityEdge.state?.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)

        // setup
        let event = Event(name: "Test Remove Identity",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify data is the same
        XCTAssertNotNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
        XCTAssertEqual("id", identityEdge.state?.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)
    }

    // MARK: handleRequestReset

    /// Tests when Identity receives a request reset event that identifiers are cleared and ECID is regenerated
    func testIdentityRequestReset() {
        // setup
        let originalEcid = ECID()
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")
        identityEdge.state?.identityEdgeProperties.customerIdentifiers = identityMap
        identityEdge.state?.identityEdgeProperties.advertisingIdentifier = "adid"
        identityEdge.state?.identityEdgeProperties.ecid = originalEcid

        let event = Event(name: "Test Request Event",
                          type: EventType.identityEdge,
                          source: EventSource.requestReset,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identityEdge.state?.identityEdgeProperties.customerIdentifiers)
        XCTAssertNil(identityEdge.state?.identityEdgeProperties.advertisingIdentifier)
        XCTAssertNotNil(identityEdge.state?.identityEdgeProperties.ecid)
        XCTAssertNotEqual(originalEcid.ecidString, identityEdge.state?.identityEdgeProperties.ecid?.ecidString)
    }

    // MARK: handleHubSharedState

    func testHandleHubSharedStateSetsLegacyEcid() {
        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT,
                                        event: event,
                                        data: ([IdentityEdgeConstants.EventDataKeys.VISITOR_ID_ECID: "legacyEcidValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("legacyEcidValue", identityEdge.state?.identityEdgeProperties.ecidLegacy)
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
    }

    func testHandleHubSharedStateWhenEcidNotInDataClearsLegacyEcid() {
        identityEdge.state?.identityEdgeProperties.ecidLegacy = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT,
                                        event: event,
                                        data: (["somekey": "legacyEcidValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual(true, identityEdge.state?.identityEdgeProperties.ecidLegacy?.isEmpty)
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
    }

    func testHandleHubSharedStateWhenEcidTheSameDoesNotCreateSharedState() {
        identityEdge.state?.identityEdgeProperties.ecidLegacy = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT,
                                        event: event,
                                        data: ([IdentityEdgeConstants.EventDataKeys.VISITOR_ID_ECID: "currentLegacyEcid"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identityEdge.state?.identityEdgeProperties.ecidLegacy) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }

    func testHandleHubSharedStateWhenNoSharedStateDoesNotUpdateLegacyEcid() {
        identityEdge.state?.identityEdgeProperties.ecidLegacy = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identityEdge.state?.identityEdgeProperties.ecidLegacy) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }

    func testHandleHubSharedStateWhenIncorrectStateownerDoesNotUpdateLegacyEcid() {
        identityEdge.state?.identityEdgeProperties.ecidLegacy = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.CONFIGURATION])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT,
                                        event: event,
                                        data: ([IdentityEdgeConstants.EventDataKeys.VISITOR_ID_ECID: "legacyEcidValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identityEdge.state?.identityEdgeProperties.ecidLegacy) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }
}
