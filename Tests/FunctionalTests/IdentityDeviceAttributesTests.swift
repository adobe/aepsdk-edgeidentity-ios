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

/// Functional tests for sending device attributes regardless of collect consent (`updateDeviceAttributesBypassConsent`):
/// rule response -> request queue -> device attributes response event -> deduplication against the confirmed values.
class IdentityDeviceAttributesTests: XCTestCase {
    var identity: Identity!
    var mockRuntime: TestableExtensionRuntime!
    // Keeps the profile attributes and device attributes stores separate; the shared MockDataStore ignores the
    // collection name, so a value in one store would hide the same value in the other.
    var mockDataStore: CollectionAwareMockDataStore!

    private let deviceStore = IdentityConstants.DataStoreKeys.DEVICE_ATTRIBUTES_DATASTORE_NAME
    private let profileStore = IdentityConstants.ProfileAttributes.STORE_NAME
    private let timeZoneKey = IdentityConstants.DeviceAttributes.TIME_ZONE
    private let pushKey = "pushNotification"
    private let appKey = IdentityConstants.DeviceAttributes.APP

    override func setUp() {
        continueAfterFailure = false
        mockDataStore = CollectionAwareMockDataStore()
        ServiceProvider.shared.namedKeyValueService = mockDataStore
        mockRuntime = TestableExtensionRuntime()
        resetState()
    }

    override func tearDown() {
        clearStores()
        super.tearDown()
    }

    private func clearStores() {
        DeviceAttributeDeduplicator(storeName: deviceStore).clear()
        mockDataStore.remove(collectionName: profileStore, key: timeZoneKey)
    }

    /// Starts a new Identity, which reads the persisted device attributes store.
    private func startIdentity() {
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
        XCTAssertTrue(identity.readyForEvent(Event(name: "boot", type: "test-type", source: "test-source", data: nil)))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()
    }

