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

    private func reloaded() -> DeviceAttributeDeduplicator {
        return DeviceAttributeDeduplicator(storeName: storeName)
    }

    private func startTokens(_ entries: [(String, String)]) -> [[String: String]] {
        return entries.map { ["attributeType": $0.0, "value": $0.1] }
    }

    private func filter(_ attributes: [String: Any], owners: [String: Any]? = nil) -> DeviceAttributeDeduplicator.FilterResult {
        return deduplicator.filter(attributes, owners: owners)
    }

    // MARK: - Confirmed values

    func testFilterDoesNotWriteUntilCommit() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        XCTAssertEqual(attributes as NSDictionary, filter(attributes).changed as NSDictionary)
        XCTAssertEqual(attributes as NSDictionary, filter(attributes).changed as NSDictionary)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)

        deduplicator.commit(attributes)

        XCTAssertTrue(filter(attributes).changed.isEmpty)
        XCTAssertEqual(attributes as NSDictionary, reloaded().readSynced() as NSDictionary)
    }

    func testOnlyChangedDeduplicatedValuesAreSent() {
        deduplicator.commit(["timezone": "UTC", "tokens": ["pushNotification": "push"]])

        let result = filter(["timezone": "UTC", "tokens": ["pushNotification": "newPush"]])

        XCTAssertEqual(["tokens": ["pushNotification": "newPush"]] as NSDictionary, result.changed as NSDictionary)
        XCTAssertTrue(result.ownerMatches.isEmpty)
    }

    func testEmptyPushTokenIsAValue() {
        let attributes: [String: Any] = ["tokens": ["pushNotification": ""]]
        XCTAssertEqual(attributes as NSDictionary, filter(attributes).changed as NSDictionary)

        deduplicator.commit(attributes)

        XCTAssertTrue(filter(attributes).changed.isEmpty)
    }

    // MARK: - Push-to-start tokens

    func testStartTokensAreComparedIgnoringOrderAndDuplicates() {
        deduplicator.commit(["tokens": ["liveActivityStart": startTokens([("A", "a"), ("B", "b")])]])

        let reordered: [String: Any] = ["tokens": ["liveActivityStart": startTokens([("B", "b"), ("A", "a"), ("A", "a")])]]

        XCTAssertTrue(filter(reordered).changed.isEmpty)
    }

    func testChangedStartTokenSendsTheWholeList() {
        deduplicator.commit(["tokens": ["liveActivityStart": startTokens([("A", "a"), ("B", "b")])]])

        let changed: [String: Any] = ["tokens": ["liveActivityStart": startTokens([("A", "a"), ("B", "b2")])]]

        XCTAssertEqual(changed as NSDictionary, filter(changed).changed as NSDictionary)
    }

    func testEmptyStartTokenListIsAValue() {
        let attributes: [String: Any] = ["tokens": ["liveActivityStart": [[String: String]]()]]
        XCTAssertEqual(attributes as NSDictionary, filter(attributes).changed as NSDictionary)

        deduplicator.commit(attributes)

        XCTAssertTrue(filter(attributes).changed.isEmpty)
        XCTAssertEqual(attributes as NSDictionary, deduplicator.readSynced() as NSDictionary)
    }

    func testMalformedStartTokensAreSentAndNotStored() {
        let attributes: [String: Any] = ["tokens": ["liveActivityStart": [["attributeType": "A"]]]]

        deduplicator.commit(attributes)

        XCTAssertTrue(deduplicator.readSynced().isEmpty)
        XCTAssertEqual(attributes as NSDictionary, filter(attributes).changed as NSDictionary)
    }

    func testStartTokensAreStoredSorted() {
        deduplicator.commit(["tokens": ["liveActivityStart": startTokens([("B", "b"), ("A", "a")])]])

        XCTAssertEqual(["tokens": ["liveActivityStart": startTokens([("A", "a"), ("B", "b")])]] as NSDictionary,
                       reloaded().readSynced() as NSDictionary)
    }

    // MARK: - Owner-held values

    func testOwnerMatchesAreReturnedWithTheirOriginalValueAndNotCommitted() {
        let start = startTokens([("A", "a")])
        let attributes: [String: Any] = ["timezone": "Europe/London",
                                         "tokens": ["pushNotification": "push", "liveActivityStart": start]]
        let owners: [String: Any] = ["timezone": "Europe/London",
                                     "tokens": ["pushNotification": "other", "liveActivityStart": start]]

        let result = filter(attributes, owners: owners)

        XCTAssertEqual(["tokens": ["pushNotification": "push"]] as NSDictionary, result.changed as NSDictionary)
        XCTAssertEqual(["timezone": "Europe/London", "tokens": ["liveActivityStart": start]] as NSDictionary,
                       result.ownerMatches as NSDictionary)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
    }

    func testCommittedOwnerMatchesAreSkippedWithoutOwners() {
        let attributes: [String: Any] = ["timezone": "Europe/London", "tokens": ["liveActivityStart": startTokens([("A", "a")])]]
        let result = filter(attributes, owners: attributes)

        deduplicator.commit(result.ownerMatches)

        XCTAssertTrue(filter(attributes).changed.isEmpty)
    }

    func testConfirmedMatchIsNotReportedAsOwnerMatch() {
        let attributes: [String: Any] = ["timezone": "Europe/London"]
        deduplicator.commit(attributes)

        let result = filter(attributes, owners: attributes)

        XCTAssertTrue(result.changed.isEmpty)
        XCTAssertTrue(result.ownerMatches.isEmpty)
    }

    // MARK: - Other values

    func testOtherValuesAreAlwaysSentAsIsAndNeverStored() {
        let date = Date()
        let attributes: [String: Any] = ["custom": "value",
                                         "null": NSNull(),
                                         "date": date,
                                         "tokens.pushNotification": "dotted",
                                         "tokens": ["liveActivityUpdate": [["liveActivityID": "1", "token": "update"]], "foo": "bar"]]
        deduplicator.commit(attributes)

        let result = filter(attributes, owners: attributes)

        XCTAssertEqual(attributes as NSDictionary, result.changed as NSDictionary)
        XCTAssertTrue(result.ownerMatches.isEmpty)
        XCTAssertTrue(deduplicator.readSynced().isEmpty)
    }

    func testUnexpectedTypeAtDeduplicatedPathIsSentAndNotStored() {
        let attributes: [String: Any] = ["timezone": 5, "tokens": ["pushNotification": ["value": "push"]]]

        deduplicator.commit(attributes)

        XCTAssertTrue(deduplicator.readSynced().isEmpty)
        XCTAssertEqual(attributes as NSDictionary, filter(attributes, owners: attributes).changed as NSDictionary)
    }

    func testTokensAreRemovedOnlyWhenEveryTokenIsUnchanged() {
        deduplicator.commit(["tokens": ["pushNotification": "push"]])

        XCTAssertTrue(filter(["tokens": ["pushNotification": "push"]]).changed.isEmpty)
        XCTAssertEqual(["tokens": ["foo": "bar"]] as NSDictionary,
                       filter(["tokens": ["pushNotification": "push", "foo": "bar"]]).changed as NSDictionary)
        XCTAssertEqual(["tokens": [String: Any]()] as NSDictionary, filter(["tokens": [String: Any]()]).changed as NSDictionary)
    }

    // MARK: - Clear

    func testClearRemovesAllConfirmedValues() {
        deduplicator.commit(["timezone": "UTC", "tokens": ["pushNotification": "push", "liveActivityStart": startTokens([("A", "a")])]])

        deduplicator.clear()

        XCTAssertTrue(reloaded().readSynced().isEmpty)
    }

    func testClearLiveActivityStartKeepsOtherValues() {
        deduplicator.commit(["timezone": "UTC", "tokens": ["pushNotification": "push", "liveActivityStart": startTokens([("A", "a")])]])

        deduplicator.clearLiveActivityStart()

        XCTAssertEqual(["timezone": "UTC", "tokens": ["pushNotification": "push"]] as NSDictionary, reloaded().readSynced() as NSDictionary)
    }
}
