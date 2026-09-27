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

/// Functional tests for the consent-independent device-attribute path (`updateDeviceAttributesBypassConsent`) handled
/// by `Identity.handleDeviceAttributes`.
class IdentityDeviceAttributesTests: XCTestCase {
    var identity: Identity!
    var mockRuntime: TestableExtensionRuntime!
    // Collection-aware so the separate profile/device store namespaces are honored (the shared
    // MockDataStore is flat and would incorrectly cross-suppress identical values).
    var mockDataStore: CollectionAwareMockDataStore!

    private let tzKey = TimeZoneAttributeHandler.key
    private let pushKey = PushTokenAttributeHandler.key
    private let deviceStore = IdentityConstants.Store.DEVICE_ATTRIBUTES
    private let profileStore = IdentityConstants.Store.PROFILE_ATTRIBUTES

    override func setUp() {
        continueAfterFailure = false
        mockDataStore = CollectionAwareMockDataStore()
        ServiceProvider.shared.namedKeyValueService = mockDataStore
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
        let bootEvent = Event(name: "boot", type: "test-type", source: "test-source", data: nil)
        XCTAssertTrue(identity.readyForEvent(bootEvent))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()
        // Deterministic start: both dedup stores empty (no reliance on device timezone / prior runs).
        clearBothStores()
    }

    override func tearDown() {
        clearBothStores()
        super.tearDown()
    }

    private func clearBothStores() {
        for store in [profileStore, deviceStore] {
            for key in [tzKey, pushKey] {
                mockDataStore.remove(collectionName: store, key: key)
            }
        }
    }

    // MARK: - Helpers

    private func makeDeviceEvent(timezone: String? = nil, pushToken: String? = nil) -> Event {
        var data: [String: Any] = [:]
        if let timezone = timezone { data[tzKey] = timezone }
        if let pushToken = pushToken { data[pushKey] = pushToken }
        return Event(name: IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES,
                     type: EventType.edgeIdentity,
                     source: EventSource.requestContent,
                     data: data)
    }