    /// Deterministic start: both stores empty (no reliance on device timezone / prior runs) and a new Identity.
    private func resetState() {
        clearStores()
        startIdentity()
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
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                        data: (config, .set))
    }

    /// Registers the Consent extension with the Event Hub and sets its collect consent.
    private func simulateCollectConsent(_ value: String?) {
        simulateRegisteredExtensions([IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME])
        let data: [String: Any] = value.map { ["consents": ["collect": ["val": $0]]] } ?? [:]
        mockRuntime.simulateXDMSharedState(for: IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME,
                                           data: (data, .set))
    }

    private func bypassEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.type == IdentityConstants.DeviceAttributes.BYPASS_TYPE }
    }

    @discardableResult
    private func complete(_ event: Event, status: String = "success") -> Event {
        let response = event.createChainedEvent(name: "Edge bypass result",
                                                type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                                source: EventSource.responseContent,
                                                data: ["status": status, "reason": "network"])
        mockRuntime.simulateComingEvents(response)
        return response
    }

    @discardableResult
    private func consequence(_ data: [String: Any], completeImmediately: Bool = true) -> Event? {
        let count = bypassEvents().count
        mockRuntime.simulateComingEvents(Event(name: "Forward operational data",
                                              type: EventType.edgeIdentity,
                                              source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE, data: data))
        guard bypassEvents().count > count, let edge = bypassEvents().last else { return nil }
        if completeImmediately { complete(edge) }
        return edge
    }

    private func sync(_ data: [String: Any]) {
        mockRuntime.simulateComingEvents(makeDeviceEvent(data))
        guard let operational = operationalEvents().last else {
            XCTFail("Expected an operational event")
            return
        }
        consequence(operational.data ?? [:])
    }

    /// Events that forward the API data to the rules engine.
    private func operationalEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.type == IdentityConstants.DeviceAttributes.OPERATIONAL_DATA_TYPE }
    }

    private func edgeEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.type == EventType.edge }
    }

    /// Confirmed device attributes as a nested map.
    private func storedDeviceAttributes() -> [String: Any] {
        return DeviceAttributeDeduplicator(storeName: deviceStore).readSynced()
    }

    /// Confirmed device attribute leaf values keyed by path. A non-empty map is walked; any other value is a leaf.
    private func syncedDeviceValues() -> [[String]: Any] {
        var leaves: [[String]: Any] = [:]
        func walk(_ map: [String: Any], _ path: [String]) {
            for (key, value) in map {
                if let child = value as? [String: Any], !child.isEmpty {
                    walk(child, path + [key])
                } else {
                    leaves[path + [key]] = value
                }
            }
        }
        walk(storedDeviceAttributes(), [])
        return leaves
    }

    /// True when every value in `attributes` matches the persisted device attributes store.
    private func isSynced(_ attributes: [String: Any]) -> Bool {
        return DeviceAttributeDeduplicator(storeName: deviceStore).filter(attributes, owners: nil).changed.isEmpty
    }

    private func syncResultEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.name == IdentityConstants.EventNames.DEVICE_ATTRIBUTES_SYNC_RESULT }
    }

    private func tokensConfirmedEvents() -> [Event] {
        return mockRuntime.dispatchedEvents.filter { $0.name == IdentityConstants.EventNames.DEVICE_ATTRIBUTES_CONFIRMED }
    }

    private func lastProfileAttributesSharedState() -> [String: Any]? {
        let state = mockRuntime.createdSharedStates.last ?? nil
        return state?[IdentityConstants.ProfileAttributes.SHARED_STATE_KEY] as? [String: Any]
    }

    private func simulateRegisteredExtensions(_ names: [String]) {
        let extensions = Dictionary(uniqueKeysWithValues: names.map { ($0, ["version": "5.0.0"] as [String: Any]) })
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME,
                                        data: ([IdentityConstants.SharedState.Hub.EXTENSIONS: extensions], .set))
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

    func testDeviceAttributes_nonJSONValue_isSentAsIsAndNotStored() {
        let date = Date()
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Asia/Kolkata", "bad": date, "null": NSNull()]))
        consequence(operationalEvents().last?.data ?? [:])
        let payload = bypassEvents().first?.data
        XCTAssertEqual("Asia/Kolkata", payload?["timezone"] as? String)
        XCTAssertEqual(date, payload?["bad"] as? Date)
        XCTAssertTrue(payload?["null"] is NSNull)
        XCTAssertNil(syncedDeviceValues()[["bad"]])
        XCTAssertNil(syncedDeviceValues()[["null"]])
    }

    func testDeviceAttributes_emptyEventData_dispatchesNothing() {
        mockRuntime.simulateComingEvents(makeDeviceEvent([:]))

        XCTAssertTrue(operationalEvents().isEmpty)
    }

    // MARK: - SDK-owned app details (added only when sending to Edge)

    func testDeviceAttributes_pushNotification_addsApp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        sync([pushKey: "push-token-123"])

        XCTAssertNil(operationalEvents()[0].data?[appKey])
        let payload = bypassEvents()[0].data
        XCTAssertEqual("push-token-123", payload?[pushKey] as? String)
        let app = payload?[appKey] as? [String: Any]
        XCTAssertEqual(Bundle.main.bundleIdentifier, app?[IdentityConstants.DeviceAttributes.APP_ID] as? String)
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_withoutPushToken_stillAddsApp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        sync(["liveActivityUpdate": [["liveActivityID": "Test2", "token": "t"]]])

        let app = bypassEvents()[0].data?[appKey] as? [String: Any]
        XCTAssertEqual(Bundle.main.bundleIdentifier, app?[IdentityConstants.DeviceAttributes.APP_ID] as? String)
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_pushNotification_useSandboxTrue_usesSandboxPlatform() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let event = makeDeviceEvent([pushKey: "push-token-123"])
        simulateConfig([IdentityConstants.DeviceAttributes.MESSAGING_USE_SANDBOX: true], for: event)

        mockRuntime.simulateComingEvents(event)
        consequence(operationalEvents()[0].data ?? [:])

        let app = bypassEvents()[0].data?[appKey] as? [String: Any]
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS_SANDBOX, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_callerProvidedApp_doesNotOverrideSDKRouting() {
        let callerApp: [String: Any] = ["id": "com.example.custom", "platform": "apnsSandbox"]
        sync([pushKey: "push-token-123", appKey: callerApp])

        let app = bypassEvents()[0].data?[appKey] as? [String: Any]
        XCTAssertEqual(Bundle.main.bundleIdentifier, app?[IdentityConstants.DeviceAttributes.APP_ID] as? String)
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PLATFORM_APNS, app?[IdentityConstants.DeviceAttributes.APP_PLATFORM] as? String)
    }

    func testDeviceAttributes_pushNotificationDeduped_appStillAdded() {
        sync(["tokens": [pushKey: "push-token-123"]])
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        sync(["tokens": [pushKey: "push-token-123"], "timezone": "Asia/Kolkata"])

        let payload = bypassEvents()[0].data
        XCTAssertNil(payload?["tokens"])
        XCTAssertEqual("Asia/Kolkata", payload?["timezone"] as? String)
        if Bundle.main.bundleIdentifier != nil {
            XCTAssertNotNil(payload?[appKey])
        }
    }

    func testDeviceAttributes_nothingChanged_noAppOnlyDispatch() {
        sync(["timezone": "Asia/Kolkata"])
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        sync(["timezone": "Asia/Kolkata"])

        XCTAssertTrue(bypassEvents().isEmpty, "app alone must never trigger an Edge dispatch")
    }

    // MARK: - Deduplication by key (enabled by default)

    func testDeviceAttributes_sameKeySameValue_sentOnlyOnce() {
        sync(["timezone": "Europe/London"])
        sync(["timezone": "Europe/London"])

        XCTAssertEqual(1, bypassEvents().count)
        XCTAssertEqual(2, operationalEvents().count, "Dedup must not run before rules")
    }

    func testDeviceAttributes_sameKeyChangedValue_sentAgain() {
        sync(["timezone": "Europe/London"])
        sync(["timezone": "Asia/Kolkata"])

        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertEqual("Asia/Kolkata", bypassEvents()[1].data?["timezone"] as? String)
    }

    func testDeviceAttributes_onlyChangedKeysInPayload() {
        sync(["timezone": "Europe/London", "customCount": 1])
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        sync(["timezone": "Europe/London", "customCount": 2])

        let payload = bypassEvents()[0].data
        XCTAssertEqual(["customCount"], attributeKeys(payload))
        XCTAssertEqual(2, payload?["customCount"] as? Int)
    }

    func testDeviceAttributes_keysSyncedIndependently_acrossCalls() {
        sync(["timezone": "Europe/London"])
        sync(["tokens": [pushKey: "push-token-123"]])
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        // Both keys are already confirmed with these values, so nothing is sent.
        sync(["timezone": "Europe/London", "tokens": [pushKey: "push-token-123"]])

        XCTAssertTrue(bypassEvents().isEmpty)
    }

    func testDeviceAttributes_boolAndNumberNotConsideredEqual() {
        sync(["flag": 1])
        sync(["flag": true])

        XCTAssertEqual(2, bypassEvents().count)
    }

    func testDeviceAttributes_nestedKeyOrderIgnoredForDedup() {
        let first = NSMutableDictionary()
        first[pushKey] = "push"
        first["liveActivityStart"] = [["attributeType": "A", "value": "start"]]
        let second = NSMutableDictionary()
        second["liveActivityStart"] = [["value": "start", "attributeType": "A"]]
        second[pushKey] = "push"

        sync(["tokens": first])
        sync(["tokens": second])

        XCTAssertEqual(1, bypassEvents().count)
    }

    func testDeviceAttributes_persistsSyncedValuesToDeviceStore() {
        sync(["timezone": "Pacific/Auckland", "tokens": [pushKey: "push"], "customCount": 3])

        // Only deduplicated paths are stored.
        XCTAssertEqual(["timezone": "Pacific/Auckland", "tokens": [pushKey: "push"]] as NSDictionary,
                       storedDeviceAttributes() as NSDictionary)
    }

    // MARK: - Deduplication config flag

    func testDeviceAttributes_dedupFalse_repeatedIdentical_alwaysDispatches() {
        let first = makeDeviceEvent(["timezone": "Europe/London"])
        simulateConfig([IdentityConstants.DeviceAttributes.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC: false], for: first)
        mockRuntime.simulateComingEvents(first)
        consequence(operationalEvents().last?.data ?? [:])

        let second = makeDeviceEvent(["timezone": "Europe/London"])
        simulateConfig([IdentityConstants.DeviceAttributes.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC: false], for: second)
        mockRuntime.simulateComingEvents(second)
        consequence(operationalEvents().last?.data ?? [:])

        XCTAssertEqual(2, bypassEvents().count)
    }

    // MARK: - Profile attributes and device attributes stores are independent

    func testStoreNameConstants_areDistinct() {
        XCTAssertNotEqual(IdentityConstants.ProfileAttributes.STORE_NAME,
                          IdentityConstants.DataStoreKeys.DEVICE_ATTRIBUTES_DATASTORE_NAME,
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
        sync(["timezone": "Europe/London", pushKey: ["token-1"]])
        XCTAssertEqual(1, operationalEvents().count)

        mockRuntime.simulateComingEvents(Event(name: "Reset",
                                               type: EventType.genericIdentity,
                                               source: EventSource.requestReset,
                                               data: nil))
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        sync(["timezone": "Europe/London", pushKey: ["token-1"]])

        let payload = bypassEvents().first?.data
        XCTAssertEqual("Europe/London", payload?["timezone"] as? String)
        XCTAssertEqual(["token-1"], payload?[pushKey] as? [String])
    }

    // MARK: - Nested tokens, arrays and arrays of objects

    private let backendTokens: [String: Any] = [
        "pushNotification": "804EB6EDB22D-EBE91B",
        "liveActivityStart": [["attributeType": "GameScoreLiveActivityAttributes", "value": "80dbbb63f25f-be5b3"]],
        "liveActivityUpdate": [["liveActivityID": "Test2", "token": "803051959663-e2bc6"]]
    ]

    private var backendAttributes: [String: Any] {
        return ["timezone": "America/Los_Angeles", "tokens": backendTokens]
    }

    func testBackendShape_passesThroughUnchanged_withoutSDKAppBeforeRules() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(backendAttributes))

        let payload = operationalEvents().first?.data
        XCTAssertEqual("America/Los_Angeles", payload?["timezone"] as? String)
        XCTAssertEqual(backendTokens as NSDictionary, payload?["tokens"] as? NSDictionary)
        XCTAssertNil(payload?[appKey])
    }

    func testBackendShape_repeated_onlyLiveActivityUpdateTokensResent() {
        sync(backendAttributes)
        sync(backendAttributes)

        XCTAssertEqual(2, bypassEvents().count)
        // Live Activity update tokens are not deduplicated, so they are sent every time.
        XCTAssertEqual(["tokens"], attributeKeys(bypassEvents().last?.data))
        XCTAssertEqual(["liveActivityUpdate": backendTokens["liveActivityUpdate"] as Any] as NSDictionary,
                       bypassEvents().last?.data?["tokens"] as? NSDictionary)
    }

    func testBackendShape_oneLiveActivityStartTokenChanged_onlyThatTokenAndUpdateTokensResent() {
        sync(backendAttributes)
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        var tokens = backendTokens
        tokens["liveActivityStart"] = [["attributeType": "GameScoreLiveActivityAttributes", "value": "NEW-TOKEN"]]
        sync(["timezone": "America/Los_Angeles", "tokens": tokens])

        let payload = bypassEvents().first?.data
        XCTAssertEqual(["tokens"], attributeKeys(payload))
        XCTAssertEqual(["liveActivityStart": tokens["liveActivityStart"] as Any,
                        "liveActivityUpdate": tokens["liveActivityUpdate"] as Any] as NSDictionary,
                       payload?["tokens"] as? NSDictionary)
        // A live-activity-only update still carries app context for routing.
        if Bundle.main.bundleIdentifier != nil {
            XCTAssertNotNil(payload?[appKey])
        }
    }

    func testBackendShape_arrayOrderChange_isNotAChange() {
        sync(["tokens": ["liveActivityStart": [["attributeType": "1", "value": "a"], ["attributeType": "2", "value": "b"]]]])
        sync(["tokens": ["liveActivityStart": [["value": "b", "attributeType": "2"], ["value": "a", "attributeType": "1"]]]])

        XCTAssertEqual(1, bypassEvents().count)
    }

    func testBackendShape_arrayElementChange_isAChange() {
        sync([pushKey: ["a", "b"]])
        sync([pushKey: ["a", "c"]])
        sync([pushKey: ["a"]])

        XCTAssertEqual(3, bypassEvents().count)
    }

    func testPublicRequestsDoNotWaitForRulesOrChangeDedupStore() {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London"]))
        XCTAssertEqual(2, operationalEvents().count)
        XCTAssertTrue(bypassEvents().isEmpty)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        XCTAssertFalse(mockRuntime.dispatchedEvents.contains { $0.name == "Device attributes barrier" })
    }

    func testConsequenceValuesAreCommittedOnlyAfterMatchingSuccess() throws {
        let edge = consequence(["timezone": "Europe/London"], completeImmediately: false)!
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        let other = Event(name: "other", type: "other", source: "other", data: nil)
        complete(other)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        complete(edge)
        XCTAssertEqual(["timezone": "Europe/London"] as NSDictionary, storedDeviceAttributes() as NSDictionary)
        XCTAssertNil(consequence(["timezone": "Europe/London"]))
    }

    func testQueuedConsequenceIsDedupedOnlyWhenSent() {
        let first = consequence(["timezone": "Europe/London"], completeImmediately: false)!
        XCTAssertNil(consequence(["timezone": "Europe/London"], completeImmediately: false))
        XCTAssertNil(consequence(["timezone": "Asia/Kolkata"], completeImmediately: false))
        XCTAssertEqual(1, bypassEvents().count)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        complete(first)
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertEqual("Asia/Kolkata", bypassEvents().last?.data?["timezone"] as? String)
    }

    func testFailedOrDroppedRequestDoesNotCommitAndReleasesNextConsequence() {
        for status in ["failed", "dropped"] {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            let first = consequence(["timezone": "Europe/London"], completeImmediately: false)!
            consequence(["timezone": "Europe/London"], completeImmediately: false)
            complete(first, status: status)
            XCTAssertEqual(2, bypassEvents().count)
            XCTAssertTrue(syncedDeviceValues().isEmpty)
            complete(bypassEvents().last!)
            XCTAssertEqual(1, syncedDeviceValues().count)
        }
    }

    func testRepeatedSuccessCannotCompleteNextQueuedRequest() {
        let first = consequence(["timezone": "Europe/London"], completeImmediately: false)!
        consequence(["timezone": "Asia/Kolkata"], completeImmediately: false)
        complete(first)
        let second = bypassEvents().last!
        complete(first)
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(isSynced(["timezone": "Asia/Kolkata"]))
        complete(second)
        XCTAssertTrue(isSynced(["timezone": "Asia/Kolkata"]))
    }

    func testContextIsNeverSentAsAnAttribute() {
        consequence(["app": ["id": "test"]])
        XCTAssertTrue(bypassEvents().isEmpty)
        let edge = consequence(["timezone": NSNull(), "tokens": ["liveActivityStart": []],
                                "app": ["id": "test"]])!
        XCTAssertTrue(edge.data?["timezone"] is NSNull)
        XCTAssertEqual([], (edge.data?["tokens"] as? [String: Any])?["liveActivityStart"] as? [String])
        XCTAssertEqual(1, syncedDeviceValues().count)
    }

    func testResetDiscardsQueueAndLateSuccess() {
        let confirmed: [String: Any] = ["tokens": ["pushNotification": "confirmed"]]
        XCTAssertNotNil(consequence(confirmed))
        let first = consequence(["timezone": "Europe/London"], completeImmediately: false)!
        consequence(["timezone": "Asia/Kolkata"], completeImmediately: false)
        mockRuntime.simulateComingEvents(Event(name: "Reset", type: EventType.genericIdentity,
                                               source: EventSource.requestReset, data: nil))
        complete(first)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertNotNil(consequence(confirmed))
        XCTAssertNotNil(consequence(["timezone": "Europe/London"]))
    }

    func testConfirmedStoreRestoredAfterIdentityReinitialization() {
        XCTAssertNotNil(consequence(["timezone": "Europe/London"]))
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()
        XCTAssertNil(consequence(["timezone": "Europe/London"]))
        XCTAssertTrue(bypassEvents().isEmpty)
    }

    func testDedupPathsDoNotCollideWithLiteralDottedKeys() {
        let dedup = DeviceAttributeDeduplicator(storeName: deviceStore)
        let attributes: [String: Any] = ["tokens.pushNotification": "dotted", "tokens": ["pushNotification": "push"]]
        dedup.commit(attributes)
        // The literal dotted key is not a deduplicated path, so only it is sent again.
        XCTAssertEqual(["tokens.pushNotification": "dotted"] as NSDictionary,
                       dedup.filter(attributes, owners: nil).changed as NSDictionary)
    }

    private func deviceAttributeRulesEngine(attributes: [[String: Any]]) throws -> LaunchRulesEngine {
        let rule: [String: Any] = [
            "version": 1,
            "rules": [[
                "condition": ["type": "matcher", "definition": [
                    "key": "~type", "matcher": "eq",
                    "values": [IdentityConstants.DeviceAttributes.OPERATIONAL_DATA_TYPE]
                ]],
                "consequences": [[
                    "id": "allow-device-attributes", "type": "forward-operational-data",
                    "detail": [
                        "type": EventType.edgeIdentity,
                        "source": IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE,
                        "attributes": attributes
                    ]
                ]]
            ]]
        ]
        let rules = try XCTUnwrap(JSONRulesParser.parse(JSONSerialization.data(withJSONObject: rule)))
        let engine = LaunchRulesEngine(name: "test", extensionRuntime: mockRuntime)
        engine.replaceRules(with: rules)
        return engine
    }

    func testSuccessfulBypassUpdatesTimezoneOwnerAndSkipsMatchingProfileRequest() throws {
        let edge = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
        XCTAssertNil(mockDataStore.get(collectionName: profileStore, key: timeZoneKey))
        complete(edge)
        XCTAssertEqual("Europe/London",
                       mockDataStore.get(collectionName: profileStore, key: timeZoneKey) as? String)
        XCTAssertEqual(["timezone": "Europe/London"] as NSDictionary, lastProfileAttributesSharedState() as NSDictionary?)
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Europe/London"))
        XCTAssertTrue(edgeEvents().isEmpty)
        mockRuntime.simulateComingEvents(makeProfileEvent(timezone: "Asia/Kolkata"))
        XCTAssertEqual(1, edgeEvents().count)
    }

    func testSuccessfulBypassDispatchesSuccessSyncResultWithCommittedAttributes() throws {
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": [
            "pushNotification": "", "liveActivityStart": [["attributeType": "A", "value": "start"]]
        ]]
        let edge = try XCTUnwrap(consequence(attributes, completeImmediately: false))
        XCTAssertTrue(syncResultEvents().isEmpty)
        let result = edge.createChainedEvent(name: "Device Attributes Response",
                                            type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                            source: EventSource.responseContent, data: ["status": "success"])
        mockRuntime.simulateComingEvents(result)
        let syncResult = try XCTUnwrap(syncResultEvents().first)
        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertEqual("Device Attributes Sync Result", syncResult.name)
        XCTAssertEqual(EventType.edgeIdentity, syncResult.type)
        XCTAssertEqual(EventSource.responseContent, syncResult.source)
        XCTAssertEqual(result.id, syncResult.parentID)
        XCTAssertNil(syncResult.responseID)
        XCTAssertEqual(["status": "success", "reason": "", "attributes": attributes] as NSDictionary, syncResult.data as NSDictionary?)
        // Messaging gets the tokens Edge confirmed as sent, including an empty push token.
        XCTAssertEqual([["tokens": attributes["tokens"] ?? [:]]] as [NSDictionary],
                       mockRuntime.dispatchedEvents.filter { $0.type == EventType.messaging }.map { ($0.data ?? [:]) as NSDictionary })
        mockRuntime.simulateComingEvents(result)
        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertEqual(1, tokensConfirmedEvents().count)
    }

    func testFailedOrDroppedBypassDispatchesFailedSyncResult() throws {
        let cases: [(data: [String: Any], expected: [String: Any])] = [
            (["status": "failed", "reason": "network"], ["status": "failed", "reason": "network"]),
            (["status": "dropped", "reason": "consent"], ["status": "failed", "reason": "consent"]),
            (["status": "failed"], ["status": "failed", "reason": "unknown"]),
            (["status": "failed", "reason": 500], ["status": "failed", "reason": "unknown"])
        ]
        for testCase in cases {
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            let edge = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
            let result = edge.createChainedEvent(name: "Device Attributes Response",
                                                type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                                source: EventSource.responseContent, data: testCase.data)
            mockRuntime.simulateComingEvents(result)
            let syncResult = try XCTUnwrap(syncResultEvents().first)
            XCTAssertEqual(1, syncResultEvents().count)
            XCTAssertEqual(EventType.edgeIdentity, syncResult.type)
            XCTAssertEqual(EventSource.responseContent, syncResult.source)
            XCTAssertEqual(result.id, syncResult.parentID)
            var expected = testCase.expected
            expected["attributes"] = ["timezone": "Europe/London"]
            XCTAssertEqual(expected as NSDictionary, syncResult.data as NSDictionary?)
            XCTAssertTrue(syncedDeviceValues().isEmpty)
        }
    }

    func testOwnerStoresAreNotUpdatedForFailureDropOrUnrelatedSuccess() throws {
        for status in ["failed", "dropped"] {
            let edge = try XCTUnwrap(consequence(["timezone": "Europe/London", "tokens": ["pushNotification": "push"]],
                                                completeImmediately: false))
            complete(Event(name: "unrelated", type: "other", source: "other", data: nil))
            complete(edge, status: status)
            XCTAssertNil(mockDataStore.get(collectionName: profileStore, key: timeZoneKey))
            XCTAssertFalse(syncResultEvents().contains { $0.data?["status"] as? String == "success" })
            XCTAssertTrue(syncedDeviceValues().isEmpty)
        }
    }

    func testCoreConsequenceFeedsOnlyAllowListedValuesToIdentity() throws {
        let engine = try deviceAttributeRulesEngine(attributes: [
            ["path": ["timezone"], "enabled": true],
            ["path": ["tokens", "pushNotification"], "enabled": false]
        ])
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "Europe/London",
                                                         "tokens": ["pushNotification": "blocked"]]))
        let operational = try XCTUnwrap(operationalEvents().last)
        _ = engine.process(event: operational)
        let response = try XCTUnwrap(mockRuntime.dispatchedEvents.last {
            $0.source == IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE
        })
        XCTAssertNil(response.responseID)
        XCTAssertEqual(operational.id, response.parentID)
        mockRuntime.simulateComingEvents(response)
        let edge = try XCTUnwrap(bypassEvents().last)
        XCTAssertEqual("Europe/London", edge.data?["timezone"] as? String)
        XCTAssertNil(edge.data?["tokens"])
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        complete(edge)
        XCTAssertEqual(1, syncedDeviceValues().count)
    }

    func testEmptyPushTokenReachesEdgeAndIsDeduplicatedOnlyAfterSuccess() throws {
        let engine = try deviceAttributeRulesEngine(attributes: [
            ["path": ["tokens", "pushNotification"], "enabled": true]
        ])
        let attributes: [String: Any] = ["tokens": ["pushNotification": ""]]
        DeviceAttributeDeduplicator(storeName: deviceStore).commit(["tokens": ["pushNotification": "previous"]])
        startIdentity()

        for status in ["failed", "success"] {
            mockRuntime.simulateComingEvents(makeDeviceEvent(attributes))
            let operational = try XCTUnwrap(operationalEvents().last)
            _ = engine.process(event: operational)
            let response = try XCTUnwrap(mockRuntime.dispatchedEvents.last {
                $0.source == IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE
            })
            mockRuntime.simulateComingEvents(response)
            let edge = try XCTUnwrap(bypassEvents().last)
            XCTAssertEqual("", (edge.data?["tokens"] as? [String: Any])?["pushNotification"] as? String)
            XCTAssertNotNil(edge.data?["app"])
            XCTAssertFalse(isSynced(attributes))
            complete(edge, status: status)
            XCTAssertEqual(status == "success", isSynced(attributes))
        }
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertNil(consequence(attributes))
        XCTAssertEqual(2, bypassEvents().count)
    }
}

