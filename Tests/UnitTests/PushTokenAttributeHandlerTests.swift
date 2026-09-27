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

class PushTokenAttributeHandlerTests: XCTestCase {

    // Must mirror PushTokenAttributeHandler.key — used for event input and persistence.
    private let key = PushTokenAttributeHandler.key
    // The store injected into the handler under test (the device-attributes store).
    private let store = IdentityConstants.Store.DEVICE_ATTRIBUTES

    var handler: PushTokenAttributeHandler!
    // Collection-aware so the injected store namespace is honored (the shared MockDataStore is flat).
    var mockDataStore: CollectionAwareMockDataStore!

    override func setUp() {
        mockDataStore = CollectionAwareMockDataStore()
        ServiceProvider.shared.namedKeyValueService = mockDataStore
        handler = PushTokenAttributeHandler(storeName: store)
    }

    // MARK: - attributeKey / operationalDataKey / storeName

    func testAttributeKey_returnsPushIdentifierKey() {
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PUSH_IDENTIFIER, handler.attributeKey)
    }

    func testOperationalDataKey_returnsPushNotificationToken() {
        XCTAssertEqual(IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION, handler.operationalDataKey)
    }

    func testStoreName_returnsInjectedStore() {
        XCTAssertEqual(store, handler.storeName)
    }

    // MARK: - collectFromEvent (dedup: true)

    func testCollectFromEvent_whenNewValue_persistsAndReturnsContribution() {
        let result = handler.collectFromEvent(makeEvent("token-abc"), dedup: true)

        XCTAssertEqual([key: "token-abc"], result)
        XCTAssertEqual("token-abc", storedToken())
    }

    func testCollectFromEvent_whenUnchanged_returnsNil() {
        storeToken("token-abc")

        let result = handler.collectFromEvent(makeEvent("token-abc"), dedup: true)

        XCTAssertNil(result)
    }

    func testCollectFromEvent_whenDifferent_persistsNewValueAndReturnsContribution() {
        storeToken("token-old")

        let result = handler.collectFromEvent(makeEvent("token-new"), dedup: true)

        XCTAssertEqual([key: "token-new"], result)
        XCTAssertEqual("token-new", storedToken())
    }

    func testCollectFromEvent_whenEmpty_returnsNilAndDoesNotPersist() {
        let result = handler.collectFromEvent(makeEvent(""), dedup: true)

        XCTAssertNil(result)
        XCTAssertNil(storedToken())
    }

    func testCollectFromEvent_whenKeyAbsent_returnsNil() {
        let event = Event(name: IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestContent,
                          data: ["otherKey": "value"])

        let result = handler.collectFromEvent(event, dedup: true)

        XCTAssertNil(result)
    }

    func testCollectFromEvent_whenNilEventData_returnsNil() {
        let event = Event(name: IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestContent,
                          data: nil)

        let result = handler.collectFromEvent(event, dedup: true)

        XCTAssertNil(result)
    }

    // MARK: - collectFromEvent (dedup: false)

    func testCollectFromEvent_dedupFalse_whenUnchanged_stillReturnsContribution() {
        storeToken("token-abc")

        let result = handler.collectFromEvent(makeEvent("token-abc"), dedup: false)

        XCTAssertEqual([key: "token-abc"], result)
    }

    func testCollectFromEvent_dedupFalse_stillIgnoresEmpty() {
        let result = handler.collectFromEvent(makeEvent(""), dedup: false)

        XCTAssertNil(result)
        XCTAssertNil(storedToken())
    }

    // MARK: - store isolation

    func testCollectFromEvent_readsAndWritesInjectedStore() {
        _ = handler.collectFromEvent(makeEvent("token-abc"), dedup: true)

        // Written to the injected device store, not the profile store.
        XCTAssertEqual("token-abc", mockDataStore.get(collectionName: store, key: key) as? String)
        XCTAssertNil(mockDataStore.get(collectionName: IdentityConstants.Store.PROFILE_ATTRIBUTES, key: key) as? String)
    }

    // MARK: - collectFromStorage

    func testCollectFromStorage_whenStored_returnsContribution() {
        storeToken("token-xyz")

        let result = handler.collectFromStorage()

        XCTAssertEqual([key: "token-xyz"], result)
    }

    func testCollectFromStorage_whenNothingStored_returnsNil() {
        let result = handler.collectFromStorage()

        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func makeEvent(_ token: String) -> Event {
        return Event(name: IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES,
                     type: EventType.edgeIdentity,
                     source: EventSource.requestContent,
                     data: [key: token])
    }

    private func storeToken(_ token: String) {
        mockDataStore.set(collectionName: store, key: key, value: token)
    }

    private func storedToken() -> String? {
        return mockDataStore.get(collectionName: store, key: key) as? String
    }
}
