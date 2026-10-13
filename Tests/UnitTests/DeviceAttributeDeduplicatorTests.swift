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
    private let storeName = IdentityConstants.Store.DEVICE_ATTRIBUTES

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

    func testFilterDoesNotWriteUntilCommit() {
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": ["pushNotification": "push"]]
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: true) as NSDictionary)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: true) as NSDictionary)
        XCTAssertNil(store.get(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES))

        deduplicator.commit(attributes)

        XCTAssertTrue(deduplicator.filter(attributes, dedup: true).isEmpty)
        XCTAssertEqual(2, deduplicator.readSynced().count)
    }

    func testNestedAttributesAreDeduplicatedIndependently() {
        deduplicator.commit(["tokens": ["pushNotification": "push", "liveActivityUpdate": []]])
        let filtered = deduplicator.filter(
            ["tokens": ["pushNotification": "push", "liveActivityUpdate": [["liveActivityID": "A", "token": "new"]]]],
            dedup: true)
        let expected: [String: Any] = ["tokens": ["liveActivityUpdate": [["liveActivityID": "A", "token": "new"]]]]
        XCTAssertEqual(expected as NSDictionary, filtered as NSDictionary)
    }

    func testConfirmedParentAndChildUpdatesInvalidateEachOther() {
        let children: [String: Any] = ["settings": ["theme": "dark", "language": "en"]]
        let parent: [String: Any] = ["settings": [String: Any]()]
        deduplicator.commit(children)
        deduplicator.commit(parent)
        XCTAssertEqual(1, deduplicator.readSynced().count)
        XCTAssertEqual(children as NSDictionary, deduplicator.filter(children, dedup: true) as NSDictionary)
        deduplicator.commit(children)
        XCTAssertEqual(2, deduplicator.readSynced().count)
        XCTAssertEqual(parent as NSDictionary, deduplicator.filter(parent, dedup: true) as NSDictionary)
    }

    func testConfirmedChildUpdatePreservesSiblingAndLiteralDottedPaths() {
        let attributes: [String: Any] = ["a.b": "literal", "a": ["b": "old", "c": "sibling"]]
        deduplicator.commit(attributes)
        deduplicator.commit(["a": ["b": "new"]])
        XCTAssertEqual(3, deduplicator.readSynced().count)
        XCTAssertTrue(deduplicator.filter(["a.b": "literal", "a": ["b": "new", "c": "sibling"]], dedup: true).isEmpty)
        XCTAssertEqual(["a": ["b": "old"]] as NSDictionary, deduplicator.filter(attributes, dedup: true) as NSDictionary)
    }

    func testFilteredPayloadDoesNotRetainMutableFoundationValues() {
        let push = NSMutableString(string: "push")
        let update = NSMutableString(string: "update")
        let entries = NSMutableArray(object: ["liveActivityID": "1", "token": update])
        let filtered = deduplicator.filter(["tokens": ["pushNotification": push, "liveActivityUpdate": entries]], dedup: true)
        push.setString("changed-push")
        update.setString("changed-update")
        entries.removeAllObjects()
        let expected: [String: Any] = ["tokens": [
            "pushNotification": "push", "liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]
        ]]
        XCTAssertEqual(expected as NSDictionary, filtered as NSDictionary)
        deduplicator.commit(filtered)
        XCTAssertTrue(deduplicator.filter(expected, dedup: true).isEmpty)
    }

    func testTimezoneOwnerRequiresExactStringMatchAndDoesNotCommit() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, timezone: "Europe/London").isEmpty)
        for timezone in [nil, "", "Asia/Kolkata"] as [String?] {
            XCTAssertEqual(attributes as NSDictionary,
                           deduplicator.filter(attributes, dedup: true, timezone: timezone) as NSDictionary)
        }
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
    }

    func testPushOwnerUsesOnlyMessagingPushIdentifierForTheNestedPath() {
        let attributes: [String: Any] = ["tokens": ["pushNotification": "push"]]
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, messagingState: ["pushidentifier": "push"]).isEmpty)
        let owners: [[String: Any]] = [[:], ["pushNotification": "push"], ["pushidentifier": "other"], ["pushidentifier": 1]]
        for owner in owners {
            XCTAssertEqual(attributes as NSDictionary,
                           deduplicator.filter(attributes, dedup: true, messagingState: owner) as NSDictionary)
        }
        XCTAssertEqual(["pushNotification": "push"] as NSDictionary,
                       deduplicator.filter(["pushNotification": "push"],
                                           dedup: true,
                                           messagingState: ["pushidentifier": "push"]) as NSDictionary)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
    }

    func testLiveActivityOwnersIgnoreOrderMetadataAndExtraStoredEntries() {
        let attributes: [String: Any] = ["tokens": [
            "liveActivityStart": [["attributeType": "B", "value": "start-b"], ["attributeType": "A", "value": "start-a"]],
            "liveActivityUpdate": [["liveActivityID": "2", "token": "update-2"], ["liveActivityID": "1", "token": "update-1"]]
        ]]
        let owner: [String: Any] = ["liveActivity": [
            "pushToStartTokens": [
                "A": ["token": "start-a", "firstIssued": 1],
                "B": ["token": "start-b", "firstIssued": 2],
                "extra": ["token": "unused"]
            ],
            "updateTokens": [
                "1": ["token": "update-1", "attributeType": "A", "firstIssued": 1],
                "2": ["token": "update-2", "attributeType": "B", "firstIssued": 2],
                "extra": ["token": "unused"]
            ]
        ]]
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, messagingState: owner).isEmpty)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
    }

    func testLiveActivityOwnerMismatchSendsTheWholeInputArray() {
        let cases = [
            ("liveActivityStart", "pushToStartTokens", "attributeType", "value"),
            ("liveActivityUpdate", "updateTokens", "liveActivityID", "token")
        ]
        for (path, ownerKey, idKey, tokenKey) in cases {
            let entries = [[idKey: "A", tokenKey: "token-a"], [idKey: "B", tokenKey: "token-b"]]
            let attributes: [String: Any] = ["tokens": [path: entries]]
            for stored in [
                ["A": ["token": "token-a"]],
                ["A": ["token": "token-a"], "B": ["token": "changed"]]
            ] {
                let owner: [String: Any] = ["liveActivity": [ownerKey: stored]]
                XCTAssertEqual(attributes as NSDictionary,
                               deduplicator.filter(attributes, dedup: true, messagingState: owner) as NSDictionary)
            }
        }
    }

    func testEmptyLiveActivityArrayMatchesOnlyAnExplicitlyEmptyOwnerMap() {
        for (path, ownerKey) in [("liveActivityStart", "pushToStartTokens"), ("liveActivityUpdate", "updateTokens")] {
            let attributes: [String: Any] = ["tokens": [path: [Any]()]]
            let emptyOwner: [String: Any] = ["liveActivity": [ownerKey: [String: [String: Any]]()]]
            XCTAssertTrue(deduplicator.filter(attributes, dedup: true, messagingState: emptyOwner).isEmpty)
            let owners: [[String: Any]] = [[:], ["liveActivity": [:]],
                                          ["liveActivity": [ownerKey: ["A": ["token": "token"]]]]]
            for owner in owners {
                XCTAssertEqual(attributes as NSDictionary,
                               deduplicator.filter(attributes, dedup: true, messagingState: owner) as NSDictionary)
            }
        }
    }

    func testMalformedLiveActivityEntriesDoNotMatchOwners() {
        let owner: [String: Any] = ["liveActivity": [
            "pushToStartTokens": ["A": ["token": "start"]],
            "updateTokens": ["1": ["token": "update"]]
        ]]
        let cases: [(String, [[String: Any]])] = [
            ("liveActivityStart", [["attributeType": "A"]]),
            ("liveActivityStart", [["value": "start"]]),
            ("liveActivityStart", [["attributeType": "A", "value": 1]]),
            ("liveActivityUpdate", [["liveActivityID": "1"]]),
            ("liveActivityUpdate", [["token": "update"]]),
            ("liveActivityUpdate", [["liveActivityID": 1, "token": "update"]])
        ]
        for (path, entries) in cases {
            let attributes: [String: Any] = ["tokens": [path: entries]]
            XCTAssertEqual(attributes as NSDictionary,
                           deduplicator.filter(attributes, dedup: true, messagingState: owner) as NSDictionary)
        }
    }

    func testDedupFalseDisablesConfirmedAndAllOwnerComparisons() {
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": [
            "pushNotification": "push",
            "liveActivityStart": [["attributeType": "A", "value": "start"]],
            "liveActivityUpdate": [["liveActivityID": "1", "token": "update"]]
        ]]
        let owner: [String: Any] = ["pushidentifier": "push", "liveActivity": [
            "pushToStartTokens": ["A": ["token": "start"]],
            "updateTokens": ["1": ["token": "update"]]
        ]]
        deduplicator.commit(attributes)
        XCTAssertEqual(attributes as NSDictionary,
                       deduplicator.filter(attributes,
                                           dedup: false,
                                           messagingState: owner,
                                           timezone: "Europe/London") as NSDictionary)
    }

    func testNullIsDroppedAndEmptyContainersAreValuesButAppIsNotAnAttribute() {
        let attributes: [String: Any] = ["null": NSNull(), "array": [], "object": [:], "app": ["id": "test"]]
        let filtered = deduplicator.filter(attributes, dedup: true)
        XCTAssertEqual(["array": [], "object": [:]] as NSDictionary, filtered as NSDictionary)
        deduplicator.commit(attributes)
        XCTAssertEqual(2, deduplicator.readSynced().count)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true).isEmpty)
    }

    func testEmptyPushTokenIsPreservedAndComparedAsAString() {
        let attributes: [String: Any] = ["tokens": ["pushNotification": ""]]
        let previous: [String: Any] = ["tokens": ["pushNotification": "previous"]]
        deduplicator.commit(previous)
        XCTAssertEqual(attributes as NSDictionary,
                       deduplicator.filter(attributes,
                                           dedup: true,
                                           messagingState: ["pushidentifier": "previous"]) as NSDictionary)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true, messagingState: ["pushidentifier": ""]).isEmpty)
        XCTAssertEqual(1, deduplicator.readSynced().count)
        deduplicator.commit(attributes)
        XCTAssertTrue(deduplicator.filter(attributes, dedup: true).isEmpty)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.filter(attributes, dedup: false) as NSDictionary)
    }

    func testInvalidJSONLeavesAreDroppedWithoutWritingStorage() {
        let filtered = deduplicator.filter(["nested": ["valid": "value", "invalid": Date()], "nan": Double.nan], dedup: false)
        XCTAssertEqual(["nested": ["valid": "value"]] as NSDictionary, filtered as NSDictionary)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
    }

    func testClearRemovesConfirmedDeviceValuesWithoutClearingOtherStores() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        store.set(collectionName: IdentityConstants.Store.PROFILE_ATTRIBUTES, key: TimeZoneAttributeHandler.key, value: "Asia/Kolkata")
        deduplicator.commit(attributes)
        let restored = DeviceAttributeDeduplicator(storeName: storeName)
        XCTAssertTrue(restored.filter(attributes, dedup: true).isEmpty)
        restored.clear()
        XCTAssertNil(store.get(collectionName: storeName, key: "confirmedAttributes"))
        XCTAssertEqual(attributes as NSDictionary, restored.filter(attributes, dedup: true) as NSDictionary)
        XCTAssertEqual("Asia/Kolkata",
                       store.get(collectionName: IdentityConstants.Store.PROFILE_ATTRIBUTES, key: TimeZoneAttributeHandler.key) as? String)
    }
}
