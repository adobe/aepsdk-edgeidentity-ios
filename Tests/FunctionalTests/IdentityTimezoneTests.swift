// Copyright 2026 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.

@testable import AEPCore
@testable import AEPEdgeIdentity
import AEPServices
import AEPTestUtils
import XCTest

class IdentityTimezoneTests: XCTestCase, AnyCodableAsserts {
    var identity: Identity!
    var mockRuntime: TestableExtensionRuntime!
    var mockDataStore: MockDataStore!

    override func setUp() {
        continueAfterFailure = false
        mockDataStore = MockDataStore()
        ServiceProvider.shared.namedKeyValueService = mockDataStore
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
        // Trigger bootup so extension is in a ready state
        let bootEvent = Event(name: "boot", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(bootEvent))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()
    }

    // MARK: - Helpers

    private func makeTimezoneEvent(_ timezone: String) -> Event {
        return Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                     type: IdentityConstants.EventTypes.GENERIC_PROFILE_ATTRIBUTES,
                     source: EventSource.requestContent,
                     data: [IdentityConstants.ProfileAttributes.TIMEZONE: timezone])
    }

    private func makeConsentEvent(val: String) -> Event {
        return Event(name: "Test Consent Response",
                     type: EventType.edgeConsent,
                     source: EventSource.responseContent,
                     data: ["consents": ["collect": ["val": val]]])
    }

    private func makeResetEvent() -> Event {
        return Event(name: "Reset Identities",
                     type: EventType.genericIdentity,
                     source: EventSource.requestReset,
                     data: nil)
    }

    private func storeTimezone(_ timezone: String) {
        mockDataStore.set(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME,
                          key: IdentityConstants.ProfileAttributes.TIMEZONE,
                          value: timezone)
    }

    private func storedTimezone() -> String? {
        return mockDataStore.get(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME,
                                 key: IdentityConstants.ProfileAttributes.TIMEZONE) as? String
    }

    private func edgeEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.type == EventType.edge }
    }

    // MARK: - Dedup

    func testTimezoneSync_firstCall_dispatchesEdgeEvent() {
        mockRuntime.simulateComingEvents(makeTimezoneEvent("America/Los_Angeles"))

        XCTAssertEqual(1, edgeEvents().count)
    }

    func testTimezoneSync_sameValue_noEdgeEvent() {
        storeTimezone("America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeTimezoneEvent("America/Los_Angeles"))

        XCTAssertTrue(edgeEvents().isEmpty)
    }

    func testTimezoneSync_differentValue_dispatchesEdgeEvent() {
        storeTimezone("America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeTimezoneEvent("Asia/Kolkata"))

        XCTAssertEqual(1, edgeEvents().count)
    }

    func testTimezoneSync_spam5x_onlyOneEdgeEvent() {
        let event = makeTimezoneEvent("America/New_York")

        mockRuntime.simulateComingEvents(event, event, event, event, event)

        XCTAssertEqual(1, edgeEvents().count)
    }

    // MARK: - Edge event format

    func testTimezoneEdgeEvent_typeIsEdge() {
        mockRuntime.simulateComingEvents(makeTimezoneEvent("Europe/London"))

        XCTAssertEqual(EventType.edge, edgeEvents()[0].type)
    }

    func testTimezoneEdgeEvent_sourceIsRequestContent() {
        mockRuntime.simulateComingEvents(makeTimezoneEvent("Europe/London"))

        XCTAssertEqual(EventSource.requestContent, edgeEvents()[0].source)
    }

    func testTimezoneEdgeEvent_hasCorrectXdmEventType() {
        mockRuntime.simulateComingEvents(makeTimezoneEvent("Europe/London"))

        let xdm = edgeEvents()[0].data?[IdentityConstants.ProfileAttributes.XDM.XDM_KEY] as? [String: Any]
        XCTAssertEqual(IdentityConstants.ProfileAttributes.XDM.PROFILE_UPDATE_EVENT_TYPE,
                       xdm?[IdentityConstants.ProfileAttributes.XDM.EVENT_TYPE_KEY] as? String)
    }

    func testTimezoneEdgeEvent_hasCorrectDataTimeZone() {
        mockRuntime.simulateComingEvents(makeTimezoneEvent("Europe/London"))

        let data = edgeEvents()[0].data?[IdentityConstants.ProfileAttributes.XDM.DATA_KEY] as? [String: Any]
        XCTAssertEqual("Europe/London",
                       data?[IdentityConstants.ProfileAttributes.XDM.TIMEZONE_DATA_KEY] as? String)
    }

    func testTimezoneEdgeEvent_storesTimezone() {
        mockRuntime.simulateComingEvents(makeTimezoneEvent("Pacific/Auckland"))

        XCTAssertEqual("Pacific/Auckland", storedTimezone())
    }

    // MARK: - Consent

    func testConsentNoToYes_reSyncsStoredValue() {
        storeTimezone("America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeConsentEvent(val: "y"))

        // Store retains the value (no clear, direct write)
        XCTAssertEqual("America/Los_Angeles", storedTimezone())
        // Edge event dispatched directly — not a genericProfileAttributes round trip
        XCTAssertEqual(1, edgeEvents().count)
        let data = edgeEvents()[0].data?[IdentityConstants.ProfileAttributes.XDM.DATA_KEY] as? [String: Any]
        XCTAssertEqual("America/Los_Angeles",
                       data?[IdentityConstants.ProfileAttributes.XDM.TIMEZONE_DATA_KEY] as? String)
    }

    func testConsentNoToYes_noStoredValue_noEdgeEvent() {
        // user never called updateProfileAttributes — nothing pending
        mockRuntime.simulateComingEvents(makeConsentEvent(val: "y"))

        XCTAssertTrue(edgeEvents().isEmpty)
    }

    func testConsentYesToYes_noReSync() {
        storeTimezone("America/Los_Angeles")
        mockRuntime.simulateComingEvents(makeConsentEvent(val: "y"))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(makeConsentEvent(val: "y"))

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    func testConsentNoToNo_noReSync() {
        mockRuntime.simulateComingEvents(makeConsentEvent(val: "n"))

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    func testConsentYesToNo_noReSync() {
        storeTimezone("America/Los_Angeles")
        mockRuntime.simulateComingEvents(makeConsentEvent(val: "y"))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(makeConsentEvent(val: "n"))

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty)
    }

    // MARK: - Reset

    func testReset_clearsProfileAttributesStore() {
        storeTimezone("America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeResetEvent())

        XCTAssertNil(storedTimezone())
    }

    func testReset_afterReset_nextSyncSendsEdgeEvent() {
        // Store a value so dedup would normally block re-dispatch
        storeTimezone("America/Los_Angeles")
        mockRuntime.simulateComingEvents(makeResetEvent())
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        // After reset, store is cleared — dedup guard passes
        mockRuntime.simulateComingEvents(makeTimezoneEvent("America/Los_Angeles"))

        XCTAssertEqual(1, edgeEvents().count)
    }
}
