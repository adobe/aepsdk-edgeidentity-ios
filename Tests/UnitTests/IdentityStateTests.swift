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

class IdentityStateTests: XCTestCase {
    var state: IdentityState!

    var mockDataStore: MockDataStore {
        return ServiceProvider.shared.namedKeyValueService as! MockDataStore
    }

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        state = IdentityState(identityProperties: IdentityProperties())
    }

    // MARK: bootupIfReady(...) tests

    /// Tests bootup generates ECID
    func testBootupIfReadyGeneratesECID() {
        XCTAssertNil(state.identityProperties.ecid)

        // test
        let result = state.bootupIfReady()

        // verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid?.ecidString)
    }

    /// Tests bootup does not generates ECID if already exists
    func testBootupIfReadyDoesNotGeneratesECIDIfSet() {
        let ecid = ECID()
        state.identityProperties.ecid = ecid

        // test
        let result = state.bootupIfReady()

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(ecid.ecidString, state.identityProperties.ecid?.ecidString)
    }

    /// Test that bootup loads properties from persistence
    func testBootupIfReadyLoadsFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.saveToPersistence() // save to shared data store

        // test
        let result = state.bootupIfReady()

        //verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(properties.ecid?.ecidString, state.identityProperties.ecid?.ecidString)
    }

    // MARK: updateCustomerIdentifiers(...)

    func testUpdateCustomerIdentifiers() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityState(identityProperties: props)

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
        XCTAssertEqual(2, state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersFiltersOutUnallowedNamespaces() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "ecid"), withNamespace: IdentityConstants.Namespaces.ECID)
        customerIdentities.add(item: IdentityItem(id: "idfa"), withNamespace: IdentityConstants.Namespaces.IDFA)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(2, state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersNoCurrentIdentifiers() {
        var props = IdentityProperties()
        props.customerIdentifiers = nil

        state = IdentityState(identityProperties: props)

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
        XCTAssertEqual(1, state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("custom", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    func testUpdateCustomerIdentifiersNoEventDataDoesNotUpdateState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)

        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    // MARK: removeCustomerIdentifiers(...)

    func testRemoveCustomerIdentifiers() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        currentIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        var props = IdentityProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityState(identityProperties: props)

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
        XCTAssertEqual(1, state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveCustomerIdentifiersNoCurrentIdentifiers() {
        var props = IdentityProperties()
        props.customerIdentifiers = nil

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertNil(state.identityProperties.customerIdentifiers)
    }

    func testRemoveCustomerIdentifiersNoEventDataDoesNotUpdateState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.customerIdentifiers = currentIdentities

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)

        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.customerIdentifiers?.getItems(withNamespace: "space")?[0].id)
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
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
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
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "")
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
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from all zeros to valid value and consent true is dispatched
    func testUpdateAdvertisingIdentifierUpdatesZerosWithValidId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID is updated from all zeros to empty string and consent false is dispatched
    func testUpdateAdvertisingIdentifierUpdatesZerosWithEmptyId() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from all zeros to empty string and consent false is dispatched; passing all zeros is converted to empty string
    func testUpdateAdvertisingIdentifierUpdatesZerosWithZeros() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID call is ignored if passing nil
    func testUpdateAdvertisingIdentifierPassingNilIsIgnored() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "oldAdId", newAdId: nil, expectedAdId: "oldAdId")
    }

    private func assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?, expectedConsent: String?) {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        let consentExpectation = XCTestExpectation(description: "Consent event should be dispatched once")

        var props = IdentityProperties()
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
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
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)

        XCTAssertNotNil(consentEvent)
        XCTAssertEqual(expectedConsent, ((consentEvent?.data?["consents"] as? [String: Any])?["adId"] as? [String: Any])?["val"] as? String)
    }

    private func assertUpdateAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")

        var props = IdentityProperties()
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        wait(for: [xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)
    }

    private func assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        var props = IdentityProperties()
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)
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
                     data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: adId as Any])
    }
}
