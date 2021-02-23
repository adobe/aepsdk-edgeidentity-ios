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

import AEPCore
@testable import AEPIdentityEdge
import AEPServices
import XCTest

class IdentityEdgeStateTests: XCTestCase {
    var state: IdentityEdgeState!

    var mockDataStore: MockDataStore {
        return ServiceProvider.shared.namedKeyValueService as! MockDataStore
    }

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        state = IdentityEdgeState(identityEdgeProperties: IdentityEdgeProperties())
    }

    // MARK: bootupIfReady(...) tests

    /// Tests that the default privacy status is set
    func testBootupIfReadyEmptyConfigSharedState() {
        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityEdgeProperties.privacyStatus)
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithOptInPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityEdgeProperties.privacyStatus) // privacy status should have been updated
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithOptOutPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue] as [String: Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityEdgeProperties.privacyStatus) // privacy status should have been updated
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithUnknownPrivacyReturnsFalse() {
        // setup
        let configSharedState = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown.rawValue] as [String: Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityEdgeProperties.privacyStatus) // privacy status should have been updated
    }

    /// Test that bootup loads properties from persistence
    func testBootupIfReadyLoadsFromPersistence() {
        // setup
        var properties = IdentityEdgeProperties()
        properties.ecid = ECID()
        properties.saveToPersistence() // save to shared data store

        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeIdentityEvent())

        //verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityEdgeProperties.ecid)
        XCTAssertEqual(properties.ecid?.ecidString, state.identityEdgeProperties.ecid?.ecidString)
    }

    // MARK: processPrivacyChange(...)

    /// Tests that when the event data is empty update to unknown
    func testProcessPrivacyChangeNoPrivacyInEventData() {
        // setup
        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event(name: "Test event", type: EventType.identityEdge, source: EventSource.requestIdentity, data: nil)

        // test
        state.processPrivacyChange(event: event,
                                   createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertEqual(PrivacyStatus.unknown, state.identityEdgeProperties.privacyStatus) // privacy status set to unknown
    }

    /// Tests that when we get an opt-in privacy status that we update the privacy status
    func testProcessPrivacyChangeToOptIn() {
        // setup
        var props = IdentityEdgeProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityEdgeProperties.privacyStatus) // privacy status should change to opt in
    }

    /// Tests that when we update privacy to opt-out
    func testProcessPrivacyChangeToOptOut() {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityEdgeProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"
        props.customerIdentifiers = IdentityMap()

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        // verify
        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityEdgeProperties.privacyStatus) // privacy status should change to opt out
        XCTAssertNil(state.identityEdgeProperties.ecid) // ecid is cleared
        XCTAssertNil(state.identityEdgeProperties.advertisingIdentifier) // ad id is cleared
        XCTAssertNil(state.identityEdgeProperties.customerIdentifiers) // customer identifiers are cleared
    }

    /// Tests that when we got from opt out to opt in
    func testProcessPrivacyChangeFromOptOutToOptIn() {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedOut

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        // verify
        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityEdgeProperties.privacyStatus) // privacy status should change to opt in
        XCTAssertNotNil(state.identityEdgeProperties.ecid) // ecid is set
    }

    /// When we go from opt-out to unknown
    func testProcessPrivacyChangeFromOptOutToUnknown() {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedOut

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        // verify
        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.unknown, state.identityEdgeProperties.privacyStatus) // privacy status should change to opt in
        XCTAssertNotNil(state.identityEdgeProperties.ecid) // ecid is set
    }

    /// When privacy status is the same, no updates
    func testProcessPrivacyChangeToSame() {
        // setup
        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"
        props.customerIdentifiers = IdentityMap()

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityEdgeProperties.privacyStatus) // privacy status should stay at optin
        XCTAssertNotNil(state.identityEdgeProperties.ecid)
        XCTAssertEqual(props.ecid?.ecidString, state.identityEdgeProperties.ecid?.ecidString)
        XCTAssertEqual(props.advertisingIdentifier, state.identityEdgeProperties.advertisingIdentifier)
        XCTAssertNotNil(state.identityEdgeProperties.customerIdentifiers)
    }

    // MARK: updateCustomerIdentifiers(...)

    func testUpdateCustomerIdentifiers() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityEdgeState(identityEdgeProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(2, state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersFiltersOutUnallowedNamespaces() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityEdgeState(identityEdgeProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "ecid"), withNamespace: IdentityEdgeConstants.Namespaces.ECID)
        customerIdentities.add(item: IdentityItem(id: "idfa"), withNamespace: IdentityEdgeConstants.Namespaces.IDFA)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(2, state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersNoCurrentIdentifiers() {
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = nil

        state = IdentityEdgeState(identityEdgeProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("custom", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    func testUpdateCustomerIdentifiersNoEventDataDoesNotUpdateState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityEdgeState(identityEdgeProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)

        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual(1, state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    // MARK: removeCustomerIdentifiers(...)

    func testRemoveCustomerIdentifiers() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        currentIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityEdgeState(identityEdgeProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveCustomerIdentifiersNoCurrentIdentifiers() {
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = nil

        state = IdentityEdgeState(identityEdgeProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertNil(state.identityEdgeProperties.customerIdentifiers)
    }

    func testRemoveCustomerIdentifiersNoEventDataDoesNotUpdateState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityEdgeProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityEdgeState(identityEdgeProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)

        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual(1, state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityEdgeProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    // MARK: updateAdvertisingIdentifier(...)

    /// Test ad ID is updated from nil to valid value on first call, and consent true is dispatched
    func testUpdateAdvertisingIdentifierUpdatesNilWithValidId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID is updated from nil to empty on first call, and consent false is dispatched
    func testUpdateAdvertisingIdentifierUpdatesNilWithEmptyId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updated from nil to empty on first call when all zeros is passed, and consent false is dispatched
    func testUpdateAdvertisingIdentifierUpdatesNilWithZeros() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updated from empty to valid value and consent true is dispatched
    func testUpdateAdvertisingIdentifierUpdatesEmptyWithValidId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "", newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID call is ignored when old and new values are empty
    func testUpdateAdvertisingIdentifierDoesNotUpdatesEmptyWithEmpty() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: "", expectedAdId: "")
    }

    /// Test ad ID call is ignored when old and new values are empty; passing all zeros is converted to empty string
    func testUpdateAdvertisingIdentifierDoesNotUpdatesEmptyWithEZeros() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "")
    }

    /// Test ad ID is updated from old value to new value, and no consent event is dispatched
    func testUpdateAdvertisingIdentifierUpdatesValidWithNewValidId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: "oldAdId", newAdId: "adId", expectedAdId: "adId")
    }

    /// Test ad ID is not updated when old and new values are the same
    func testUpdateAdvertisingIdentifierDoesNotUpdatesValidWithSameValidId() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "adId", newAdId: "adId", expectedAdId: "adId")
    }

    /// Test ad ID is updated from valid value to empty string and consent false is dispatched
    func testUpdateAdvertisingIdentifierUpdatesValidWithEmptyId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from valid value to empty string when all zeros is passed, and consent false is dispatched
    func testUpdateAdvertisingIdentifierUpdatesValidWithZeros() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from all zeros to valid value and consent true is dispatched
    func testUpdateAdvertisingIdentifierUpdatesZerosWithValidId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID is updated from all zeros to empty string and consent false is dispatched
    func testUpdateAdvertisingIdentifierUpdatesZerosWithEmptyId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updated from all zeros to empty string and consent false is dispatched; passing all zeros is converted to empty string
    func testUpdateAdvertisingIdentifierUpdatesZerosWithZeros() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, newAdId: IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID call is ignored if passing nil
    func testUpdateAdvertisingIdentifierPassingNilIsIgnored() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "oldAdId", newAdId: nil, expectedAdId: "oldAdId")
    }

    /// Tests that ad ID call is ignored when privacy is opted out
    func testUpdateAdvertisingIdentifierIgnoresWhenPrivacyOptedOut() {
        // setup
        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedOut
        props.ecid = ECID()
        props.advertisingIdentifier = "oldAdId"

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: "adId")

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual("oldAdId", state.identityEdgeProperties.advertisingIdentifier) // no change
    }

    private func assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?, expectedConsent: String?) {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        let consentExpectation = XCTestExpectation(description: "Consent event should be dispatched once")

        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        var consentEvent: Event?
        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          dispatchEvent: { event in
                                            consentEvent = event
                                            consentExpectation.fulfill()
                                          })

        // verify
        wait(for: [xdmSharedStateExpectation, consentExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityEdgeProperties.advertisingIdentifier)

        XCTAssertNotNil(consentEvent)
        XCTAssertEqual(expectedConsent, ((consentEvent?.data?["consents"] as? [String: Any])?["adId"] as? [String: Any])?["val"] as? String)
    }

    private func assertUpdateAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")

        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        wait(for: [xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityEdgeProperties.advertisingIdentifier)
    }

    private func assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        var props = IdentityEdgeProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityEdgeState(identityEdgeProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity edge properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityEdgeProperties.advertisingIdentifier)
    }

}

private extension Event {
    static func fakeIdentityEvent() -> Event {
        return Event(name: "Fake Identity Event", type: EventType.identityEdge, source: EventSource.requestContent, data: nil)
    }

    static func fakeGenericIdentityEvent(adId: String?) -> Event {
        return Event(name: "Test Event",
                     type: EventType.genericIdentity,
                     source: EventSource.requestIdentity,
                     data: [IdentityEdgeConstants.EventDataKeys.ADVERTISING_IDENTIFIER: adId as Any])
    }
}