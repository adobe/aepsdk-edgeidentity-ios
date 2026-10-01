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
/// by `Identity.handleDeviceAttributes`: open-map pass-through plus key-based dedup.
class IdentityDeviceAttributesTests: XCTestCase {
    var identity: Identity!
    var mockRuntime: TestableExtensionRuntime!
    // Collection-aware so the separate profile/device store namespaces are honored (the shared
    // MockDataStore is flat and would incorrectly cross-suppress identical values).
    var mockDataStore: CollectionAwareMockDataStore!

    private let deviceStore = IdentityConstants.Store.DEVICE_ATTRIBUTES
    private let profileStore = IdentityConstants.Store.PROFILE_ATTRIBUTES
    private let pushKey = "pushNotification"
    private let appKey = IdentityConstants.DeviceAttributes.APP

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
        clearStores()
    }

    override func tearDown() {
        clearStores()
        super.tearDown()
    }

    private func clearStores() {
        mockDataStore.remove(collectionName: deviceStore, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES)
        mockDataStore.remove(collectionName: profileStore, key: TimeZoneAttributeHandler.key)
    }

    // MARK: - Helpers

    private func makeDeviceEvent(_ data: [String: Any]) -> Event {
        return Event(name: IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES,
                     type: EventType.edgeIdentity,
                     source: EventSource.requestContent,
                     data: data)
    }

    private func makeProfileEvent(timezone: String) -> Event {
        return Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                     type: EventType.genericProfileAttributes,
                     source: EventSource.requestContent,
                     data: [TimeZoneAttributeHandler.key: timezone])
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

    private func syncedDeviceValues() -> [String: String] {
        return mockDataStore.get(collectionName: deviceStore, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES) as? [String: String] ?? [:]
    }

    /// Payload keys that came from the caller (excludes the SDK-added `app` entry).
    private func attributeKeys(_ payload: [String: Any]?) -> Set<String> {
        return Set((payload ?? [:]).keys).subtracting([appKey])
    }

    // MARK: - Pass-through

    func testDeviceAttributes_forwardsArbitraryKeysAsIs() {
        let nested: [String: Any] = ["start": "la-start", "count": 2]
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "America/Los_Angeles",
                                                          "liveActivity": nested,
                                                          "optedIn": true]))

        let events = operationalEvents()
        XCTAssertEqual(1, events.count)
        let payload = events[0].data
        XCTAssertEqual(["timezone", "liveActivity", "optedIn"], attributeKeys(payload))
        XCTAssertEqual("America/Los_Angeles", payload?["timezone"] as? String)
        XCTAssertEqual(true, payload?["optedIn"] as? Bool)
        XCTAssertEqual(nested as NSDictionary, payload?["liveActivity"] as? NSDictionary)
    }

    func testDeviceAttributes_valueIsNotValidated() {
        // The SDK no longer validates values; whatever the app passes is forwarded.
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Not/AReal/Zone"]))

        XCTAssertEqual("Not/AReal/Zone", operationalEvents().first?.data?["timezone"] as? String)
    }

    func testDeviceAttributes_nonJSONValue_droppedOthersSent() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Asia/Kolkata", "bad": Date()]))

        let payload = operationalEvents().first?.data
        XCTAssertEqual("Asia/Kolkata", payload?["timezone"] as? String)
        XCTAssertNil(payload?["bad"])
        XCTAssertNil(syncedDeviceValues()["bad"])
    }

    func testDeviceAttributes_onlyNonJSONValues_dispatchesNothing() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["bad": Date()]))

        XCTAssertTrue(operationalEvents().isEmpty)
    }

    func testDeviceAttributes_emptyEventData_dispatchesNothing() {
        mockRuntime.simulateComingEvents(makeDeviceEvent([:]))

        XCTAssertTrue(operationalEvents().isEmpty)
    }

    // MARK: - App context (added to every update)

    func testDeviceAttributes_pushNotification_addsApp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: "push-token-123"]))

        let payload = operationalEvents()[0].data
        XCTAssertEqual("push-token-123", payload?[pushKey] as? String)
        let app = payload?[appKey] as? [String: Any]
        XCTAssertEqual(Bundle.main.bundleIdentifier, app?[IdentityConstants.DeviceAttributes.APP_ID] as? String)
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_withoutPushToken_stillAddsApp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        mockRuntime.simulateComingEvents(makeDeviceEvent(["liveActivityUpdate": [["liveActivityID": "Test2", "token": "t"]]]))

        let app = operationalEvents()[0].data?[appKey] as? [String: Any]
        XCTAssertEqual(Bundle.main.bundleIdentifier, app?[IdentityConstants.DeviceAttributes.APP_ID] as? String)
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_pushNotification_useSandboxTrue_usesSandboxPlatform() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let event = makeDeviceEvent([pushKey: "push-token-123"])
        simulateConfig([IdentityConstants.DeviceAttributes.MESSAGING_USE_SANDBOX: true], for: event)

        mockRuntime.simulateComingEvents(event)

        let app = operationalEvents()[0].data?[appKey] as? [String: Any]
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS_SANDBOX, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_callerProvidedApp_notOverwritten() {
        let callerApp: [String: Any] = ["id": "com.example.custom", "platform": "apnsSandbox"]
        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: "push-token-123", appKey: callerApp]))

        XCTAssertEqual(callerApp as NSDictionary, operationalEvents()[0].data?[appKey] as? NSDictionary)
    }

    func testDeviceAttributes_pushNotificationDeduped_appStillAdded() {
        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: "push-token-123"]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: "push-token-123", "timezone": "Asia/Kolkata"]))

        let payload = operationalEvents()[0].data
        XCTAssertNil(payload?[pushKey])
        XCTAssertEqual("Asia/Kolkata", payload?["timezone"] as? String)
        if Bundle.main.bundleIdentifier != nil {
            XCTAssertNotNil(payload?[appKey])
        }
    }

    func testDeviceAttributes_nothingChanged_noAppOnlyDispatch() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Asia/Kolkata"]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Asia/Kolkata"]))

        XCTAssertTrue(operationalEvents().isEmpty, "app alone must never trigger a dispatch")
    }

    // MARK: - Key-based dedup (default true)

    func testDeviceAttributes_sameKeySameValue_sentOnlyOnce() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))

        XCTAssertEqual(1, operationalEvents().count)
    }

    func testDeviceAttributes_sameKeyChangedValue_sentAgain() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Asia/Kolkata"]))

        XCTAssertEqual(2, operationalEvents().count)
        XCTAssertEqual("Asia/Kolkata", operationalEvents()[1].data?["timezone"] as? String)
    }

    func testDeviceAttributes_onlyChangedKeysInPayload() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London", "customCount": 1]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London", "customCount": 2]))

        let payload = operationalEvents()[0].data
        XCTAssertEqual(["customCount"], attributeKeys(payload))
        XCTAssertEqual(2, payload?["customCount"] as? Int)
    }

    func testDeviceAttributes_keysSyncedIndependently_acrossCalls() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))
        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: "push-token-123"]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        // Both keys already synced with these values -> nothing sent.
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London", pushKey: "push-token-123"]))

        XCTAssertTrue(operationalEvents().isEmpty)
    }

    func testDeviceAttributes_boolAndNumberNotConsideredEqual() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["flag": 1]))
        mockRuntime.simulateComingEvents(makeDeviceEvent(["flag": true]))

        XCTAssertEqual(2, operationalEvents().count)
    }

    func testDeviceAttributes_nestedKeyOrderIgnoredForDedup() {
        let first = NSMutableDictionary()
        first["a"] = 1
        first["b"] = 2
        let second = NSMutableDictionary()
        second["b"] = 2
        second["a"] = 1

        mockRuntime.simulateComingEvents(makeDeviceEvent(["nested": first]))
        mockRuntime.simulateComingEvents(makeDeviceEvent(["nested": second]))

        XCTAssertEqual(1, operationalEvents().count)
    }

    func testDeviceAttributes_persistsSyncedValuesToDeviceStore() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Pacific/Auckland", "customCount": 3]))

        let synced = syncedDeviceValues()
        // Canonical form is the value serialized inside a one-element JSON array.
        XCTAssertEqual("[\"Pacific\\/Auckland\"]", synced["timezone"])
        XCTAssertEqual("[3]", synced["customCount"])
    }

    // MARK: - Dedup config flag

    func testDeviceAttributes_dedupFalse_repeatedIdentical_alwaysDispatches() {
        let first = makeDeviceEvent(["timezone": "Europe/London"])
        simulateConfig([IdentityConstants.ConfigKeys.DEVICE_ATTRIBUTES_DEDUP: false], for: first)
        mockRuntime.simulateComingEvents(first)

        let second = makeDeviceEvent(["timezone": "Europe/London"])
        simulateConfig([IdentityConstants.ConfigKeys.DEVICE_ATTRIBUTES_DEDUP: false], for: second)
        mockRuntime.simulateComingEvents(second)

        XCTAssertEqual(2, operationalEvents().count)
    }

    // MARK: - Store independence between profile and device paths

    func testStoreNameConstants_areDistinct() {
        XCTAssertNotEqual(IdentityConstants.Store.PROFILE_ATTRIBUTES,
                          IdentityConstants.Store.DEVICE_ATTRIBUTES,
                          "Profile and device dedup stores must be distinct or a profile write would suppress the device dispatch")
    }

    func testProfileThenDevice_sameTimezone_bothDispatch() {
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Asia/Kolkata"))
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Asia/Kolkata"]))

        XCTAssertEqual(1, edgeEvents().count, "Profile path should dispatch its Edge event")
        XCTAssertEqual(1, operationalEvents().count, "Device path should dispatch its operational-data event")
    }

    func testDeviceThenProfile_sameTimezone_bothDispatch() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Europe/London"))

        XCTAssertEqual(1, operationalEvents().count)
        XCTAssertEqual(1, edgeEvents().count)
    }

    // MARK: - Only the API's own request is forwarded

    func testOtherEventOnSameTypeAndSource_isNotForwarded() {
        let otherEvent = Event(name: "Some Other Request",
                               type: EventType.edgeIdentity,
                               source: EventSource.requestContent,
                               data: ["timezone": "Asia/Kolkata", "secret": "value"])

        mockRuntime.simulateComingEvents(otherEvent)

        XCTAssertTrue(operationalEvents().isEmpty)
        XCTAssertTrue(syncedDeviceValues().isEmpty, "Ignored events must not be recorded as synced")
    }

    // MARK: - Reset

    func testResetIdentities_clearsSyncedValues_sameValueSentAgain() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London", pushKey: ["token-1"]]))
        XCTAssertEqual(1, operationalEvents().count)

        mockRuntime.simulateComingEvents(Event(name: "Reset",
                                               type: EventType.genericIdentity,
                                               source: EventSource.requestReset,
                                               data: nil))
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London", pushKey: ["token-1"]]))

        let payload = operationalEvents().first?.data
        XCTAssertEqual("Europe/London", payload?["timezone"] as? String)
        XCTAssertEqual(["token-1"], payload?[pushKey] as? [String])
    }

    // MARK: - Backend payload shape (arrays / arrays of objects)

    private let backendAttributes: [String: Any] = [
        "timezone": "America/Los_Angeles",
        "pushNotification": ["804EB6EDB22D-EBE91B"],
        "liveActivityStart": [["attributeType": "GameScoreLiveActivityAttributes", "value": "80dbbb63f25f-be5b3"]],
        "liveActivityUpdate": [["liveActivityID": "Test2", "token": "803051959663-e2bc6"]]
    ]

    func testBackendShape_passesThroughUnchanged_withApp() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(backendAttributes))

        let payload = operationalEvents().first?.data
        XCTAssertEqual("America/Los_Angeles", payload?["timezone"] as? String)
        XCTAssertEqual(["804EB6EDB22D-EBE91B"], payload?[pushKey] as? [String])
        XCTAssertEqual(backendAttributes["liveActivityStart"] as? NSArray, payload?["liveActivityStart"] as? NSArray)
        XCTAssertEqual(backendAttributes["liveActivityUpdate"] as? NSArray, payload?["liveActivityUpdate"] as? NSArray)
        if Bundle.main.bundleIdentifier != nil {
            let app = payload?[appKey] as? [String: Any]
            XCTAssertEqual(Bundle.main.bundleIdentifier, app?[IdentityConstants.DeviceAttributes.APP_ID] as? String)
            XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
        }
    }

    func testBackendShape_repeated_sentOnce() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(backendAttributes))
        mockRuntime.simulateComingEvents(makeDeviceEvent(backendAttributes))

        XCTAssertEqual(1, operationalEvents().count)
    }

    func testBackendShape_oneLiveActivityTokenChanged_onlyThatKeyResent() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(backendAttributes))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        var updated = backendAttributes
        updated["liveActivityUpdate"] = [["liveActivityID": "Test2", "token": "NEW-TOKEN"]]
        mockRuntime.simulateComingEvents(makeDeviceEvent(updated))

        let payload = operationalEvents().first?.data
        XCTAssertEqual(["liveActivityUpdate"], attributeKeys(payload))
        XCTAssertEqual(updated["liveActivityUpdate"] as? NSArray, payload?["liveActivityUpdate"] as? NSArray)
        // A live-activity-only update still carries app context for routing.
        if Bundle.main.bundleIdentifier != nil {
            XCTAssertNotNil(payload?[appKey])
        }
    }

    func testBackendShape_arrayOrderChange_isTreatedAsChange() {
        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: ["a", "b"]]))
        mockRuntime.simulateComingEvents(makeDeviceEvent([pushKey: ["b", "a"]]))

        XCTAssertEqual(2, operationalEvents().count)
    }
}