extension IdentityDeviceAttributesTests {
    func testRegistersDedicatedConsequenceAndCompletionListenersWithoutWildcard() {
        XCTAssertNotNil(mockRuntime.getListener(type: EventType.edgeIdentity,
                                               source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE))
        XCTAssertNotNil(mockRuntime.getListener(type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                               source: EventSource.responseContent))
        XCTAssertNil(mockRuntime.getListener(type: EventType.wildcard, source: EventSource.wildcard))
    }

    func testConsequenceWithWrongTypeOrSourceDoesNotEnterQueue() {
        mockRuntime.simulateComingEvents(
            Event(name: "Forward operational data", type: EventType.edge,
                  source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE, data: ["timezone": "Europe/London"]),
            Event(name: "Forward operational data", type: EventType.edgeIdentity,
                  source: EventSource.responseContent, data: ["timezone": "Europe/London"]))
        XCTAssertTrue(bypassEvents().isEmpty)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
    }

    func testEmptyConsequencesDoNotBlockLaterAllowedValues() {
        mockRuntime.simulateComingEvents(
            Event(name: "Forward operational data", type: EventType.edgeIdentity,
                  source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE, data: nil))
        XCTAssertNil(consequence([:]))
        XCTAssertNil(consequence(["app": ["id": "test"]]))
        XCTAssertNotNil(consequence(["timezone": "Europe/London"]))
    }

