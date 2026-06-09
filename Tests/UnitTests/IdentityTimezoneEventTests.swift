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
import XCTest

class IdentityTimezoneEventTests: XCTestCase {

    private func makeEvent(data: [String: Any]?) -> Event {
        return Event(name: "Test Timezone",
                     type: IdentityConstants.EventTypes.GENERIC_PROFILE_ATTRIBUTES,
                     source: EventSource.requestContent,
                     data: data)
    }

    // MARK: - timezone

    func testTimezone_returnsValue() {
        let event = makeEvent(data: [TimeZoneAttributeHandler.key: "Asia/Kolkata"])
        XCTAssertEqual("Asia/Kolkata", event.timezone)
    }

    func testTimezone_returnsNil_whenAbsent() {
        let event = makeEvent(data: ["somekey": "someValue"])
        XCTAssertNil(event.timezone)
    }

    func testTimezone_returnsNil_whenNilData() {
        let event = makeEvent(data: nil)
        XCTAssertNil(event.timezone)
    }

    func testTimezone_returnsNil_whenNotString() {
        let event = makeEvent(data: [TimeZoneAttributeHandler.key: 99])
        XCTAssertNil(event.timezone)
    }

    /// The extractor is a pure value read — it does NOT validate the IANA identifier.
    /// An empty string passes through as-is; validation is `TimeZoneAttributeHandler.collectFromEvent`'s job.
    func testTimezone_returnsEmptyString_whenEmpty() {
        let event = makeEvent(data: [TimeZoneAttributeHandler.key: ""])
        XCTAssertEqual("", event.timezone)
    }

    func testTimezone_ignoresOtherProfileAttributeKeys() {
        let event = makeEvent(data: ["pushidentifier": "token-123"])
        XCTAssertNil(event.timezone)
    }
}
