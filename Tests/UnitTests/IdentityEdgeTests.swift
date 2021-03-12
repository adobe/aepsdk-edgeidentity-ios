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
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.identityMap)
        XCTAssertEqual("id", identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer")?[0].id)
    }

    /// Tests when Identity receives an update identity event without valid data the customer identifiers are not updated
    func testIdentityUpdateIdentityWithNilData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identityEdge.state.identityEdgeProperties.updateCustomerIdentifiers(defaultIdentities)

        // setup
        let event = Event(name: "Test Update Identity",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.identityMap)
        XCTAssertEqual("id", identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer")?[0].id)
    }

    // MARK: handleRemoveIdentity

    /// Tests when Identity receives a remove identity event with valid data the customer identifiers are removed
    func testIdentityRemoveIdentityWithValidData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identityEdge.state.identityEdgeProperties.updateCustomerIdentifiers(defaultIdentities)
        // verify setup
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.identityMap)
        XCTAssertEqual("id", identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer")?[0].id)

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
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.identityMap)
        XCTAssertNil(identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer"))
    }

    /// Tests when Identity receives a remove identity event without valid data the customer identifiers are not modified
    func testIdentityRemoveIdentityWithNilData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identityEdge.state.identityEdgeProperties.updateCustomerIdentifiers(defaultIdentities)
        // verify setup
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.identityMap)
        XCTAssertEqual("id", identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer")?[0].id)

        // setup
        let event = Event(name: "Test Remove Identity",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify data is the same
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.identityMap)
        XCTAssertEqual("id", identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer")?[0].id)
    }

    // MARK: handleRequestReset

    /// Tests when Identity receives a request reset event that identifiers are cleared and ECID is regenerated
    func testIdentityRequestReset() {
        // setup
        let originalEcid = ECID()
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")
        identityEdge.state.identityEdgeProperties.updateCustomerIdentifiers(identityMap)
        identityEdge.state.identityEdgeProperties.ecid = originalEcid.ecidString

        let event = Event(name: "Test Request Event",
                          type: EventType.identityEdge,
                          source: EventSource.requestReset,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identityEdge.state.identityEdgeProperties.identityMap.getItems(withNamespace: "customer"))
        XCTAssertNotNil(identityEdge.state.identityEdgeProperties.ecid)
        XCTAssertNotEqual(originalEcid.ecidString, identityEdge.state.identityEdgeProperties.ecid)
    }

    // MARK: handleHubSharedState

    func testHandleHubSharedStateSetsLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
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
        XCTAssertEqual("legacyEcidValue", identityEdge.state.identityEdgeProperties.ecidSecondary)
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)

        guard let sharedState = mockRuntime.createdXdmSharedStates[0], let identityData = sharedState["identityMap"] as? [String: Any] else {
            XCTFail("Failed to get identityMap data from shared state")
            return
        }

        let identityMap = IdentityMap.from(eventData: identityData)
        XCTAssertNotNil(identityMap)
        XCTAssertEqual(2, identityMap?.getItems(withNamespace: "ECID")?.count)
    }

    func testHandleHubSharedStateWhenEcidNotInDataClearsLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        identityEdge.state.identityEdgeProperties.ecidSecondary = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT,
                                        event: event,
                                        data: (["somekey": "someValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identityEdge.state.identityEdgeProperties.ecidSecondary)
        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)

        guard let sharedState = mockRuntime.createdXdmSharedStates[0], let identityData = sharedState["identityMap"] as? [String: Any] else {
            XCTFail("Failed to get identityMap data from shared state")
            return
        }

        let identityMap = IdentityMap.from(eventData: identityData)
        XCTAssertNotNil(identityMap)
        XCTAssertEqual(1, identityMap?.getItems(withNamespace: "ECID")?.count)
    }

    func testHandleHubSharedStateWhenEcidTheSameDoesNotCreateSharedState() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        identityEdge.state.identityEdgeProperties.ecidSecondary = "currentLegacyEcid"

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
        XCTAssertEqual("currentLegacyEcid", identityEdge.state.identityEdgeProperties.ecidSecondary) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }

    func testHandleHubSharedStateWhenNoSharedStateDoesNotUpdateLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        identityEdge.state.identityEdgeProperties.ecidSecondary = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityEdgeConstants.EventDataKeys.STATE_OWNER: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identityEdge.state.identityEdgeProperties.ecidSecondary) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }

    func testHandleHubSharedStateWhenIncorrectStateownerDoesNotUpdateLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        identityEdge.state.identityEdgeProperties.ecidSecondary = "currentLegacyEcid"

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
        XCTAssertEqual("currentLegacyEcid", identityEdge.state.identityEdgeProperties.ecidSecondary) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }
}