    func testMatchingResultWithInvalidStatusIsTreatedAsFailed() throws {
        let invalidResults: [[String: Any]?] = [nil, [:], ["status": "unknown"], ["status": 202]]
        for data in invalidResults {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            let first = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
            consequence(["timezone": "Asia/Kolkata"], completeImmediately: false)
            mockRuntime.simulateComingEvents(first.createChainedEvent(name: "Device Attributes Response",
                                                                      type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                                                      source: EventSource.responseContent, data: data))
            XCTAssertEqual(2, bypassEvents().count)
            XCTAssertEqual("Asia/Kolkata", bypassEvents().last?.data?["timezone"] as? String)
            XCTAssertTrue(syncedDeviceValues().isEmpty)
            XCTAssertEqual(1, syncResultEvents().count)
            XCTAssertEqual(["status": "failed", "reason": "unknown", "attributes": ["timezone": "Europe/London"]] as NSDictionary,
                           syncResultEvents().last?.data as NSDictionary?)
            complete(bypassEvents().last!)
        }
    }

    func testUnchainedResultMatchedByRequestEventIdReleasesQueue() throws {
        let first = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
        consequence(["timezone": "Asia/Kolkata"], completeImmediately: false)
        mockRuntime.simulateComingEvents(Event(name: "Device Attributes Response",
                                               type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                               source: EventSource.responseContent,
                                               data: ["status": "failed", "requestEventId": first.id.uuidString]))
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertEqual(["status": "failed", "reason": "unknown", "attributes": ["timezone": "Europe/London"]] as NSDictionary,
                       syncResultEvents().last?.data as NSDictionary?)

        let second = try XCTUnwrap(bypassEvents().last)
        mockRuntime.simulateComingEvents(Event(name: "Device Attributes Response",
                                               type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                               source: EventSource.responseContent,
                                               data: ["status": "success", "requestEventId": second.id.uuidString]))
        XCTAssertEqual(["timezone": "Asia/Kolkata"] as NSDictionary, storedDeviceAttributes() as NSDictionary)
    }

    func testRequestEventIdIsMatchedAsAnExactString() throws {
        let first = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
        mockRuntime.simulateComingEvents(Event(name: "Device Attributes Response",
                                               type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                               source: EventSource.responseContent,
                                               data: ["status": "success", "requestEventId": first.id.uuidString.lowercased()]))
        XCTAssertTrue(syncResultEvents().isEmpty)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        complete(first)
        XCTAssertEqual(1, syncResultEvents().count)
    }

