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
@testable import AEPEdgeIdentity
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

    /// Tests bootup generates ECID
    func testBootupIfReadyGeneratesECID() {
        XCTAssertNil(state.identityProperties.ecid)

        // test
        let result = state.bootupIfReady()

        // verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
    }

    /// Tests bootup does not generates ECID if already exists
    func testBootupIfReadyDoesNotGeneratesECIDIfSet() {
        let ecid = ECID()
        state.identityProperties.ecid = ecid.ecidString

        // test
        let result = state.bootupIfReady()

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(ecid.ecidString, state.identityProperties.ecid)
    }

    /// Test that bootup loads properties from persistence
    func testBootupIfReadyLoadsFromPersistence() {
        // setup
        var properties = IdentityProperties()
        properties.ecid = ECID().ecidString
        properties.saveToPersistence() // save to shared data store

        // test
        let result = state.bootupIfReady()

        //verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(properties.ecid, state.identityProperties.ecid)
    }

    /// Test that bootup returns false if already booted
    func testBootupIfReadyReturnsFalseWhenBooted() {
        XCTAssertFalse(state.hasBooted)
        XCTAssertTrue(state.bootupIfReady())
        XCTAssertTrue(state.hasBooted)
        XCTAssertFalse(state.bootupIfReady())
    }

    // MARK: updateLegacyExperienceCloudId(...)

    func testUpdateLegacyExperienceCloudIdNewEcidIsSet() {
        state.identityProperties.ecid = ECID().ecidString
        state.identityProperties.ecidSecondary = ECID().ecidString

        XCTAssertTrue(state.updateLegacyExperienceCloudId("legacyEcid"))
        XCTAssertFalse(mockDataStore.dict.isEmpty) // properties saved to persistence
        XCTAssertEqual("legacyEcid", state.identityProperties.ecidSecondary)
    }

    func testUpdateLegacyExperienceCloudIdNotSetWhenEcidIsSame() {
        let ecid = ECID().ecidString
        state.identityProperties.ecid = ecid

        XCTAssertFalse(state.updateLegacyExperienceCloudId(ecid))
        XCTAssertTrue(mockDataStore.dict.isEmpty) // properties saved to persistence
        XCTAssertNil(state.identityProperties.ecidSecondary)
    }

    func testUpdateLegacyExperienceCloudIdNotSetWhenLegacyEcidIsSame() {
        state.identityProperties.ecidSecondary = "legacyEcid"

        XCTAssertFalse(state.updateLegacyExperienceCloudId("legacyEcid"))
        XCTAssertTrue(mockDataStore.dict.isEmpty) // properties saved to persistence
        XCTAssertEqual("legacyEcid", state.identityProperties.ecidSecondary) // unchanged
    }

    // MARK: updateCustomerIdentifiers(...)

    func testUpdateCustomerIdentifiers() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(2, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityProperties.identityMap.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersFiltersOutUnallowedNamespaces() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "ecid"), withNamespace: IdentityConstants.Namespaces.ECID)
        customerIdentities.add(item: IdentityItem(id: "idfa"), withNamespace: IdentityConstants.Namespaces.IDFA)
        customerIdentities.add(item: IdentityItem(id: "gaid"), withNamespace: IdentityConstants.Namespaces.GAID)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(2, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityProperties.identityMap.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersFiltersOutUnallowedNamespacesCaseInsensitive() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "ecid"), withNamespace: "ecid")
        customerIdentities.add(item: IdentityItem(id: "idfa"), withNamespace: "idfa")
        customerIdentities.add(item: IdentityItem(id: "gaid"), withNamespace: "gaid")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(2, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual("custom", state.identityProperties.identityMap.getItems(withNamespace: "space")?[1].id)
    }

    func testUpdateCustomerIdentifiersNoCurrentIdentifiers() {
        let props = IdentityProperties()

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("custom", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testUpdateCustomerIdentifiersNoEventDataDoesNotUpdateState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)

        state.updateCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    // MARK: removeCustomerIdentifiers(...)

    func testRemoveCustomerIdentifiers() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        currentIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveCustomerIdentifiersNoEventDataDoesNotUpdateState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: nil)

        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") })

        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should not have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveCustomerIdentifiersFiltersOutUnallowedNamespaces() {
        let props = IdentityProperties()
        props.identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        props.identityMap.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        props.identityMap.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.ECID)
        props.identityMap.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.IDFA)
        props.identityMap.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.GAID)

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.ECID)
        customerIdentities.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.IDFA)
        customerIdentities.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.GAID)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveCustomerIdentifiersFiltersOutUnallowedNamespacesCaseInsensitive() {
        let props = IdentityProperties()
        props.identityMap.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        props.identityMap.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        props.identityMap.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.ECID)
        props.identityMap.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.IDFA)
        props.identityMap.add(item: IdentityItem(id: "id"), withNamespace: IdentityConstants.Namespaces.GAID)

        state = IdentityState(identityProperties: props)

        let customerIdentities = IdentityMap()
        customerIdentities.add(item: IdentityItem(id: "custom"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "identifier2"), withNamespace: "space")
        customerIdentities.add(item: IdentityItem(id: "id"), withNamespace: "ecid")
        customerIdentities.add(item: IdentityItem(id: "id"), withNamespace: "idfa")
        customerIdentities.add(item: IdentityItem(id: "id"), withNamespace: "gaid")

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.removeCustomerIdentifiers(event: event,
                                        createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    // MARK: resetIdentities(...)

    func testResetIdentities() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)
        props.ecidSecondary = ECID().ecidString
        props.ecid = ECID().ecidString

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.identityEdge,
                          source: EventSource.requestReset,
                          data: nil)

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.resetIdentifiers(event: event,
                               createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill()
                               })

        wait(for: [xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertNil(state.identityProperties.ecidSecondary)
        XCTAssertNil(state.identityProperties.identityMap.getItems(withNamespace: "space"))
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertNotEqual(props.ecid, state.identityProperties.ecid)
    }

}

private extension Event {
    static func fakeIdentityEvent() -> Event {
        return Event(name: "Fake Identity Event", type: EventType.identityEdge, source: EventSource.requestContent, data: nil)
    }
}
