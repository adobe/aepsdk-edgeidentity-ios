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

/// Verifies the `AttributeHandler` key-routing contract: `operationalDataKey` defaults to `attributeKey`
/// and can diverge, and that a handler whose two keys are identical stores/emits correctly (no clobbering).
class AttributeHandlerRoutingTests: XCTestCase {

    private let store = IdentityConstants.Store.DEVICE_ATTRIBUTES
    private var mockDataStore: CollectionAwareMockDataStore!

    override func setUp() {
        mockDataStore = CollectionAwareMockDataStore()
        ServiceProvider.shared.namedKeyValueService = mockDataStore
    }

    // Test-only handler that does NOT override operationalDataKey, so attributeKey == operationalDataKey
    // via the protocol default extension.
    private struct SameKeyHandler: AttributeHandler {
        static let key = "sameKey"
        var attributeKey: String { SameKeyHandler.key }
        let storeName: String

        func collectFromEvent(_ event: Event, dedup: Bool) -> [String: String]? {
            guard let value = event.data?[attributeKey] as? String, !value.isEmpty else { return nil }
            if dedup,
               ServiceProvider.shared.namedKeyValueService.get(collectionName: storeName, key: attributeKey) as? String == value {
                return nil
            }
            ServiceProvider.shared.namedKeyValueService.set(collectionName: storeName, key: attributeKey, value: value)
            return [attributeKey: value]
        }

        func collectFromStorage() -> [String: String]? {
            guard let stored = ServiceProvider.shared.namedKeyValueService.get(collectionName: storeName, key: attributeKey) as? String else { return nil }
            return [attributeKey: stored]
        }
    }

    // MARK: - operationalDataKey default / override

    func testOperationalDataKey_defaultsToAttributeKey_whenNotOverridden() {
        let handler = SameKeyHandler(storeName: store)
        XCTAssertEqual(handler.attributeKey, handler.operationalDataKey)
    }

    func testOperationalDataKey_overriddenHandlers_differFromAttributeKey() {
        let timeZone = TimeZoneAttributeHandler(storeName: store)
        XCTAssertEqual("timeZone", timeZone.attributeKey)
        XCTAssertEqual("timezone", timeZone.operationalDataKey)
        XCTAssertNotEqual(timeZone.attributeKey, timeZone.operationalDataKey)

        let push = PushTokenAttributeHandler(storeName: store)
        XCTAssertEqual("pushidentifier", push.attributeKey)
        XCTAssertEqual("pushNotification", push.operationalDataKey)
        XCTAssertNotEqual(push.attributeKey, push.operationalDataKey)
    }

    // MARK: - same-key routing (no dictionary clobbering)

    func testSameKeyHandler_storesUnderAttributeKey_andEmitsUnderOperationalKey() {
        let handler = SameKeyHandler(storeName: store)
        let event = Event(name: "test", type: EventType.edgeIdentity, source: EventSource.requestContent,
                          data: [SameKeyHandler.key: "value-1"])

        let contribution = handler.collectFromEvent(event, dedup: true)

        // Contribution keyed by attributeKey.
        XCTAssertEqual([SameKeyHandler.key: "value-1"], contribution)
        // Because attributeKey == operationalDataKey, the operational payload key is the same string —
        // building payload[operationalDataKey] = contribution[attributeKey] round-trips without loss.
        let payloadKey = handler.operationalDataKey
        XCTAssertEqual("value-1", contribution?[handler.attributeKey])
        XCTAssertEqual(handler.attributeKey, payloadKey)
        // Persisted under attributeKey in the injected store.
        XCTAssertEqual("value-1", mockDataStore.get(collectionName: store, key: SameKeyHandler.key) as? String)
    }

    func testSameKeyHandler_dedupSuppressesUnchanged_andBypassesWhenDedupFalse() {
        let handler = SameKeyHandler(storeName: store)
        let event = Event(name: "test", type: EventType.edgeIdentity, source: EventSource.requestContent,
                          data: [SameKeyHandler.key: "value-1"])

        XCTAssertNotNil(handler.collectFromEvent(event, dedup: true))
        // Unchanged with dedup on -> suppressed.
        XCTAssertNil(handler.collectFromEvent(event, dedup: true))
        // Unchanged with dedup off -> still returns.
        XCTAssertNotNil(handler.collectFromEvent(event, dedup: false))
    }
}
