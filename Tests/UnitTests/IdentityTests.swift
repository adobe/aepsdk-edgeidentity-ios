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

class IdentityTests: XCTestCase {
    var identity: Identity!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
        // simulate bootup as mockRuntime bypasses call to readyForEvent
        let event = Event(name: "test-event", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(event))

        XCTAssertEqual(1, mockRuntime.createdXdmSharedStates.count)
        XCTAssertTrue(mockRuntime.createdSharedStates.isEmpty)
    }

    // MARK: handleIdentifiersRequest

    /// Tests that when identity receives an edge identity request identity event with empty event data that we dispatch a response event with the identifiers
    func testEdgeIdentityRequestIdentifiersHappy() {
        // setup
        let event = Event(name: "Test Request Identifiers",
                          type: EventType.edgeIdentity,
                          source: EventSource.requestIdentity,
                          data: nil)
        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                        event: event,
                                        data: (["testKey": "testVal"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    /// Tests that when identity receives an edge identity request identity event with empty event data and no config that we dispatch a response event with the identifiers
    func testEdgeIdentityRequestIdentifiersNoConfig() {
        // setup
        let event = Event(name: "Test Request Identifiers",
                          type: EventType.edgeIdentity,
                          source: EventSource.requestIdentity,
                          data: nil)

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    /// Tests that when identity receives an edge identity request identity event with urlVariables flag set that we dispatch a response event with the UrlVariables string
    func testEdgeIdentityRequestIdentifiersGetUrlVariables_returnsProperUrlString() {
        // setup
        let testECID = ECID()
        identity.state.identityProperties.ecid = testECID.ecidString
        let getUrlVariablesEvent = Event(name: "Test Request Identifiers",
                                         type: EventType.edgeIdentity,
                                         source: EventSource.requestIdentity,
                                         data: [IdentityConstants.EventDataKeys.URL_VARIABLES: true])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event: getUrlVariablesEvent, data: ([IdentityConstants.ConfigurationKeys.EXPERIENCE_CLOUD_ORGID: "test-org-id@AdobeOrg"], .set))

        // test
        mockRuntime.simulateComingEvent(event: getUrlVariablesEvent)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == getUrlVariablesEvent.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertEqual(EventType.edgeIdentity, responseEvent?.type)
        XCTAssertEqual(EventSource.responseIdentity, responseEvent?.source)
        let urlVariablesString = responseEvent?.data?[IdentityConstants.EventDataKeys.URL_VARIABLES] as? String ?? ""
        XCTAssertFalse(urlVariablesString.isEmpty)

        let expectedUrlVariableTSString = "adobe_mc=TS%3"
        let expectedUrlVariableIdentifiersString = "%7C" + "MCMID" + "%3D" + testECID.ecidString + "%7C" + "MCORGID" + "%3D" + "test-org-id%40AdobeOrg"
        XCTAssertTrue(urlVariablesString.contains(expectedUrlVariableTSString))
        XCTAssertTrue(urlVariablesString.contains(expectedUrlVariableIdentifiersString))
    }

    /// Tests that when identity receives an edge identity request identity event with urlVariables flag set and missing org id configuration will dispatch a response event with empty url variables string
    func testEdgeIdentityRequestIdentifiersGetUrlVariables_whenOrgIdMissing_returnsNil() {
        // setup
        let getUrlVariablesEvent = Event(name: "Test Request Identifiers",
                                         type: EventType.edgeIdentity,
                                         source: EventSource.requestIdentity,
                                         data: [IdentityConstants.EventDataKeys.URL_VARIABLES: true])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event: getUrlVariablesEvent, data: (["test": "value"], .set))

        // test
        mockRuntime.simulateComingEvent(event: getUrlVariablesEvent)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == getUrlVariablesEvent.id })
        XCTAssertEqual(responseEvent?.data?[IdentityConstants.EventDataKeys.URL_VARIABLES] as? String, "")

    }

    /// Tests that when identity receives an edge identity request identity event with urlVariables flag set and missing ecid will dispatch a response event with empty url variables string
    func testEdgeIdentityRequestIdentifiersGetUrlVariables_whenECIDNotGenerated_returnsNil() {
        // setup
        let getUrlVariablesEvent = Event(name: "Test Request Identifiers",
                                         type: EventType.edgeIdentity,
                                         source: EventSource.requestIdentity,
                                         data: [IdentityConstants.EventDataKeys.URL_VARIABLES: true])

        // simulate ecid not being generated
        identity.state.identityProperties.ecid = nil

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event: getUrlVariablesEvent, data: ([IdentityConstants.ConfigurationKeys.EXPERIENCE_CLOUD_ORGID: "test-org-id@AdobeOrg"], .set))

        // test
        mockRuntime.simulateComingEvent(event: getUrlVariablesEvent)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == getUrlVariablesEvent.id })
        XCTAssertEqual(responseEvent?.data?[IdentityConstants.EventDataKeys.URL_VARIABLES] as? String, "")
    }

    /// Tests that when identity receives an edge identity request identity event with urlVariables flag set and missing configuration shared state will dispatch a response event with empty url variables string
    func testEdgeIdentityRequestIdentifiersGetUrlVariablesWithoutConfigurationSharedState() {
        // setup
        let getUrlVariablesEvent = Event(name: "Test Request Identifiers",
                                         type: EventType.edgeIdentity,
                                         source: EventSource.requestIdentity,
                                         data: [IdentityConstants.EventDataKeys.URL_VARIABLES: true])

        // test
        mockRuntime.simulateComingEvent(event: getUrlVariablesEvent)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == getUrlVariablesEvent.id })
        XCTAssertEqual(responseEvent?.data?[IdentityConstants.EventDataKeys.URL_VARIABLES] as? String, "")
    }

    // MARK: handleRequestContent
    /// Tests that when identity receives a generic identity request content event with an advertising ID, that the ID is updated
    func testGenericIdentityRequestWithAdIdWithValidId() {
        // setup
        identity.state.identityProperties.advertisingIdentifier = "AdID"
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "newAdId"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("newAdId", identity.state.identityProperties.advertisingIdentifier)
    }
    /// Tests that when identity receives a generic identity request content event **without** an advertising ID, that the ID is updated
    func testGenericIdentityRequestWithAdIdWithoutValidId() {
        // setup
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "newAdId"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("newAdId", identity.state.identityProperties.advertisingIdentifier)
    }

    /// Tests that when identity receives a generic identity request content event with a `nil` advertising ID, that the ID is not changed
    func testGenericIdentityRequestWithNilAdIdWithValidId() {
        // setup
        identity.state.identityProperties.advertisingIdentifier = "AdID"
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: String?.none as Any] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identity.state.identityProperties.advertisingIdentifier)
    }

    /// Tests that when identity receives a generic identity request content event **without** an advertising ID, that the ID is not changed
    func testGenericIdentityRequestWithoutAdIdWithValidId() {
        // setup
        identity.state.identityProperties.advertisingIdentifier = "AdID"
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: ["someKey": "someValue"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("AdID", identity.state.identityProperties.advertisingIdentifier)
    }

    /// Tests that when identity receives a generic identity request content event **without** an advertising ID, that the ID is not changed
    func testGenericIdentityRequestWithoutAdIdWithoutValidId() {
        // setup
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: ["someKey": "someValue"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)
    }

    // MARK: handleUpdateIdentity

    /// Tests when Identity receives an update identity event with valid data the customer identifiers are updated
    func testIdentityUpdateIdentityWithValidData() {
        // setup
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")

        let event = Event(name: "Test Update Identity",
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: identityMap.asDictionary())
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identity.state.identityProperties.identityMap)
        XCTAssertEqual("id", identity.state.identityProperties.identityMap.getItems(withNamespace: "customer")?[0].id)
    }

    /// Tests when Identity receives an update identity event without valid data the customer identifiers are not updated
    func testIdentityUpdateIdentityWithNilData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticatedState: .authenticated, primary: true), withNamespace: "customer")
        identity.state.identityProperties.updateCustomerIdentifiers(defaultIdentities)

        // setup
        let event = Event(name: "Test Update Identity",
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identity.state.identityProperties.identityMap)
        XCTAssertEqual("id", identity.state.identityProperties.identityMap.getItems(withNamespace: "customer")?[0].id)
    }

    // MARK: handleRemoveIdentity

    /// Tests when Identity receives a remove identity event with valid data the customer identifiers are removed
    func testIdentityRemoveIdentityWithValidData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticatedState: .authenticated, primary: true), withNamespace: "customer")
        identity.state.identityProperties.updateCustomerIdentifiers(defaultIdentities)
        // verify setup
        XCTAssertNotNil(identity.state.identityProperties.identityMap)
        XCTAssertEqual("id", identity.state.identityProperties.identityMap.getItems(withNamespace: "customer")?[0].id)

        // setup
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")

        let event = Event(name: "Test Remove Identity",
                          type: EventType.edgeIdentity,
                          source: EventSource.removeIdentity,
                          data: identityMap.asDictionary())
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identity.state.identityProperties.identityMap)
        XCTAssertNil(identity.state.identityProperties.identityMap.getItems(withNamespace: "customer"))
    }

    /// Tests when Identity receives a remove identity event without valid data the customer identifiers are not modified
    func testIdentityRemoveIdentityWithNilData() {
        // set default identities
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticatedState: .authenticated, primary: true), withNamespace: "customer")
        identity.state.identityProperties.updateCustomerIdentifiers(defaultIdentities)
        // verify setup
        XCTAssertNotNil(identity.state.identityProperties.identityMap)
        XCTAssertEqual("id", identity.state.identityProperties.identityMap.getItems(withNamespace: "customer")?[0].id)

        // setup
        let event = Event(name: "Test Remove Identity",
                          type: EventType.edgeIdentity,
                          source: EventSource.removeIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify data is the same
        XCTAssertNotNil(identity.state.identityProperties.identityMap)
        XCTAssertEqual("id", identity.state.identityProperties.identityMap.getItems(withNamespace: "customer")?[0].id)
    }

    // MARK: handleRequestReset

    /// Tests when Identity receives a request reset event that identifiers are cleared and ECID is regenerated
    func testIdentityRequestReset() {
        // setup
        let originalEcid = ECID()
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")
        identity.state.identityProperties.updateCustomerIdentifiers(identityMap)
        identity.state.identityProperties.advertisingIdentifier = "adid"
        identity.state.identityProperties.ecid = originalEcid.ecidString

        let event = Event(name: "Test Request Event",
                          type: EventType.genericIdentity,
                          source: EventSource.requestReset,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state.identityProperties.identityMap.getItems(withNamespace: "customer"))
        XCTAssertNil(identity.state.identityProperties.advertisingIdentifier)
        XCTAssertNotNil(identity.state.identityProperties.ecid)
        XCTAssertNotEqual(originalEcid.ecidString, identity.state.identityProperties.ecid)
    }

    // MARK: handleHubSharedState

    func testHandleHubSharedStateSetsLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityConstants.EventDataKeys.STATE_OWNER: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME,
                                        event: event,
                                        data: ([IdentityConstants.SharedState.IdentityDirect.VISITOR_ID_ECID: "legacyEcidValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("legacyEcidValue", identity.state.identityProperties.ecidSecondary)
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
        identity.state.identityProperties.ecidSecondary = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityConstants.EventDataKeys.STATE_OWNER: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME,
                                        event: event,
                                        data: (["somekey": "someValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state.identityProperties.ecidSecondary)
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
        identity.state.identityProperties.ecidSecondary = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityConstants.EventDataKeys.STATE_OWNER: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME,
                                        event: event,
                                        data: ([IdentityConstants.SharedState.IdentityDirect.VISITOR_ID_ECID: "currentLegacyEcid"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identity.state.identityProperties.ecidSecondary) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }

    func testHandleHubSharedStateWhenNoSharedStateDoesNotUpdateLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        identity.state.identityProperties.ecidSecondary = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityConstants.EventDataKeys.STATE_OWNER: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME])

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identity.state.identityProperties.ecidSecondary) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }

    func testHandleHubSharedStateWhenIncorrectStateownerDoesNotUpdateLegacyEcid() {
        mockRuntime.createdXdmSharedStates = [] // clear shared state from boot
        identity.state.identityProperties.ecidSecondary = "currentLegacyEcid"

        let event = Event(name: "Test Identity State Change",
                          type: EventType.hub,
                          source: EventSource.sharedState,
                          data: [IdentityConstants.EventDataKeys.STATE_OWNER: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME,
                                        event: event,
                                        data: ([IdentityConstants.SharedState.IdentityDirect.VISITOR_ID_ECID: "legacyEcidValue"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("currentLegacyEcid", identity.state.identityProperties.ecidSecondary) // no change
        XCTAssertEqual(0, mockRuntime.createdXdmSharedStates.count) // shared state not created
    }
}