    private func makeProfileEvent(timezone: String) -> Event {
        return Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                     type: EventType.genericProfileAttributes,
                     source: EventSource.requestContent,
                     data: [tzKey: timezone])
    }

    private func simulateConfig(_ config: [String: Any], for event: Event) {
        mockRuntime.simulateSharedState(for: (IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event),
                                        data: (config, .set))
    }

    /// Operational-data events dispatched by the device path.
    private func operationalEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.type == IdentityConstants.DeviceAttributes.OPERATIONAL_DATA_TYPE }
    }

    private func edgeEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.type == EventType.edge }
    }

    // Reads the raw persisted value for a given store namespace + key (each store is independent).
    private func rawStored(store: String, key: String) -> String? {
        return mockDataStore.get(collectionName: store, key: key) as? String
    }

    // MARK: - Payload

    func testDeviceAttributes_timezoneOnly_dispatchesOperationalEventWithTimezone_noApp() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "America/Los_Angeles"))

        let events = operationalEvents()
        XCTAssertEqual(1, events.count)
        let payload = events[0].data
        XCTAssertEqual("America/Los_Angeles", payload?[IdentityConstants.DeviceAttributes.TIMEZONE] as? String)
        // No push token -> no app context.
        XCTAssertNil(payload?[IdentityConstants.DeviceAttributes.APP])
        XCTAssertNil(payload?[IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION])
    }

    func testDeviceAttributes_pushToken_dispatchesOperationalEventWithPushNotificationAndApp() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(pushToken: "push-token-123"))

        let events = operationalEvents()
        XCTAssertEqual(1, events.count)
        let payload = events[0].data
        XCTAssertEqual("push-token-123", payload?[IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION] as? String)

        // App context (bundle id + platform) is added only when a push identifier is present, and only
        // when the host bundle identifier is resolvable.
        if Bundle.main.bundleIdentifier != nil {
            let app = payload?[IdentityConstants.DeviceAttributes.APP] as? [String: Any]
            XCTAssertNotNil(app)
            XCTAssertNotNil(app?[IdentityConstants.DeviceAttributes.APP_ID])
            XCTAssertNotNil(app?[IdentityConstants.DeviceAttributes.APP_PLATFORM])
        }
    }

    func testDeviceAttributes_pushToken_defaultsToProductionApnsPlatform() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        mockRuntime.simulateComingEvents(makeDeviceEvent(pushToken: "push-token-123"))

        let app = operationalEvents()[0].data?[IdentityConstants.DeviceAttributes.APP] as? [String: Any]
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS,
                       app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_pushToken_useSandboxTrue_usesSandboxApnsPlatform() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let event = makeDeviceEvent(pushToken: "push-token-123")
        simulateConfig([IdentityConstants.DeviceAttributes.MESSAGING_USE_SANDBOX: true], for: event)

        mockRuntime.simulateComingEvents(event)

        let app = operationalEvents()[0].data?[IdentityConstants.DeviceAttributes.APP] as? [String: Any]
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS_SANDBOX,
                       app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_bothAttributes_collatesIntoSinglePayload() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Asia/Kolkata", pushToken: "push-token-123"))

        let events = operationalEvents()
        XCTAssertEqual(1, events.count)
        let payload = events[0].data
        XCTAssertEqual("Asia/Kolkata", payload?[IdentityConstants.DeviceAttributes.TIMEZONE] as? String)
        XCTAssertEqual("push-token-123", payload?[IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION] as? String)
    }

    // MARK: - Dedup (default true)

    func testDeviceAttributes_allUnchanged_dispatchesNothing() {
        mockDataStore.set(collectionName: deviceStore, key: tzKey, value: "America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "America/Los_Angeles"))

        XCTAssertTrue(operationalEvents().isEmpty)
    }

    func testDeviceAttributes_repeatedIdentical_onlyFirstDispatches_default() {
        let event = makeDeviceEvent(timezone: "Europe/London")
        mockRuntime.simulateComingEvents(event)
        XCTAssertEqual(1, operationalEvents().count)

        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Europe/London"))
        // Still only the first dispatch — dedup default suppresses the identical repeat.
        XCTAssertEqual(1, operationalEvents().count)
    }

    func testDeviceAttributes_persistsToDeviceStore() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Pacific/Auckland", pushToken: "push-token-123"))

        XCTAssertEqual("Pacific/Auckland", mockDataStore.get(collectionName: deviceStore, key: tzKey) as? String)
        XCTAssertEqual("push-token-123", mockDataStore.get(collectionName: deviceStore, key: pushKey) as? String)
    }

    // MARK: - Dedup config flag

    func testDeviceAttributes_dedupFalse_repeatedIdentical_alwaysDispatches() {
        let first = makeDeviceEvent(timezone: "Europe/London")
        simulateConfig([IdentityConstants.ConfigKeys.DEVICE_ATTRIBUTES_DEDUP: false], for: first)
        mockRuntime.simulateComingEvents(first)

        let second = makeDeviceEvent(timezone: "Europe/London")
        simulateConfig([IdentityConstants.ConfigKeys.DEVICE_ATTRIBUTES_DEDUP: false], for: second)
        mockRuntime.simulateComingEvents(second)

        XCTAssertEqual(2, operationalEvents().count)
    }

    func testDeviceAttributes_dedupTrueExplicit_repeatedIdentical_skipsSecond() {
        let first = makeDeviceEvent(timezone: "Europe/London")
        simulateConfig([IdentityConstants.ConfigKeys.DEVICE_ATTRIBUTES_DEDUP: true], for: first)
        mockRuntime.simulateComingEvents(first)

        let second = makeDeviceEvent(timezone: "Europe/London")
        simulateConfig([IdentityConstants.ConfigKeys.DEVICE_ATTRIBUTES_DEDUP: true], for: second)
        mockRuntime.simulateComingEvents(second)

        XCTAssertEqual(1, operationalEvents().count)
    }

    // MARK: - CLASH: separate stores between profile and device paths

    func testProfileAndDevicePaths_sameTimezone_bothDispatchIndependently() {
        // Profile path (consent-gated) with timezone X.
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Asia/Kolkata"))
        // Device path (consent-independent) with the SAME timezone X.
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Asia/Kolkata"))

        // With separate stores, the identical value does not cross-suppress: both paths emit.
        XCTAssertEqual(1, edgeEvents().count, "Profile path should dispatch its Edge event")
        XCTAssertEqual(1, operationalEvents().count, "Device path should dispatch its operational-data event")

        // Each path persisted to its own store.
        XCTAssertEqual("Asia/Kolkata", mockDataStore.get(collectionName: profileStore, key: tzKey) as? String)
        XCTAssertEqual("Asia/Kolkata", mockDataStore.get(collectionName: deviceStore, key: tzKey) as? String)
    }

    func testDeviceThenProfile_sameTimezone_bothDispatch() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Europe/London"))
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Europe/London"))

        XCTAssertEqual(1, operationalEvents().count)
        XCTAssertEqual(1, edgeEvents().count)
    }

    // MARK: - Empty / invalid

    func testDeviceAttributes_emptyEventData_dispatchesNothing() {
        let event = Event(name: IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestContent,
                          data: [:])

        mockRuntime.simulateComingEvents(event)

        XCTAssertTrue(operationalEvents().isEmpty)
    }

    func testDeviceAttributes_invalidTimezone_dispatchesNothing_andNotStored() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Not/AReal/Zone"))

        XCTAssertTrue(operationalEvents().isEmpty)
        XCTAssertNil(rawStored(store: deviceStore, key: tzKey))
    }

    // MARK: - Store independence (regression guard)
    //
    // These guard against a copy-paste regression that points both registries at the same store name.
    // If the stores were shared, a profile write would suppress the device path's consent-override
    // dispatch (data loss) — the assertions below would then fail loudly.

    func testStoreNameConstants_areDistinct() {
        XCTAssertNotEqual(IdentityConstants.Store.PROFILE_ATTRIBUTES,
                          IdentityConstants.Store.DEVICE_ATTRIBUTES,
                          "Profile and device dedup stores must be distinct or a profile write would suppress the device dispatch")
    }

    func testProfileWriteFirst_deviceStoreUntouched_andDeviceStillEmits() {
        // Profile path writes timezone X.
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Asia/Kolkata"))
        XCTAssertEqual("Asia/Kolkata", rawStored(store: profileStore, key: tzKey))
        // The DEVICE store must NOT contain the value written by the profile path.
        XCTAssertNil(rawStored(store: deviceStore, key: tzKey), "Profile write must not leak into the device store")

        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        // Firing the device path with the SAME value must still emit (not suppressed by the profile write).
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Asia/Kolkata"))
        XCTAssertEqual(1, operationalEvents().count)
        // Now only the device store holds X too — each store holds it under its own namespace.
        XCTAssertEqual("Asia/Kolkata", rawStored(store: deviceStore, key: tzKey))
        XCTAssertEqual("Asia/Kolkata", rawStored(store: profileStore, key: tzKey))
    }

    func testDeviceWriteFirst_profileStoreUntouched_andProfileStillEmits() {
        // Device path writes timezone X.
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Europe/London"))
        XCTAssertEqual("Europe/London", rawStored(store: deviceStore, key: tzKey))
        // The PROFILE store must NOT contain the value written by the device path.
        XCTAssertNil(rawStored(store: profileStore, key: tzKey), "Device write must not leak into the profile store")

        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        // Firing the profile path with the SAME value must still emit (not suppressed by the device write).
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Europe/London"))
        XCTAssertEqual(1, edgeEvents().count)
        XCTAssertEqual("Europe/London", rawStored(store: profileStore, key: tzKey))
    }

    // MARK: - Robust coverage

    func testDeviceAttributes_changedValue_emits() {
        mockDataStore.set(collectionName: deviceStore, key: tzKey, value: "America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Asia/Kolkata"))

        XCTAssertEqual(1, operationalEvents().count)
        XCTAssertEqual("Asia/Kolkata", operationalEvents()[0].data?[IdentityConstants.DeviceAttributes.TIMEZONE] as? String)
    }

    func testDeviceAttributes_multipleAttributes_onlyChangedIncludedInPayload() {
        // Timezone already synced (unchanged); push token is new (changed).
        mockDataStore.set(collectionName: deviceStore, key: tzKey, value: "America/Los_Angeles")

        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "America/Los_Angeles", pushToken: "push-token-123"))

        let payload = operationalEvents()[0].data
        XCTAssertEqual(1, operationalEvents().count)
        // Only the changed attribute (push) is present; the unchanged timezone is omitted.
        XCTAssertNil(payload?[IdentityConstants.DeviceAttributes.TIMEZONE])
        XCTAssertEqual("push-token-123", payload?[IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION] as? String)
    }

    // Payload uses operationalDataKey; storage uses attributeKey.
    func testDeviceAttributes_payloadUsesOperationalKey_storageUsesAttributeKey() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(timezone: "Europe/London", pushToken: "push-token-123"))

        let payload = operationalEvents()[0].data
        // Outgoing payload keyed by operationalDataKey ("timezone" / "pushNotification").
        XCTAssertEqual("Europe/London", payload?[IdentityConstants.DeviceAttributes.TIMEZONE] as? String)
        XCTAssertEqual("push-token-123", payload?[IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION] as? String)
        // Storage keyed by attributeKey ("timeZone" / "pushidentifier").
        XCTAssertEqual("Europe/London", rawStored(store: deviceStore, key: tzKey))
        XCTAssertEqual("push-token-123", rawStored(store: deviceStore, key: pushKey))
    }
}
