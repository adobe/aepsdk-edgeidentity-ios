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

    // MARK: handleIdentityRequest

    func testGenericIdentityRequestSetsAdId() {
        var props = IdentityProperties()
        props.ecid = ECID()
        props.privacyStatus = .optedIn
        props.advertisingIdentifier = "oldAdId"
        props.saveToPersistence()

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "adId"])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedStateKeys.CONFIGURATION,
                                        event: event,
                                        data: ([IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: "optedin"], .set))

        _ = identity.readyForEvent(event) // trigger boot sequence

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("adId", identity.state?.identityProperties.advertisingIdentifier)

        XCTAssertEqual("adId", mockRuntime.createdSharedStates[1]?[IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid?.ecidString ?? "")"]],
                    "IDFA": [["id": "adId"]]
                ]
            ]
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)

        XCTAssertTrue(mockRuntime.dispatchedEvents.isEmpty) // no Consent event dispatched
    }

    func testGenericIdentityRequestClearsAdId() {
        var props = IdentityProperties()
        props.ecid = ECID()
        props.privacyStatus = .optedIn
        props.advertisingIdentifier = "oldAdId"
        props.saveToPersistence()

        let event = Event(name: "Test Generic Identity",
                          type: EventType.genericIdentity,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""])

        mockRuntime.simulateSharedState(extensionName: IdentityConstants.SharedStateKeys.CONFIGURATION,
                                        event: event,
                                        data: ([IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: "optedin"], .set))

        _ = identity.readyForEvent(event) // trigger boot sequence

        // test
        mockRuntime.simulateComingEvent(event: event)

        // verify
        XCTAssertEqual("", identity.state?.identityProperties.advertisingIdentifier)

        XCTAssertNil(mockRuntime.createdSharedStates[1]?[IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)

        let expectedIdentity: [String: Any] =
            [
                "identityMap": [
                    "ECID": [["id": "\(props.ecid?.ecidString ?? "")"]]
                ]
            ]
        XCTAssertEqual(expectedIdentity as NSObject, mockRuntime.createdXdmSharedStates[1] as NSObject?)

        let expectedConsent: [String: Any] =
            [
                "consents": [
                    "adId": ["val": "n"]
                ]
            ]
        XCTAssertEqual(expectedConsent as NSObject, mockRuntime.dispatchedEvents[0].data as NSObject?)
    }

}
