// Copyright 2026 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.

@testable import AEPEdgeIdentity
@testable import AEPServices
import XCTest

class DeviceAttributeDeduplicatorTests: XCTestCase {
    private var store: CollectionAwareMockDataStore!
    private var deduplicator: DeviceAttributeDeduplicator!
    private let storeName = IdentityConstants.DataStoreKeys.DEVICE_ATTRIBUTES_DATASTORE_NAME

    override func setUp() {
        super.setUp()
        store = CollectionAwareMockDataStore()
        ServiceProvider.shared.namedKeyValueService = store
        deduplicator = DeviceAttributeDeduplicator(storeName: storeName)
    }

    override func tearDown() {
        ServiceProvider.shared.reset()
        super.tearDown()
    }

    private func persisted() -> Any? {
        return store.get(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES)
    }

    private func reloaded() -> DeviceAttributeDeduplicator {
        return DeviceAttributeDeduplicator(storeName: storeName)
    }

    func testFilterDoesNotWriteUntilCommit() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: true, owners: nil).changed as NSDictionary)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: true, owners: nil).changed as NSDictionary)
        XCTAssertNil(persisted())
        deduplicator.commit(attributes)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, owners: nil).changed.isEmpty)
        XCTAssertEqual(attributes as NSDictionary, reloaded().readSynced() as NSDictionary)
    }

    func testNestedAttributesAreDeduplicatedIndependently() {
        deduplicator.commit(["custom": ["a": "old", "b": "same"]])
        XCTAssertEqual(["custom": ["a": "new"]] as NSDictionary,
                       deduplicator.filter(["custom": ["a": "new", "b": "same"]], dedup: true, owners: nil).changed as NSDictionary)
    }

    func testFilteredPayloadDoesNotRetainMutableValues() {
        let values = NSMutableArray(array: [NSMutableDictionary(dictionary: ["value": "original"])])
        let attributes: [String: Any] = ["custom": values]
        let payload = deduplicator.filter(attributes, dedup: true, owners: nil).changed
        values.removeAllObjects()
        XCTAssertEqual(["custom": [["value": "original"]]] as NSDictionary, payload as NSDictionary)
        deduplicator.commit(payload)
        XCTAssertTrue(deduplicator.filter(payload, dedup: true, owners: nil).changed.isEmpty)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: true, owners: nil).changed as NSDictionary)
    }

    func testCommitDoesNotRetainMutableValues() {
        let values = NSMutableArray(array: ["original"])
        deduplicator.commit(["custom": values])
        values.removeAllObjects()
        XCTAssertEqual(["custom": ["original"]] as NSDictionary, deduplicator.readSynced() as NSDictionary)
    }

    func testOwnerMatchesAreReturnedSeparatelyAndNotCommitted() {
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": ["pushNotification": "push"]]
        let owners: [String: Any] = ["timezone": "Europe/London", "tokens": ["pushNotification": "other"]]
        let result = deduplicator.filter(attributes, dedup: true, owners: owners)
        XCTAssertEqual(["tokens": ["pushNotification": "push"]] as NSDictionary, result.changed as NSDictionary)
        XCTAssertEqual(["timezone": "Europe/London"] as NSDictionary, result.ownerMatches as NSDictionary)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
        XCTAssertNil(persisted())
    }

    func testOwnerMatchesAreEmptyWithoutOwnersOrWhenDedupIsDisabled() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, owners: nil).ownerMatches.isEmpty)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: false, owners: attributes).ownerMatches.isEmpty)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, owners: ["timezone": "Asia/Tokyo"]).ownerMatches.isEmpty)
    }

    func testDisabledDedupIgnoresSyncedAndOwnerValues() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        deduplicator.commit(attributes)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: false, owners: attributes).changed as NSDictionary)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.readSynced() as NSDictionary)
    }

    func testEmptyPushTokenIsPreservedAndComparedAsAString() {
        let attributes: [String: Any] = ["tokens": ["pushNotification": ""]]
        XCTAssertEqual(attributes as NSDictionary,
                       deduplicator.filter(attributes, dedup: true, owners: ["tokens": ["pushNotification": "previous"]]).changed as NSDictionary)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: true, owners: nil).changed as NSDictionary)
        deduplicator.commit(attributes)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, owners: nil).changed.isEmpty)
    }

    func testNullIsDroppedButEmptyContainersAreValues() {
        let attributes: [String: Any] = ["null": NSNull(), "array": [Any](), "object": [String: Any]()]
        let expected: [String: Any] = ["array": [Any](), "object": [String: Any]()]
        let changed = deduplicator.filter(attributes, dedup: false, owners: nil).changed
        XCTAssertEqual(expected as NSDictionary, changed as NSDictionary)
        deduplicator.commit(changed)
        XCTAssertEqual(expected as NSDictionary, deduplicator.readSynced() as NSDictionary)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, owners: nil).changed.isEmpty)
    }

    func testInvalidJSONLeavesAreDroppedWithoutWritingStorage() {
        let nested: [String: Any] = ["valid": "value", "null": NSNull(), "invalid": Date()]
        XCTAssertEqual(["nested": ["valid": "value"]] as NSDictionary,
                       deduplicator.filter(["nested": nested, "nan": Double.nan], dedup: false, owners: nil).changed as NSDictionary)
        XCTAssertNil(persisted())
    }

    func testArraysAreComparedAsSets() {
        deduplicator.commit(["array": ["first", "second"]])
        XCTAssertTrue(deduplicator.filter(["array": ["second", "first"]], dedup: true, owners: nil).changed.isEmpty)
        XCTAssertTrue(deduplicator.filter(["array": NSArray(array: ["second", "first"])], dedup: true, owners: nil).changed.isEmpty)
        XCTAssertEqual(["array": ["first"]] as NSDictionary,
                       deduplicator.filter(["array": ["first"]], dedup: true, owners: nil).changed as NSDictionary)
        XCTAssertEqual(["array": ["first", NSNull()]] as NSDictionary,
                       deduplicator.filter(["array": ["first", NSNull()]], dedup: true, owners: nil).changed as NSDictionary)
        deduplicator.commit(["nested": [["x", "y"], ["z"]]])
        XCTAssertTrue(deduplicator.filter(["nested": [["z", "z"], ["y", "x", "x"]]], dedup: true, owners: nil).changed.isEmpty)
    }

    func testCommitDeepMergesMapsAndReplacesOtherValues() {
        deduplicator.commit(["prefs": ["lang": "en", "theme": "dark"], "tags": ["a"]])
        deduplicator.commit(["prefs": ["lang": "fr"]])
        XCTAssertEqual(["prefs": ["lang": "fr", "theme": "dark"], "tags": ["a"]] as NSDictionary,
                       deduplicator.readSynced() as NSDictionary)
        deduplicator.commit(["prefs": [String: Any](), "tags": ["x": 1]])
        XCTAssertEqual(["prefs": [String: Any](), "tags": ["x": 1]] as NSDictionary, deduplicator.readSynced() as NSDictionary)
        deduplicator.commit(["prefs": "off"])
        XCTAssertEqual(["prefs": "off", "tags": ["x": 1]] as NSDictionary, reloaded().readSynced() as NSDictionary)
    }

    func testBooleansRemainDistinctFromNumbersAndNumbersSurviveSnapshots() {
        deduplicator.commit(["value": true])
        XCTAssertEqual(["value": 1] as NSDictionary, deduplicator.filter(["value": 1], dedup: true, owners: nil).changed as NSDictionary)
        deduplicator.commit(deduplicator.filter(["value": 1.0], dedup: true, owners: nil).changed)
        XCTAssertTrue(deduplicator.filter(["value": 1.0], dedup: true, owners: nil).changed.isEmpty)
        XCTAssertTrue(reloaded().filter(["value": 1.0], dedup: true, owners: nil).changed.isEmpty)
    }

    func testClearRemovesOnlyConfirmedDeviceValues() {
        store.set(collectionName: storeName, key: "other", value: "kept")
        deduplicator.commit(["timezone": "Europe/London"])
        deduplicator.clear()
        XCTAssertNil(persisted())
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
        XCTAssertEqual("kept", store.get(collectionName: storeName, key: "other") as? String)
    }

    func testCanonicalization_isIndependentOfMapKeyOrder() {
        let firstNestedValue: [String: Any] = ["b": 2, "a": 1]
        XCTAssertEqual("{\"a\":1,\"b\":2}", DeviceAttributeDeduplicator.canonicalize(firstNestedValue))
        XCTAssertEqual(DeviceAttributeDeduplicator.canonicalize(firstNestedValue),
                       DeviceAttributeDeduplicator.canonicalize(["a": 1, "b": 2]))
    }

    func testCanonicalization_rejectsUnsupportedValuesAndTopLevelNull() {
        let nonStringKey: [AnyHashable: Any] = [1: "invalid-key"]
        XCTAssertNil(DeviceAttributeDeduplicator.canonicalize(nonStringKey))
        XCTAssertNil(DeviceAttributeDeduplicator.canonicalize(Date()))
        XCTAssertNil(DeviceAttributeDeduplicator.canonicalize(Double.nan))
        XCTAssertNil(DeviceAttributeDeduplicator.canonicalize(nil))
        XCTAssertNil(DeviceAttributeDeduplicator.canonicalize(NSNull()))
        XCTAssertEqual("{\"value\":null}", DeviceAttributeDeduplicator.canonicalize(["value": NSNull()]))
    }

    // Shared canonicalize cases: keep in sync with the Android DeviceAttributeDeduplicator tests.

    func testCanonicalization_sharedEqualCases() {
        let reorderedKeys = NSMutableDictionary()
        reorderedKeys["b"] = 2
        reorderedKeys["a"] = 1
        let equalPairs: [(Any, Any)] = [
            (1, 1.0),
            (0, -0.0),
            (Int64(5), Float(5.0)),
            ("a", "a"),
            (reorderedKeys, ["a": 1, "b": 2]),
            (["a", "b"], ["b", "a"]),
            (["a", "a", "b"], ["b", "a"]),
            ([["x", "y"], ["z"]], [["z"], ["y", "x"]]),
            (["k": [1, [2, 3, 3]]], ["k": [[3, 2], 1.0]]),
            ([["a": 1], ["b": 2]], [["b": 2], ["a": 1]])
        ]
        for (first, second) in equalPairs {
            let canonical = DeviceAttributeDeduplicator.canonicalize(first)
            XCTAssertNotNil(canonical)
            XCTAssertEqual(canonical, DeviceAttributeDeduplicator.canonicalize(second))
        }
    }

    func testCanonicalization_sharedDistinctCases() {
        let distinctPairs: [(Any, Any)] = [
            (true, 1),
            (false, 0),
            ("1", 1),
            (1.5, 1),
            ([Any](), [String: Any]()),
            ([NSNull()], [Any]()),
            (["a": NSNull()], [String: Any]()),
            ([["a", "b"]], ["a", "b"])
        ]
        for (first, second) in distinctPairs {
            XCTAssertNotEqual(DeviceAttributeDeduplicator.canonicalize(first), DeviceAttributeDeduplicator.canonicalize(second))
        }
    }

    func testCanonicalization_sharedInvalidCases() {
        let invalid: [Any?] = [
            nil,
            NSNull(),
            Double.nan,
            Double.infinity,
            -Double.infinity,
            NSObject(),
            [1: "x"] as [AnyHashable: Any],
            ["a", Double.nan] as [Any],
            ["a": Double.infinity]
        ]
        for value in invalid {
            XCTAssertNil(DeviceAttributeDeduplicator.canonicalize(value))
        }
    }

    func testCanonicalization_sharedExpectedStrings() {
        typealias Dedup = DeviceAttributeDeduplicator
        XCTAssertEqual("\"a\"", Dedup.canonicalize("a"))
        XCTAssertEqual("true", Dedup.canonicalize(true))
        XCTAssertEqual("1", Dedup.canonicalize(1.0))
        XCTAssertEqual("0", Dedup.canonicalize(-0.0))
        XCTAssertEqual("[\"a\",\"b\"]", Dedup.canonicalize(["b", "a", "a"]))
        XCTAssertEqual("{\"a\":[1,2],\"b\":null}", Dedup.canonicalize(["b": NSNull(), "a": [2, 1, 2]] as [String: Any]))
        XCTAssertEqual("[]", Dedup.canonicalize([Any]()))
        XCTAssertEqual("{}", Dedup.canonicalize([String: Any]()))
    }

    /// iOS only: strings are escaped as Android's `JSONObject.quote` does.
    func testCanonicalization_escapesStringsLikeJSONObjectQuote() {
        XCTAssertEqual("\"a\\\"b\\\\c\\/\\n\\t\\u0001\"", DeviceAttributeDeduplicator.canonicalize("a\"b\\c/\n\t\u{01}"))
    }

    func testNonStringKeyIsDropped() {
        let nested: [AnyHashable: Any] = [1: "dropped", "kept": "value"]
        XCTAssertEqual(["custom": ["kept": "value"]] as NSDictionary,
                       deduplicator.filter(["custom": nested], dedup: true, owners: nil).changed as NSDictionary)
    }

    func testRemovePathsRemovesValuesAndEmptyParents() {
        deduplicator.commit(["tokens": ["liveActivityStart": ["a"], "liveActivityUpdate": ["b"]], "timezone": "UTC"])
        deduplicator.remove(paths: [["tokens", "liveActivityStart"], ["tokens", "liveActivityUpdate"]])
        XCTAssertEqual(["timezone": "UTC"] as NSDictionary, reloaded().readSynced() as NSDictionary)
    }
}