    func testNonMatchingResultDoesNotAdvanceQueue() throws {
        let first = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
        consequence(["timezone": "Asia/Kolkata"], completeImmediately: false)
        let unrelated = Event(name: "unrelated", type: "other", source: "other", data: nil)
        mockRuntime.simulateComingEvents(
            unrelated.createChainedEvent(name: "Device Attributes Response",
                                         type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                         source: EventSource.responseContent, data: ["status": "success"]),
            Event(name: "Device Attributes Response",
                  type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                  source: EventSource.responseContent,
                  data: ["status": "success", "requestEventId": UUID().uuidString]),
            Event(name: "Device Attributes Response",
                  type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                  source: EventSource.responseContent,
                  data: ["status": "success"]))
        XCTAssertEqual(1, bypassEvents().count)
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        XCTAssertTrue(syncResultEvents().isEmpty)
        complete(first)
        XCTAssertEqual(2, bypassEvents().count)
    }

    func testResultWithWrongTypeOrSourceDoesNotCompleteActiveRequest() throws {
        let first = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
        mockRuntime.simulateComingEvents(
            first.createChainedEvent(name: "Edge bypass result", type: EventType.edge,
                                     source: EventSource.responseContent, data: ["status": "success"]),
            first.createChainedEvent(name: "Edge bypass result", type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                     source: EventSource.responseIdentity, data: ["status": "success"]))
        XCTAssertTrue(syncedDeviceValues().isEmpty)
        complete(first)
        XCTAssertEqual(1, syncedDeviceValues().count)
    }

