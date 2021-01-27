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

import AEPCore
@testable import AEPIdentityEdge
import AEPServices
import XCTest

class IdentityStateTests: XCTestCase {
    var state: IdentityState!

    var mockDataStore: MockDataStore {
        return ServiceProvider.shared.namedKeyValueService as! MockDataStore
    }

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        state = IdentityState(identityProperties: IdentityProperties())
    }

    // MARK: bootupIfReady(...) tests

    /// Tests that the default privacy status is set
    func testBootupIfReadyEmptyConfigSharedState() {
        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus)
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithOptInPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should have been updated
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithOptOutPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut] as [String: Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityProperties.privacyStatus) // privacy status should have been updated
    }

    /// Tests that the properties are updated
    func testBootupIfReadyWithUnknownPrivacyReturnsFalse() {
        // setup
        let configSharedState = [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown] as [String: Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeIdentityEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should have been updated
    }

    /// Test that bootup loads properties from persistence
    func testBootupIfReadyLoadsFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID()
        properties.saveToPersistence() // save to shared data store

        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeIdentityEvent())

        //verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(properties.ecid?.ecidString, state.identityProperties.ecid?.ecidString)
    }

    // MARK: processPrivacyChange(...)

    /// Tests that when the event data is empty update to unknown
    func testProcessPrivacyChangeNoPrivacyInEventData() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: nil)

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            XCTFail("Shared state should not be updated")
        }, createXDMSharedState: { _, _ in
            XCTFail("XDM Shared state should not be updated")
        })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status set to unknown
    }

    /// Tests that when we get an opt-in privacy status that we update the privacy status
    func testProcessPrivacyChangeToOptIn() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            XCTFail("Shared state should not be updated")
        }, createXDMSharedState: { _, _ in
            XCTFail("XDM Shared state should not be updated")
        })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should change to opt in
    }

    /// Tests that when we update privacy to opt-out
    func testProcessPrivacyChangeToOptOut() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            sharedStateExpectation.fulfill()
        }, createXDMSharedState: { _, _ in
            xdmSharedStateExpectation.fulfill()
        })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityProperties.privacyStatus) // privacy status should change to opt out
        XCTAssertNil(state.identityProperties.ecid) // ecid is cleared
    }

    /// Tests that when we got from opt out to opt in
    func testProcessPrivacyChangeFromOptOutToOptIn() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            sharedStateExpectation.fulfill()
        }, createXDMSharedState: { _, _ in
            xdmSharedStateExpectation.fulfill()
        })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should change to opt in
        XCTAssertNotNil(state.identityProperties.ecid) // ecid is set
    }

    /// When we go from opt-out to unknown
    func testProcessPrivacyChangeFromOptOutToUnknown() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            sharedStateExpectation.fulfill()
        }, createXDMSharedState: { _, _ in
            xdmSharedStateExpectation.fulfill()
        })

        // verify
        wait(for: [sharedStateExpectation, xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should change to opt in
        XCTAssertNotNil(state.identityProperties.ecid) // ecid is set
    }

    /// When privacy status is the same, no updates
    func testProcessPrivacyChangeToSame() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .optedIn
        props.ecid = ECID()

        state = IdentityState(identityProperties: props)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            XCTFail("Shared state should not be updated")
        }, createXDMSharedState: { _, _ in
            XCTFail("XDM Shared state should not be updated")
        })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should stay at optin
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(props.ecid?.ecidString, state.identityProperties.ecid?.ecidString)
    }
}

private extension Event {
    static func fakeIdentityEvent() -> Event {
        return Event(name: "Fake Identity Event", type: EventType.identity, source: EventSource.requestContent, data: nil)
    }
}
