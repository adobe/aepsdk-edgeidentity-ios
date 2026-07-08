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

class TimeZoneAttributeHandlerTests: XCTestCase {

    // Must mirror TimeZoneAttributeHandler.key — used for event input, persistence, and payload.
    private let key = TimeZoneAttributeHandler.key

    var handler: TimeZoneAttributeHandler!
    var mockDataStore: MockDataStore!

    override func setUp() {
        mockDataStore = MockDataStore()
        ServiceProvider.shared.namedKeyValueService = mockDataStore
        handler = TimeZoneAttributeHandler()
    }

    // MARK: - attributeKey

    func testAttributeKey_returnsTimeZoneKey() {
        XCTAssertEqual("timeZone", handler.attributeKey)
    }

    // MARK: - collectFromEvent

    func testCollectFromEvent_whenChanged_persistsAndReturnsContribution() {
        let result = handler.collectFromEvent(makeEvent("America/New_York"))

        XCTAssertEqual([key: "America/New_York"], result)
        XCTAssertEqual("America/New_York", storedTimezone())
    }

    func testCollectFromEvent_whenUnchanged_returnsNil() {
        storeTimezone("America/New_York")

        let result = handler.collectFromEvent(makeEvent("America/New_York"))

        XCTAssertNil(result)
    }

    func testCollectFromEvent_whenDifferent_persistsNewValueAndReturnsContribution() {
        storeTimezone("America/Los_Angeles")

        let result = handler.collectFromEvent(makeEvent("Asia/Kolkata"))

        XCTAssertEqual([key: "Asia/Kolkata"], result)
        XCTAssertEqual("Asia/Kolkata", storedTimezone())
    }

    func testCollectFromEvent_whenEmpty_returnsNil() {
        let result = handler.collectFromEvent(makeEvent(""))

        XCTAssertNil(result)
        XCTAssertNil(storedTimezone())
    }

    func testCollectFromEvent_whenKeyAbsent_returnsNil() {
        let event = Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                          type: EventType.genericProfileAttributes,
                          source: EventSource.requestContent,
                          data: ["otherKey": "value"])

        let result = handler.collectFromEvent(event)

        XCTAssertNil(result)
    }

    // NOTE: IANA validation is iOS-specific and absent in the Android implementation.
    // Android should add equivalent validation to reject non-IANA strings.
    func testCollectFromEvent_whenInvalidIANA_returnsNilAndDoesNotPersist() {
        let result = handler.collectFromEvent(makeEvent("Not/AReal/Zone"))

        XCTAssertNil(result)
        XCTAssertNil(storedTimezone())
    }

    func testCollectFromEvent_whenNilEventData_returnsNil() {
        let event = Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                          type: EventType.genericProfileAttributes,
                          source: EventSource.requestContent,
                          data: nil)

        let result = handler.collectFromEvent(event)

        XCTAssertNil(result)
    }

    // MARK: - collectFromStorage

    func testCollectFromStorage_whenStored_returnsContribution() {
        storeTimezone("Asia/Kolkata")

        let result = handler.collectFromStorage()

        XCTAssertEqual([key: "Asia/Kolkata"], result)
    }

    func testCollectFromStorage_whenNothingStored_returnsNil() {
        let result = handler.collectFromStorage()

        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func makeEvent(_ timezone: String) -> Event {
        return Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                     type: EventType.genericProfileAttributes,
                     source: EventSource.requestContent,
                     data: [key: timezone])
    }

    private func storeTimezone(_ timezone: String) {
        mockDataStore.set(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: key, value: timezone)
    }

    private func storedTimezone() -> String? {
        return mockDataStore.get(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: key) as? String
    }
}
