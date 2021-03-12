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
@testable import AEPEdgeIdentity
import XCTest

class IdentityAPITests: XCTestCase {

    override func setUp() {
        MockExtension.reset()
        EventHub.shared.start()
        registerMockExtension(MockExtension.self)
    }

    override func tearDown() {
        unregisterMockExtension(MockExtension.self)
    }

    private func registerMockExtension<T: Extension> (_ type: T.Type) {
        let semaphore = DispatchSemaphore(value: 0)
        EventHub.shared.registerExtension(type) { _ in
            semaphore.signal()
        }

        semaphore.wait()
    }

    private func unregisterMockExtension<T: Extension> (_ type: T.Type) {
        let semaphore = DispatchSemaphore(value: 0)
        EventHub.shared.unregisterExtension(type) { _ in
            semaphore.signal()
        }

        semaphore.wait()
    }

    /// Tests that getExperienceCloudId dispatches an identity request identity event
    func testGetExperienceCloudId() {
        // setup
        let expectation = XCTestExpectation(description: "getExperienceCloudId should dispatch an event")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity) { _ in
            expectation.fulfill()
        }

        // test
        Identity.getExperienceCloudId { _, _ in }

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that getIdentities returns an error if the response event contains no data
    func testGetExperienceCloudIdReturnsErrorIfResponseContainsNoData() {
        // setup
        let expectation = XCTestExpectation(description: "getExperienceCloudId callback should get called")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity) { event in
            let responseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_CONTENT_ONE_TIME,
                                                          type: EventType.edgeIdentity,
                                                          source: EventSource.responseIdentity,
                                                          data: nil)
            MobileCore.dispatch(event: responseEvent)
        }

        // test
        Identity.getExperienceCloudId { _, error in
            XCTAssertNotNil(error)
            XCTAssertEqual(AEPError.unexpected, error as? AEPError)
            expectation.fulfill()
        }

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that getIdentities dispatches an identity request identity event
    func testGetIdentities() {
        // setup
        let expectation = XCTestExpectation(description: "getIdentities should dispatch an event")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity) { _ in
            expectation.fulfill()
        }

        // test
        Identity.getIdentities { _, _ in }

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that getIdentities returns an error if the response event contains no data
    func testGetIdentitiesReturnsErrorIfResponseContainsNoData() {
        // setup
        let expectation = XCTestExpectation(description: "getIdentities callback should get called")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity) { event in
            let responseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_CONTENT_ONE_TIME,
                                                          type: EventType.edgeIdentity,
                                                          source: EventSource.responseIdentity,
                                                          data: nil)
            MobileCore.dispatch(event: responseEvent)
        }

        // test
        Identity.getIdentities { _, error in
            XCTAssertNotNil(error)
            XCTAssertEqual(AEPError.unexpected, error as? AEPError)
            expectation.fulfill()
        }

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that getIdentities returns an empty IdentityMap if the response map is empty
    func testGetIdentitiesReturnsEmptyIdentitiesWhenResponseIsEmpty() {
        // setup
        let expectation = XCTestExpectation(description: "getIdentities callback should get called")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity) { event in
            let responseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_CONTENT_ONE_TIME,
                                                          type: EventType.edgeIdentity,
                                                          source: EventSource.responseIdentity,
                                                          data: [IdentityConstants.XDMKeys.IDENTITY_MAP: [:]])
            MobileCore.dispatch(event: responseEvent)
        }

        // test
        Identity.getIdentities { identityMap, _ in
            XCTAssertEqual(true, identityMap?.isEmpty)
            expectation.fulfill()
        }

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that updateIdentifiers dispatches an identity update identity event
    func testUpdateIdentifiers() {
        // setup
        let expectation = XCTestExpectation(description: "updateIdentities should dispatch an event")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.updateIdentity) { _ in
            expectation.fulfill()
        }

        // test
        let map = IdentityMap()
        map.add(item: IdentityItem(id: "id"), withNamespace: "namespace")
        Identity.updateIdentities(with: map)

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that removeIdentity dispatches an identity remove identity event
    func testRemoveIdentity() {
        // setup
        let expectation = XCTestExpectation(description: "removeIdentity should dispatch an event")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.removeIdentity) { _ in
            expectation.fulfill()
        }

        // test
        Identity.removeIdentity(item: IdentityItem(id: "id"), withNamespace: "namespace")

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that resetIdentities dispatches an edge identity reset request event
    func testResetIdentities() {
        // setup
        let expectation = XCTestExpectation(description: "resetIdentities should dispatch an event")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.edgeIdentity, source: EventSource.requestReset) { _ in
            expectation.fulfill()
        }

        // test
        Identity.resetIdentities()

        // verify
        wait(for: [expectation], timeout: 1)
    }
}
