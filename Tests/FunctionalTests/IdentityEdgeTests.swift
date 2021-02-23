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
    var identityEdge: IdentityEdge!

    var mockRuntime: TestableExtensionRuntime!

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockRuntime = TestableExtensionRuntime()
        identityEdge = IdentityEdge(runtime: mockRuntime)
        identityEdge.onRegistered()
    }

    // MARK: handleIdentityRequest

    func testGenericIdentityRequestSetsAdId() {
        var props = IdentityEdgeProperties()
        props.ecid = ECID()
        props.privacyStatus = .optedIn
        props.advertisingIdentifier = "oldAdId"
        props.saveToPersistence()

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityEdgeConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "adId"])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.CONFIGURATION,
                                        event: event,
                                        data: ([IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: "optedin"], .set))

        _ = identityEdge.readyForEvent(event) // trigger boot sequence

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("adId", identityEdge.state?.identityEdgeProperties.advertisingIdentifier)

        XCTAssertEqual(2, mockRuntime.createdSharedStates.count) // bootup + request content event
        XCTAssertEqual("adId", mockRuntime.createdSharedStates[1]?[IdentityEdgeConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid?.ecidString ?? "")", "authenticationState": "ambiguous", "primary": 1]],
                    "IDFA": [["id": "adId", "authenticationState": "ambiguous", "primary": 0]]
                ]
            ]
        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty) // no Consent event dispatched
    }

    func testGenericIdentityRequestClearsAdId() {
        var props = IdentityEdgeProperties()
        props.ecid = ECID()
        props.privacyStatus = .optedIn
        props.advertisingIdentifier = "oldAdId"
        props.saveToPersistence()

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityEdgeConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""])

        mockRuntime.simulateSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.CONFIGURATION,
                                        event: event,
                                        data: ([IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY: "optedin"], .set))

        _ = identityEdge.readyForEvent(event) // trigger boot sequence

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("", identityEdge.state?.identityEdgeProperties.advertisingIdentifier)

        XCTAssertEqual(2, mockRuntime.createdSharedStates.count) // bootup + request content event
        XCTAssertNil(mockRuntime.createdSharedStates[1]?[IdentityEdgeConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid?.ecidString ?? "")", "authenticationState": "ambiguous", "primary": 1]]
                ]
            ]
        XCTAssertEqual(2, mockRuntime.createdXdmSharedStates.count) // bootup + request content event
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)

        let expectedConsent: [String: Any] =
            [
                "consents": [
                    "adId": ["val": "n"]
                ]
            ]
        XCTAssertEqual(1, mockRuntime.dispatchedEvents.count)
        XCTAssertEqual(expectedConsent as NSObject, mockRuntime.dispatchedEvents[0].data as NSObject?)
    }

}