    func testOwnerMatchesSuppressValuesOnlyWhenCollectConsentIsYes() throws {
        for consent in [nil, "n", "p", "unknown", "y"] as [String?] {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            simulateCollectConsent(consent)
            mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Europe/London")
            mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                            data: (["pushidentifier": "push", "liveActivity": [
                                                "pushToStartTokens": ["A": ["token": "start"]],
                                                "updateTokens": ["1": ["token": "update"]]
                                            ]], .set))
            let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": [
                "pushNotification": "push",
                "liveActivityStart": [["attributeType": "A", "value": "start"]],
                "liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]
            ], "custom": "new"]
            let request = try XCTUnwrap(consequence(attributes, completeImmediately: false))
            var actual = request.data ?? [:]
            actual.removeValue(forKey: appKey)
            // Live Activity update tokens and custom values are never owner-held.
            let expected: [String: Any] = consent == "y"
                ? ["custom": "new", "tokens": ["liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]]]
                : attributes
            XCTAssertEqual(expected as NSDictionary, actual as NSDictionary)
            // With consent "y" the owner-held values are stored as confirmed right away.
            XCTAssertEqual(consent == "y" ? 3 : 0, syncedDeviceValues().count)
            complete(request)
            XCTAssertEqual(3, syncedDeviceValues().count)
        }
    }

    func testConfirmedBypassValuesSuppressDuplicatesAtEveryConsentState() throws {
        for consent in [nil, "n", "p", "unknown", "y"] as [String?] {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            simulateCollectConsent(consent)
            let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": [
                "pushNotification": "push",
                "liveActivityStart": [["attributeType": "A", "value": "start"]]
            ]]
            XCTAssertNotNil(consequence(attributes))
            XCTAssertEqual(3, syncedDeviceValues().count)
            XCTAssertNil(consequence(attributes))
            XCTAssertEqual(1, bypassEvents().count)
        }
    }

    func testEmptyPushTokenMatchingOwnerIsStillSentWithoutGrantedConsent() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": ""], .set))
        let attributes: [String: Any] = ["tokens": ["pushNotification": ""]]
        for consent in [nil, "n", "p"] as [String?] {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            simulateCollectConsent(consent)
            let request = try XCTUnwrap(consequence(attributes))
            XCTAssertEqual("", (request.data?["tokens"] as? [String: Any])?["pushNotification"] as? String)
            XCTAssertNil(consequence(attributes))
        }
        resetState()
        simulateCollectConsent("y")
        XCTAssertNil(consequence(attributes))
        XCTAssertEqual(["tokens": ["pushNotification": ""]] as NSDictionary, storedDeviceAttributes() as NSDictionary)
    }

    func testDisabledDedupSendsValuesMatchingBothConfirmedAndOwnerStores() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                        data: ([IdentityConstants.DeviceAttributes.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC: false], .set))
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push", "liveActivity": [
                                            "pushToStartTokens": ["A": ["token": "start"]],
                                            "updateTokens": ["1": ["token": "update"]]
                                        ]], .set))
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": [
            "pushNotification": "push",
            "liveActivityStart": [["attributeType": "A", "value": "start"]],
            "liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]
        ]]
        for consent in ["n", "y"] {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            simulateCollectConsent(consent)
            mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Europe/London")
            for _ in 0..<2 {
                let request = try XCTUnwrap(consequence(attributes))
                var actual = request.data ?? [:]
                actual.removeValue(forKey: appKey)
                XCTAssertEqual(attributes as NSDictionary, actual as NSDictionary)
                // Live Activity update tokens are never stored.
                XCTAssertEqual(3, syncedDeviceValues().count)
            }
            XCTAssertEqual(2, bypassEvents().count)
        }
    }

    func testPendingOrMalformedConsentDoesNotSuppressMatchingOwnerValues() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        let states: [([String: Any]?, SharedStateStatus)] = [
            (["consents": ["collect": ["val": "y"]]], .pending),
            (nil, .none),
            (["consents": ["collect": ["val": true]]], .set),
            (["consents": ["collect": "y"]], .set)
        ]
        for state in states {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            simulateRegisteredExtensions([IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME])
            mockRuntime.simulateXDMSharedState(for: IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME, data: state)
            let request = try XCTUnwrap(consequence(["tokens": ["pushNotification": "push"]]))
            XCTAssertEqual("push", (request.data?["tokens"] as? [String: Any])?["pushNotification"] as? String)
        }
    }

    func testQueuedConsequenceReadsConsentAtDequeueTime() throws {
        for (initial, latest) in [("y", "n"), ("n", "y")] {
            resetState()
            mockRuntime.resetDispatchedEventAndCreatedSharedStates()
            simulateCollectConsent(initial)
            mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                            data: (["pushidentifier": "push"], .set))
            let first = try XCTUnwrap(consequence(["custom": "first"], completeImmediately: false))
            XCTAssertNil(consequence(["tokens": ["pushNotification": "push"]], completeImmediately: false))
            simulateCollectConsent(latest)
            complete(first)
            XCTAssertEqual(latest == "y" ? 1 : 2, bypassEvents().count)
            if latest != "y" {
                let second = try XCTUnwrap(bypassEvents().last)
                XCTAssertEqual("push", (second.data?["tokens"] as? [String: Any])?["pushNotification"] as? String)
                complete(second)
            }
        }
    }

    func testChangedOwnerValuesAreSent() throws {
        simulateCollectConsent("y")
        mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Europe/London")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "old"], .set))
        let request = try XCTUnwrap(consequence(["timezone": "Asia/Kolkata", "tokens": ["pushNotification": "new"]]))
        XCTAssertEqual(["timezone", "tokens"], attributeKeys(request.data))
        XCTAssertEqual(2, syncedDeviceValues().count)
    }

    func testQueuedConsequenceReadsLatestMessagingAndTimezoneOwners() throws {
        simulateCollectConsent("y")
        let first = try XCTUnwrap(consequence(["custom": 1], completeImmediately: false))
        consequence(["timezone": "Europe/London", "tokens": ["pushNotification": "push"]], completeImmediately: false)
        mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Europe/London")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        complete(first)
        XCTAssertEqual(1, bypassEvents().count)
        // The timezone and push token are owner-held, so they are stored as confirmed; the custom value is never
        // stored.
        XCTAssertEqual(2, syncedDeviceValues().count)
        XCTAssertNotNil(consequence(["custom": 2]))
    }

    func testQueuedConsequenceReadsLatestDedupConfiguration() throws {
        let first = try XCTUnwrap(consequence(["timezone": "Europe/London"], completeImmediately: false))
        consequence(["timezone": "Europe/London"], completeImmediately: false)
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                        data: ([IdentityConstants.DeviceAttributes.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC: false], .set))
        complete(first)
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertEqual("Europe/London", bypassEvents().last?.data?["timezone"] as? String)
    }

    func testConsequencePayloadIsAuthoritativeAndEdgeRequestIsChained() throws {
        mockRuntime.simulateComingEvents(makeDeviceEvent(["timezone": "original", "notAllowed": "secret"]))
        let operational = try XCTUnwrap(operationalEvents().last)
        let response = operational.createChainedEvent(name: "Forward operational data",
                                                       type: EventType.edgeIdentity,
                                                       source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE,
                                                       data: ["timezone": "allowed", "app": ["id": "rules-app"]])
        mockRuntime.simulateComingEvents(response)
        let edge = try XCTUnwrap(bypassEvents().last)
        XCTAssertEqual(response.id, edge.parentID)
        XCTAssertNil(edge.responseID)
        XCTAssertEqual(["timezone"], attributeKeys(edge.data))
        XCTAssertEqual("allowed", edge.data?["timezone"] as? String)
        XCTAssertEqual(Bundle.main.bundleIdentifier, (edge.data?["app"] as? [String: Any])?["id"] as? String)
        complete(edge)
        XCTAssertEqual(1, syncedDeviceValues().count)
    }

    func testLiveActivityOwnerStateSuppressesOnlyMatchingArrays() throws {
        simulateCollectConsent("y")
        mockRuntime.simulateSharedState(
            for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
            data: (["liveActivity": [
                "pushToStartTokens": ["A": ["token": "start", "firstIssued": 1]],
                "updateTokens": ["1": ["token": "old", "attributeType": "A", "firstIssued": 1]]
            ]], .set))
        let edge = try XCTUnwrap(consequence(["tokens": [
            "liveActivityStart": [["attributeType": "A", "value": "start"]],
            "liveActivityUpdate": [["liveActivityID": "1", "token": "new"]]
        ]], completeImmediately: false))
        XCTAssertEqual(["liveActivityUpdate": [["liveActivityID": "1", "token": "new"]]] as NSDictionary,
                       edge.data?["tokens"] as? NSDictionary)
        XCTAssertEqual(1, syncedDeviceValues().count, "The matching start tokens are copied from the owner")
        complete(edge)
        XCTAssertEqual(1, syncedDeviceValues().count, "Live Activity update tokens are never stored")
    }

    func testQueuedRequestGeneratesAppFromLatestConfigurationAtSendTime() throws {
        let first = try XCTUnwrap(consequence(["timezone": "UTC"], completeImmediately: false))
        consequence(["timezone": "Asia/Tokyo", "app": ["id": "not-the-sdk-app", "platform": "apns"]], completeImmediately: false)
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                        data: ([IdentityConstants.DeviceAttributes.MESSAGING_USE_SANDBOX: true], .set))
        complete(first)
        let second = try XCTUnwrap(bypassEvents().last)
        XCTAssertNotEqual(first.id, second.id)
        let app = try XCTUnwrap(second.data?["app"] as? [String: Any])
        XCTAssertEqual(Bundle.main.bundleIdentifier, app["id"] as? String)
        XCTAssertEqual("apnsSandbox", app["platform"] as? String)
        XCTAssertEqual(1, syncedDeviceValues().count)
        complete(second)
        XCTAssertEqual(1, syncedDeviceValues().count, "App details are never written to the confirmed store")
    }

    // MARK: - Consent extension registration

    func testUnregisteredConsentExtensionIsTreatedAsYes() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        simulateRegisteredExtensions([IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME])

        XCTAssertNil(consequence(["tokens": ["pushNotification": "push"]]))
        XCTAssertTrue(bypassEvents().isEmpty)
    }

    func testRegisteredConsentExtensionWithoutValueIsNotYes() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        simulateRegisteredExtensions([IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                      IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME])

        XCTAssertNotNil(consequence(["tokens": ["pushNotification": "push"]]))
    }

    func testConsentIsNotYesBeforeEventHubPublishesExtensions() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        mockRuntime.simulateXDMSharedState(for: IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME,
                                           data: (["consents": ["collect": ["val": "y"]]], .set))

        XCTAssertNotNil(consequence(["tokens": ["pushNotification": "push"]]))
    }

    func testConsentExtensionWithEmptyHubEntryIsTreatedAsYes() throws {
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME,
                                        data: ([IdentityConstants.SharedState.Hub.EXTENSIONS: [
                                            IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME: [String: Any]()
                                        ]], .set))

        XCTAssertNil(consequence(["tokens": ["pushNotification": "push"]]))
    }

    // MARK: - Owner-held values are stored as confirmed and published

    /// Starts Identity on a runtime that records the event each standard shared state is published for.
    private func startRecordingIdentity() -> SharedStateEventRecorder {
        let recorder = SharedStateEventRecorder(mockRuntime)
        identity = Identity(runtime: recorder)
        identity.onRegistered()
        XCTAssertTrue(identity.readyForEvent(Event(name: "boot", type: "test-type", source: "test-source", data: nil)))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()
        recorder.sharedStateEvents.removeAll()
        return recorder
    }

    private func ruleResponse(_ data: [String: Any]) -> Event {
        return Event(name: "Forward operational data",
                     type: EventType.edgeIdentity,
                     source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE,
                     data: data)
    }

    func testOwnerMatchIsCommittedAndPublishedForTheRuleResponse() throws {
        simulateCollectConsent("y")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        let recorder = startRecordingIdentity()
        let response = ruleResponse(["tokens": ["pushNotification": "push"], "custom": "new"])

        mockRuntime.simulateComingEvents(response)

        let edge = try XCTUnwrap(bypassEvents().last)
        XCTAssertEqual(["custom"], attributeKeys(edge.data))
        XCTAssertEqual(["tokens": ["pushNotification": "push"]] as NSDictionary, storedDeviceAttributes() as NSDictionary)
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual(["tokens": ["pushNotification": "push"]] as NSDictionary,
                       lastProfileAttributesSharedState() as NSDictionary?)
        XCTAssertEqual([response.id], recorder.sharedStateEvents.map { $0?.id })
        XCTAssertTrue(syncResultEvents().isEmpty, "A partially deduplicated request only gets the Edge result")
    }

    func testOwnerMatchIsPublishedWhenEverythingIsDeduplicated() throws {
        simulateCollectConsent("y")
        mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Europe/London")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "push"], .set))
        let recorder = startRecordingIdentity()
        let response = ruleResponse(["timezone": "Europe/London", "tokens": ["pushNotification": "push"]])

        mockRuntime.simulateComingEvents(response)

        XCTAssertTrue(bypassEvents().isEmpty)
        let expected: [String: Any] = ["timezone": "Europe/London", "tokens": ["pushNotification": "push"]]
        XCTAssertEqual(expected as NSDictionary, storedDeviceAttributes() as NSDictionary)
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual(expected as NSDictionary, lastProfileAttributesSharedState() as NSDictionary?)
        XCTAssertEqual([response.id], recorder.sharedStateEvents.map { $0?.id })
        let syncResult = try XCTUnwrap(syncResultEvents().last)
        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertEqual(response.id, syncResult.parentID)
        XCTAssertEqual(["status": "success", "reason": "unchanged", "attributes": expected] as NSDictionary,
                       syncResult.data as NSDictionary?)

        // The owner-held values are now confirmed, so they are deduplicated whatever the consent.
        simulateCollectConsent("n")
        XCTAssertNil(consequence(["tokens": ["pushNotification": "push"]]))
        XCTAssertTrue(bypassEvents().isEmpty)
    }

    func testNoOwnerMatchDoesNotPublishBeforeEdgeResponse() throws {
        simulateCollectConsent("y")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "other"], .set))

        let edge = try XCTUnwrap(consequence(["tokens": ["pushNotification": "push"]], completeImmediately: false))

        XCTAssertTrue(storedDeviceAttributes().isEmpty)
        XCTAssertTrue(mockRuntime.createdSharedStates.isEmpty)
        complete(edge)
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
    }

    // MARK: - Result events for requests that are not sent to Edge

    private func resetEvent() -> Event {
        return Event(name: "Reset", type: EventType.genericIdentity, source: EventSource.requestReset, data: nil)
    }

    func testAllValuesSyncedDispatchesUnchangedResult() throws {
        DeviceAttributeDeduplicator(storeName: deviceStore).commit(["timezone": "Europe/London", "tokens": ["pushNotification": "push"]])
        startIdentity()
        let response = ruleResponse(["timezone": "Europe/London", "tokens": ["pushNotification": "push"], "app": ["id": "rules-app"]])

        mockRuntime.simulateComingEvents(response)

        XCTAssertTrue(bypassEvents().isEmpty)
        let syncResult = try XCTUnwrap(syncResultEvents().last)
        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertEqual(EventType.edgeIdentity, syncResult.type)
        XCTAssertEqual(EventSource.responseContent, syncResult.source)
        XCTAssertEqual(response.id, syncResult.parentID)
        XCTAssertEqual(["status": "success", "reason": "unchanged",
                        "attributes": ["timezone": "Europe/London", "tokens": ["pushNotification": "push"]]] as NSDictionary,
                       syncResult.data as NSDictionary?)
    }

    func testPartialDedupSendsEdgeRequestWithoutUnchangedResult() throws {
        DeviceAttributeDeduplicator(storeName: deviceStore).commit(["timezone": "Europe/London"])
        startIdentity()

        let edge = try XCTUnwrap(consequence(["timezone": "Europe/London", "custom": "new"], completeImmediately: false))

        XCTAssertEqual(["custom"], attributeKeys(edge.data))
        XCTAssertTrue(syncResultEvents().isEmpty)
        complete(edge)
        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertEqual("success", syncResultEvents().last?.data?["status"] as? String)
        XCTAssertEqual("", syncResultEvents().last?.data?["reason"] as? String)
    }

    func testResetDispatchesFailedResultsForActiveAndQueuedRequests() throws {
        let active = try XCTUnwrap(consequence(["custom": 1], completeImmediately: false))
        let first = ruleResponse(["custom": 2, "app": ["id": "rules-app"]])
        let second = ruleResponse(["timezone": "Asia/Kolkata"])
        mockRuntime.simulateComingEvents(first)
        mockRuntime.simulateComingEvents(second)
        XCTAssertEqual(1, bypassEvents().count)

        mockRuntime.simulateComingEvents(resetEvent())

        let results = syncResultEvents()
        XCTAssertEqual(3, results.count)
        XCTAssertEqual([active.id, first.id, second.id], results.map { $0.parentID })
        let expectedAttributes: [[String: Any]] = [["custom": 1], ["custom": 2], ["timezone": "Asia/Kolkata"]]
        for (result, attributes) in zip(results, expectedAttributes) {
            XCTAssertEqual(["status": "failed", "reason": "identityReset", "attributes": attributes] as NSDictionary,
                           result.data as NSDictionary?)
        }
        XCTAssertEqual(1, bypassEvents().count, "Dropped requests are never sent")

        complete(active)
        XCTAssertEqual(3, syncResultEvents().count, "A late Edge result for the dropped request is ignored")
        XCTAssertTrue(syncedDeviceValues().isEmpty)
    }

    func testResetWithNothingPendingDispatchesNoResult() {
        XCTAssertNotNil(consequence(["custom": 1]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(resetEvent())

        XCTAssertTrue(syncResultEvents().isEmpty)
    }

    // MARK: - Device attributes confirmed event for Messaging

    func testSuccessWithTokensDispatchesTokensConfirmedAfterPublishAndBeforeSyncResult() throws {
        let recorder = startRecordingIdentity()
        let edge = try XCTUnwrap(consequence(["timezone": "Europe/London", "tokens": ["pushNotification": "token"]],
                                             completeImmediately: false))

        let response = complete(edge)

        let confirmed = try XCTUnwrap(tokensConfirmedEvents().last)
        XCTAssertEqual(1, tokensConfirmedEvents().count)
        XCTAssertEqual("Device attributes confirmed", confirmed.name)
        XCTAssertEqual(EventType.messaging, confirmed.type)
        XCTAssertEqual(EventSource.responseContent, confirmed.source)
        XCTAssertEqual(response.id, confirmed.parentID)
        XCTAssertEqual(["tokens": ["pushNotification": "token"]] as NSDictionary, confirmed.data as NSDictionary?)
        XCTAssertEqual(["sharedState", "Device attributes confirmed", "Device Attributes Sync Result"],
                       recorder.trace.suffix(3))
    }

    func testSuccessWithoutTokensDoesNotDispatchTokensConfirmed() {
        XCTAssertNotNil(consequence(["timezone": "Europe/London"]))

        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertTrue(tokensConfirmedEvents().isEmpty)
    }

    func testFailureWithTokensDoesNotDispatchTokensConfirmed() throws {
        let edge = try XCTUnwrap(consequence(["tokens": ["pushNotification": "token"]], completeImmediately: false))

        complete(edge, status: "failed")

        XCTAssertEqual("failed", syncResultEvents().last?.data?["status"] as? String)
        XCTAssertTrue(tokensConfirmedEvents().isEmpty)
    }

    func testOwnerMatchedTokenWithEverythingDeduplicatedDoesNotDispatchTokensConfirmed() {
        simulateCollectConsent("y")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["pushidentifier": "token"], .set))
        startIdentity()

        mockRuntime.simulateComingEvents(ruleResponse(["tokens": ["pushNotification": "token"]]))

        XCTAssertTrue(bypassEvents().isEmpty)
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual("unchanged", syncResultEvents().last?.data?["reason"] as? String)
        XCTAssertTrue(tokensConfirmedEvents().isEmpty)
    }

    func testResetWithPendingTokenRequestDoesNotDispatchTokensConfirmed() throws {
        let edge = try XCTUnwrap(consequence(["tokens": ["pushNotification": "token"]], completeImmediately: false))

        mockRuntime.simulateComingEvents(resetEvent())
        complete(edge)

        XCTAssertEqual("identityReset", syncResultEvents().last?.data?["reason"] as? String)
        XCTAssertTrue(tokensConfirmedEvents().isEmpty)
    }

    func testPartialDedupDispatchesOnlyTheSentTokens() throws {
        DeviceAttributeDeduplicator(storeName: deviceStore).commit(["tokens": ["pushNotification": "token"]])
        startIdentity()

        XCTAssertNotNil(consequence(["timezone": "Europe/London",
                                     "tokens": ["pushNotification": "token", "otherToken": "new"]]))

        XCTAssertEqual(["tokens": ["otherToken": "new"]] as NSDictionary,
                       tokensConfirmedEvents().last?.data as NSDictionary?)
    }

    func testLiveActivityTokensAreIncludedInTokensConfirmed() {
        let tokens: [String: Any] = [
            "liveActivityStart": [["attributeType": "A", "value": "start"]],
            "liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]
        ]

        XCTAssertNotNil(consequence(["tokens": tokens]))

        XCTAssertEqual(1, tokensConfirmedEvents().count)
        XCTAssertEqual(["tokens": tokens] as NSDictionary, tokensConfirmedEvents().last?.data as NSDictionary?)
    }

    // MARK: - Shared state

    func testDeviceAttributesArePublishedInStandardSharedStateOnly() throws {
        mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Asia/Kolkata")
        XCTAssertNotNil(consequence(["tokens": ["pushNotification": "push"], "custom": ["nested": true]]))

        // Values outside the deduplicated paths are not stored, so they are not published.
        XCTAssertEqual(["timezone": "Asia/Kolkata",
                        "tokens": ["pushNotification": "push"]] as NSDictionary,
                       lastProfileAttributesSharedState() as NSDictionary?)
        // The XDM shared state is unchanged by the device attributes API.
        XCTAssertTrue(mockRuntime.createdXdmSharedStates.isEmpty)
    }

    func testBootupPublishesPersistedProfileAttributes() {
        DeviceAttributeDeduplicator(storeName: deviceStore).commit(["tokens": ["pushNotification": "push"]])
        mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Asia/Kolkata")
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()

        // The standard shared state is published once, at registration.
        XCTAssertEqual(1, mockRuntime.createdSharedStates.count)
        XCTAssertEqual(["timezone": "Asia/Kolkata", "tokens": ["pushNotification": "push"]] as NSDictionary,
                       lastProfileAttributesSharedState() as NSDictionary?)
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        XCTAssertTrue(identity.readyForEvent(Event(name: "boot", type: "test-type", source: "test-source", data: nil)))

        XCTAssertTrue(mockRuntime.createdSharedStates.isEmpty)
        let xdm = mockRuntime.createdXdmSharedStates.last ?? nil
        XCTAssertNotNil(xdm?[IdentityConstants.XDMKeys.IDENTITY_MAP])
        // As released: the XDM shared state holds only the profile attributes timezone, never the device attributes.
        XCTAssertEqual(["timeZone": "Asia/Kolkata"] as NSDictionary,
                       xdm?[IdentityConstants.XDMKeys.PROFILE_ATTRIBUTES] as? NSDictionary)
    }

    func testRegistrationWithNothingStoredDoesNotPublish() {
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()

        XCTAssertTrue(mockRuntime.createdSharedStates.isEmpty)
    }

    func testResetPublishesEmptyProfileAttributes() {
        mockDataStore.set(collectionName: profileStore, key: timeZoneKey, value: "Asia/Kolkata")
        XCTAssertNotNil(consequence(["custom": 1]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(Event(name: "Reset", type: EventType.genericIdentity,
                                               source: EventSource.requestReset, data: nil))

        XCTAssertEqual([:] as NSDictionary, lastProfileAttributesSharedState() as NSDictionary?)
        XCTAssertNil(mockDataStore.get(collectionName: profileStore, key: timeZoneKey))
    }

    // MARK: - Deduplicated paths

    func testCustomValueIsSentEveryTimeAndNeverStoredOrPublished() throws {
        simulateCollectConsent("y")
        for _ in 0..<2 {
            let request = try XCTUnwrap(consequence(["custom": ["nested": true]]))
            XCTAssertEqual(["nested": true] as NSDictionary, request.data?["custom"] as? NSDictionary)
        }
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertTrue(storedDeviceAttributes().isEmpty)
        XCTAssertNil(lastProfileAttributesSharedState()?["custom"])
    }

    func testLiveActivityUpdateTokensAreSentEveryTimeAndNeverStoredOrOwnerMatched() throws {
        simulateCollectConsent("y")
        mockRuntime.simulateSharedState(for: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                                        data: (["liveActivity": ["updateTokens": ["1": ["token": "update"]]]], .set))
        let tokens: [String: Any] = ["liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]]
        for _ in 0..<2 {
            let request = try XCTUnwrap(consequence(["tokens": tokens]))
            XCTAssertEqual(tokens as NSDictionary, request.data?["tokens"] as? NSDictionary)
        }
        XCTAssertEqual(2, bypassEvents().count)
        XCTAssertTrue(storedDeviceAttributes().isEmpty)
    }

    func testMixedRequestSendsOnlyValuesThatAreNotDeduplicated() throws {
        XCTAssertNotNil(consequence(["timezone": "Europe/London"]))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        let request = try XCTUnwrap(consequence(["timezone": "Europe/London", "custom": "value"]))

        XCTAssertEqual(["custom"], attributeKeys(request.data))
        if Bundle.main.bundleIdentifier != nil {
            XCTAssertNotNil(request.data?[appKey])
        }
        XCTAssertEqual(1, syncResultEvents().count)
        XCTAssertEqual(["status": "success", "reason": "", "attributes": ["custom": "value"]] as NSDictionary,
                       syncResultEvents().last?.data as NSDictionary?)
        XCTAssertEqual(["timezone": "Europe/London"] as NSDictionary, storedDeviceAttributes() as NSDictionary)
    }

    func testUnknownTokenIsSentWhileSyncedPushTokenIsDeduplicated() throws {
        XCTAssertNotNil(consequence(["tokens": ["pushNotification": "push"]]))

        let request = try XCTUnwrap(consequence(["tokens": ["pushNotification": "push", "foo": "bar"]]))

        XCTAssertEqual(["foo": "bar"] as NSDictionary, request.data?["tokens"] as? NSDictionary)
        XCTAssertEqual(["tokens": ["pushNotification": "push"]] as NSDictionary, storedDeviceAttributes() as NSDictionary)
    }

    // MARK: - Clear Live Activities

    private func clearLiveActivitiesEvent(_ data: [String: Any]?) -> Event {
        return Event(name: "Clear Live Activities", type: EventType.messaging, source: EventSource.requestContent, data: data)
    }

    func testClearLiveActivitiesRemovesLiveActivityTokensAndRepublishes() throws {
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": [
            "pushNotification": "push",
            "liveActivityStart": [["attributeType": "A", "value": "start"]],
            "liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]
        ]]
        XCTAssertNotNil(consequence(attributes))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(clearLiveActivitiesEvent(["isClearLiveActivitiesEvent": true]))

        let expected: [String: Any] = ["timezone": "Europe/London", "tokens": ["pushNotification": "push"]]
        XCTAssertEqual(expected as NSDictionary, storedDeviceAttributes() as NSDictionary)
        XCTAssertEqual(expected as NSDictionary, lastProfileAttributesSharedState() as NSDictionary?)
        // Cleared tokens are sent again.
        XCTAssertNotNil(consequence(attributes))
        XCTAssertEqual(["liveActivityStart", "liveActivityUpdate"],
                       Set((bypassEvents().last?.data?["tokens"] as? [String: Any] ?? [:]).keys))
    }

    func testOtherMessagingRequestsDoNotClearLiveActivityTokens() throws {
        let attributes: [String: Any] = ["tokens": ["liveActivityStart": [["attributeType": "A", "value": "start"]]]]
        XCTAssertNotNil(consequence(attributes))
        mockRuntime.resetDispatchedEventAndCreatedSharedStates()

        mockRuntime.simulateComingEvents(clearLiveActivitiesEvent(nil),
                                         clearLiveActivitiesEvent(["isClearLiveActivitiesEvent": false]),
                                         clearLiveActivitiesEvent(["refreshInAppMessages": true]))

        XCTAssertEqual(attributes as NSDictionary, storedDeviceAttributes() as NSDictionary)
        XCTAssertTrue(mockRuntime.createdSharedStates.isEmpty)
    }
}

