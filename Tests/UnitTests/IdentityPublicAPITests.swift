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
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.identityEdge, source: EventSource.requestIdentity) { _ in
            expectation.fulfill()
        }

        // test
        Identity.getExperienceCloudId { _, _ in }

        // verify
        wait(for: [expectation], timeout: 1)
    }

    /// Tests that getIdentities dispatches an identity request identity event
    func testGetIdentities() {
        // setup
        let expectation = XCTestExpectation(description: "getIdentities should dispatch an event")
        expectation.assertForOverFulfill = true
        EventHub.shared.getExtensionContainer(MockExtension.self)?.registerListener(type: EventType.identityEdge, source: EventSource.requestIdentity) { _ in
            expectation.fulfill()
        }

        // test
        Identity.getIdentities { _, _ in }

        // verify
        wait(for: [expectation], timeout: 1)
    }
}
