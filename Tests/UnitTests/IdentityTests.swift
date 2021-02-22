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

class IdentityTests: XCTestCase {
    var identity: Identity!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identity = Identity(runtime: mockRuntime)
        identity.onRegistered()
    }

    // MARK: handleIdentifiersRequest

    /// Tests that when identity receives a identity request identity event with empty event data that we dispatch a response event with the identifiers
    func testIdentityRequestIdentifiersHappy() {
        // setup
        let event = Event(name: "Test Request Identifiers",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: nil)
        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedStateKeys.CONFIGURATION,
                                        event: event,
                                        data: (["testKey": "testVal"], .set))

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
        let event = Event(name: "Test Request Identifiers",
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: nil)

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        let responseEvent = mockRuntime.dispatchedEvents.first(where: { $0.responseID == event.id })
        XCTAssertNotNil(responseEvent)
        XCTAssertNotNil(responseEvent?.data)
    }

    // MARK: handleRequestContent

    /// Tests that when identity receives a generic identity request content event with an advertising ID, that the ID is updated
    func testGenericIdentityRequestWithAdId() {
        // setup
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "newAdId"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("newAdId", identity.state?.identityProperties.advertisingIdentifier)
    }

    /// Tests that when identity receives a generic identity request content event without an advertising ID, that the ID is not changed
    func testGenericIdentityRequestWithoutAdId() {
        // setup
        let event = Event(name: "Test Request Content",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: ["someKey": "newAdId"] as [String: Any])
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state?.identityProperties.advertisingIdentifier)
    }

    // MARK: handleUpdateIdentity

    /// Tests when Identity receives an update identity event with valid data the customer identifiers are updated
    func testIdentityUpdateIdentityWithValidData() {
        // setup
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")

        let event = Event(name: "Test Update Identity",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: identityMap.asDictionary())
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identity.state?.identityProperties.customerIdentifiers)
        XCTAssertEqual("id", identity.state?.identityProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)
    }

    /// Tests when Identity receives an update identity event without valid data the customer identifiers are not updated
    func testIdentityUpdateIdentityWithNilData() {
        // setup
        let event = Event(name: "Test Update Identity",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state?.identityProperties.customerIdentifiers)
    }

    // MARK: handleRemoveIdentity

    /// Tests when Identity receives a remove identity event with valid data the customer identifiers are removed
    func testIdentityRemoveIdentityWithValidData() {
        // set default identites
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identity.state?.identityProperties.customerIdentifiers = defaultIdentities
        // verify setup
        XCTAssertNotNil(identity.state?.identityProperties.customerIdentifiers)
        XCTAssertEqual("id", identity.state?.identityProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)

        // setup
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")

        let event = Event(name: "Test Remove Identity",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: identityMap.asDictionary())
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNotNil(identity.state?.identityProperties.customerIdentifiers)
        XCTAssertEqual(true, identity.state?.identityProperties.customerIdentifiers?.isEmpty)
    }

    /// Tests when Identity receives a remove identity event without valid data the customer identifiers are not modified
    func testIdentityRemoveIdentityWithNilData() {
        // set default identites
        let defaultIdentities = IdentityMap()
        defaultIdentities.add(item: IdentityItem(id: "id", authenticationState: .authenticated, primary: true), withNamespace: "customer")
        identity.state?.identityProperties.customerIdentifiers = defaultIdentities
        // verify setup
        XCTAssertNotNil(identity.state?.identityProperties.customerIdentifiers)
        XCTAssertEqual("id", identity.state?.identityProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)

        // setup
        let event = Event(name: "Test Remove Identity",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify data is the same
        XCTAssertNotNil(identity.state?.identityProperties.customerIdentifiers)
        XCTAssertEqual("id", identity.state?.identityProperties.customerIdentifiers?.getItems(withNamespace: "customer")?[0].id)
    }

    // MARK: handleRequestReset

    /// Tests when Identity receives a request reset event that identifiers are cleared and ECID is regenerated
    func testIdentityRequestReset() {
        // setup
        let originalEcid = ECID()
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "customer")
        identity.state?.identityProperties.customerIdentifiers = identityMap
        identity.state?.identityProperties.advertisingIdentifier = "adid"
        identity.state?.identityProperties.ecid = originalEcid

        let event = Event(name: "Test Request Event",
                          type: EventType.identityEdge,
                          source: EventSource.requestReset,
                          data: nil)
        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertNil(identity.state?.identityProperties.customerIdentifiers)
        XCTAssertNil(identity.state?.identityProperties.advertisingIdentifier)
        XCTAssertNotNil(identity.state?.identityProperties.ecid)
        XCTAssertNotEqual(originalEcid.ecidString, identity.state?.identityProperties.ecid?.ecidString)
    }

}
