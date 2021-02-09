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

    /// Tests that the default privacy status is set
    func testBootupIfReadyEmptyConfigSharedState() {
        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus)
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithOptInPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should have been updated
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithOptOutPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue] as [String: Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityProperties.privacyStatus) // privacy status should have been updated
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithUnknownPrivacyReturnsFalse() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown.rawValue] as [String: Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should have been updated
    }

    /// Test that bootup loads properties from persistence
    func testBootupIfReadyLoadsFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.saveToPersistence() // save to shared data store

        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeIdentityEvent())

        //verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(properties.ecid?.ecidString, state.identityProperties.ecid?.ecidString)
    }

    // MARK: processPrivacyChange(...)

    /// Tests that when the event data is empty update to unknown
    func testProcessPrivacyChangeNoPrivacyInEventData() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: nil)

        // test
        state.processPrivacyChange(event: event,
                                   createSharedState: { _, _ in XCTFail("Shared state should not be updated") },
                                   createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status set to unknown
    }

    /// Tests that when we get an opt-in privacy status that we update the privacy status
    func testProcessPrivacyChangeToOptIn() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identity,
                          source: EventSource.requestIdentity,
                          data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createSharedState: { _, _ in XCTFail("Shared state should not be updated") },
                                   createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should change to opt in
    }

    /// Tests that when we update privacy to opt-out
    func testProcessPrivacyChangeToOptOut() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"
        props.pushIdentifier = "push-id"
        props.customerIds = [CustomIdentity.init(origin: "origin", type: "type", identifier: "id", authenticationState: .authenticated)]

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identity,
                          source: EventSource.requestIdentity,
                          data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createSharedState: { _, _ in sharedStateExpectation.fulfill() },
                                   createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityProperties.privacyStatus) // privacy status should change to opt out
        XCTAssertNil(state.identityProperties.ecid) // ecid is cleared
        XCTAssertNil(state.identityProperties.advertisingIdentifier) // ad id is cleared
        XCTAssertNil(state.identityProperties.pushIdentifier) // push id is cleared
        XCTAssertEqual(true, state.identityProperties.customerIds?.isEmpty) // customer ids is cleared
    }

    /// Tests that when we got from opt out to opt in
    func testProcessPrivacyChangeFromOptOutToOptIn() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identity,
                          source: EventSource.requestIdentity,
                          data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createSharedState: { _, _ in sharedStateExpectation.fulfill() },
                                   createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should change to opt in
        XCTAssertNotNil(state.identityProperties.ecid) // ecid is set
    }

    /// When we go from opt-out to unknown
    func testProcessPrivacyChangeFromOptOutToUnknown() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identity,
                          source: EventSource.requestIdentity,
                          data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createSharedState: { _, _ in sharedStateExpectation.fulfill() },
                                   createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should change to opt in
        XCTAssertNotNil(state.identityProperties.ecid) // ecid is set
    }

    /// When privacy status is the same, no updates
    func testProcessPrivacyChangeToSame() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = "adId"

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event",
                          type: EventType.identity,
                          source: EventSource.requestIdentity,
                          data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event,
                                   createSharedState: { _, _ in XCTFail("Shared state should not be updated") },
                                   createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should stay at optin
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(props.ecid?.ecidString, state.identityProperties.ecid?.ecidString)
        XCTAssertEqual(props.advertisingIdentifier, state.identityProperties.advertisingIdentifier)
    }

    // MARK: syncAdvertisingIdentifier(...)

    /// Test ad ID is updated from nil to valid value on first call, and consent true is dispatched
    func testSyncAdvertisingIdentifierUpdatesNilWithValidId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID is updated from nil to empty on first call, and consent false is dispatched
    func testSyncAdvertisingIdentifierUpdatesNilWithEmptyId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updated from nil to empty on first call when all zeros is passed, and consent false is dispatched
    func testSyncAdvertisingIdentifierUpdatesNilWithZeros() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updated from empty to valid value and consent true is dispatched
    func testSyncAdvertisingIdentifierUpdatesEmptyWithValidId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "", newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID call is ignored when old and new values are empty
    func testSyncAdvertisingIdentifierDoesNotUpdatesEmptyWithEmpty() {
        assertSyncAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: "", expectedAdId: "")
    }

    /// Test ad ID call is ignored when old and new values are empty; passing all zeros is converted to empty string
    func testSyncAdvertisingIdentifierDoesNotUpdatesEmptyWithEZeros() {
        assertSyncAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "")
    }

    /// Test ad ID is updated from old value to new value, and no consent event is dispatched
    func testSyncAdvertisingIdentifierUpdatesValidWithNewValidId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: "oldAdId", newAdId: "adId", expectedAdId: "adId")
    }

    /// Test ad ID is not updated when old and new values are the same
    func testSyncAdvertisingIdentifierDoesNotUpdatesValidWithSameValidId() {
        assertSyncAdvertisingIdentifierIsNotUpdated(persistedAdId: "adId", newAdId: "adId", expectedAdId: "adId")
    }

    /// Test ad ID is updated from valid value to empty string and consent false is dispatched
    func testSyncAdvertisingIdentifierUpdatesValidWithEmptyId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from valid value to empty string when all zeros is passed, and consent false is dispatched
    func testSyncAdvertisingIdentifierUpdatesValidWithZeros() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from all zeros to valid value and consent true is dispatched
    func testSyncAdvertisingIdentifierUpdatesZerosWithValidId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID is updated from all zeros to empty string and consent false is dispatched
    func testSyncAdvertisingIdentifierUpdatesZerosWithEmptyId() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: "", expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID is updaed from all zeros to empty string and consent false is dispatched; passing all zeros is converted to empty string
    func testSyncAdvertisingIdentifierUpdatesZerosWithZeros() {
        assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: "", expectedConsent: "n")
    }

    /// Test ad ID call is ignored if passing nil
    func testSyncAdvertisingIdentifierPassingNilIsIgnored() {
        assertSyncAdvertisingIdentifierIsNotUpdated(persistedAdId: "oldAdId", newAdId: nil, expectedAdId: "oldAdId")
    }

    /// Tests that ad ID call is ignored when privacy is opted out
    func testSyncAdvertisingIdentifierIgnoresWhenPrivacyOptedOut() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .optedOut
        props.ecid = ECID()
        props.advertisingIdentifier = "oldAdId"

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: "adId")

        state.updateAdvertisingIdentifier(event: event,
                                          createSharedState: { _, _ in XCTFail("Shared state should not be updated") },
                                          createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual("oldAdId", state.identityProperties.advertisingIdentifier) // no change
    }

    private func assertSyncAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?, expectedConsent: String?) {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        let consentExpectation = XCTestExpectation(description: "Consent event should be dispatched once")

        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        var consentEvent: Event?
        state.updateAdvertisingIdentifier(event: event,
                                          createSharedState: { _, _ in sharedStateExpectation.fulfill() },
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          dispatchEvent: { event in
                                            consentEvent = event
                                            consentExpectation.fulfill()
                                          })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation, consentExpectation], timeout: 3)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)

        XCTAssertNotNil(consentEvent)
        XCTAssertEqual(expectedConsent, ((consentEvent?.data?["consents"] as? [String: Any])?["adId"] as? [String: Any])?["val"] as? String)
    }

    private func assertSyncAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")

        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createSharedState: { _, _ in sharedStateExpectation.fulfill() },
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 3)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)
    }

    private func assertSyncAdvertisingIdentifierIsNotUpdated(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createSharedState: { _, _ in XCTFail("Shared state should not be updated") },
                                          createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") },
                                          dispatchEvent: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)
    }

}

private extension Event {
    static func fakeIdentityEvent() -> Event {
        return Event(name: "Fake Identity Event", type: EventType.identity, source: EventSource.requestContent, data: nil)
    }

    static func fakeGenericIdentityEvent(adId: String?) -> Event {
        return Event(name: "Test Event",
                     type: EventType.genericIdentity,
                     source: EventSource.requestIdentity,
                     data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: adId as Any])
    }
}