/// Forwards to a `TestableExtensionRuntime` and records the event each standard shared state is created for.
private final class SharedStateEventRecorder: ExtensionRuntime {
    private let runtime: TestableExtensionRuntime
    var sharedStateEvents: [Event?] = []
    /// Dispatched event names and "sharedState" for each standard shared state, in call order.
    var trace: [String] = []

    init(_ runtime: TestableExtensionRuntime) {
        self.runtime = runtime
    }

    func unregisterExtension() { runtime.unregisterExtension() }
    func registerListener(type: String, source: String, listener: @escaping EventListener) {
        runtime.registerListener(type: type, source: source, listener: listener)
    }
    func startEvents() { runtime.startEvents() }
    func stopEvents() { runtime.stopEvents() }
    func dispatch(event: Event) {
        trace.append(event.name)
        runtime.dispatch(event: event)
    }
    func createSharedState(data: [String: Any], event: Event?) {
        sharedStateEvents.append(event)
        trace.append("sharedState")
        runtime.createSharedState(data: data, event: event)
    }
    func createPendingSharedState(event: Event?) -> SharedStateResolver {
        return runtime.createPendingSharedState(event: event)
    }
    func getSharedState(extensionName: String, event: Event?, barrier: Bool) -> SharedStateResult? {
        return runtime.getSharedState(extensionName: extensionName, event: event, barrier: barrier)
    }
    func getSharedState(extensionName: String, event: Event?, barrier: Bool, resolution: SharedStateResolution) -> SharedStateResult? {
        return runtime.getSharedState(extensionName: extensionName, event: event, barrier: barrier, resolution: resolution)
    }
    func createXDMSharedState(data: [String: Any], event: Event?) {
        runtime.createXDMSharedState(data: data, event: event)
    }
    func createPendingXDMSharedState(event: Event?) -> SharedStateResolver {
        return runtime.createPendingXDMSharedState(event: event)
    }
    func getXDMSharedState(extensionName: String, event: Event?, barrier: Bool) -> SharedStateResult? {
        return runtime.getXDMSharedState(extensionName: extensionName, event: event, barrier: barrier)
    }
    func getXDMSharedState(extensionName: String, event: Event?, barrier: Bool, resolution: SharedStateResolution) -> SharedStateResult? {
        return runtime.getXDMSharedState(extensionName: extensionName, event: event, barrier: barrier, resolution: resolution)
    }
    func getHistoricalEvents(_ requests: [EventHistoryRequest], enforceOrder: Bool, handler: @escaping ([EventHistoryResult]) -> Void) {
        runtime.getHistoricalEvents(requests, enforceOrder: enforceOrder, handler: handler)
    }
    func recordHistoricalEvent(_ event: Event, handler: ((Bool) -> Void)?) {
        runtime.recordHistoricalEvent(event, handler: handler)
    }
}
