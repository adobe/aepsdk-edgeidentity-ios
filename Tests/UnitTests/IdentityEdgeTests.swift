//
// Copyright 2021 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

@testable import AEPCore
@testable import AEPIdentityEdge
import AEPServices
import XCTest

class IdentityEdgeTests: XCTestCase {
    var identity: Identity!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
    }

    // MARK: processIdentifiersRequest

    /// Tests that when identity receives a identity request identity event with empty event data that we dispatch a response event with the identifiers
    func testIdentityRequestIdentifiersHappy() {
        // setup
        let event = Event(name: "Test Request Identifiers", type: EventType.identity, source: EventSource.requestIdentity, data: nil)
        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.CONFIGURATION, event: event, data: (["testKey": "testVal"], .set))

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    /// Tests that when identity receives a identity request identity event with empty event data and no config that we dispatch a response event with the identifiers
    func testIdentityRequestIdentifiersNoConfig() {
        // setup
        let event = Event(name: "Test Request Identifiers", type: EventType.identity, source: EventSource.requestIdentity, data: nil)

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    // MARK: handleConfigurationRequest

    /// Tests that when a configuration request content event contains opt-out that we update privacy status
    func testConfigurationResponseEventOptOut() {
        // setup
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()

        let data = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue] as [String: Any]
        let event = Event(name: "Test Configuration response", type: EventType.configuration, source: EventSource.responseContent, data: data)

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual(PrivacyStatus.optedOut, identity.state?.identityProperties.privacyStatus) // identity state should have updated to opt-out
    }

    /// Tests that when no privacy status is in the configuration event that we do not update the privacy status
    func testConfigurationResponseEventNoPrivacyStatus() {
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()

        let event = Event(name: "Test Configuration response", type: EventType.configuration, source: EventSource.responseContent, data: ["key": "value"])
        _ = identity.readyForEvent(event) // sets default privacy of unknown

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual(PrivacyStatus.unknown, identity.state?.identityProperties.privacyStatus) // identity state should have remained unknown
    }

}
