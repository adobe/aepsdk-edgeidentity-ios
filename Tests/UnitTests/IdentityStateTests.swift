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
        let expectation = XCTestExpectation(description: "createXDMSharedState callback")
        let result = state.bootupIfReady(
            getSharedState: {_, _ in
                return nil
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertNotNil(sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

        // verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
    }

    /// Tests bootup does not generates ECID if already exists
    func testBootupIfReadyDoesNotGeneratesECIDIfSet() {
        let ecid = ECID()
        state.identityProperties.ecid = ecid.ecidString

        // test
        let expectation = XCTestExpectation(description: "createXDMSharedState callback")
        let result = state.bootupIfReady(
            getSharedState: {_, _ in
                return nil
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertEqual(ecid.ecidString, sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

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
        let expectation = XCTestExpectation(description: "createXDMSharedState callback")
        let result = state.bootupIfReady(
            getSharedState: {_, _ in
                return nil
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertEqual(properties.ecid, sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

        // verify
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertEqual(properties.ecid, state.identityProperties.ecid)
    }

    /// Test that bootup loads properties from Identity direct persistence
    func testBootupIfReadyLoadsFromIdentityDirectPersistence() {
        // setup, no ECID in Edge Identity persistence

        let legacyEcid = ECID()
        addEcidToIdentityDirectPersistence(ecid: legacyEcid)

        // test
        let expectation = XCTestExpectation(description: "createXDMSharedState callback")
        let result = state.bootupIfReady(
            getSharedState: {_, _ in
                return nil
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertEqual(legacyEcid.ecidString, sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(legacyEcid.ecidString, state.identityProperties.ecid)
    }

    /// Test that bootup returns true if already booted, and does not create a shared state
    func testBootupIfReadyReturnsTrueWhenBooted() {
        XCTAssertFalse(state.hasBooted)
        XCTAssertTrue(state.bootupIfReady(
                        getSharedState: {_, _ in
                            return nil
                        },
                        createXDMSharedState: {_, _ in }))
        XCTAssertTrue(state.hasBooted)
        XCTAssertTrue(state.bootupIfReady(
                        getSharedState: {_, _ in
                            return nil
                        },
                        createXDMSharedState: {_, _ in
                            XCTFail("BootupIfReady should not set XDM shared state if already booted.")
                        }))
    }

    func testBootupIfReadyReturnsFalseWhenIdentityDirectIsRegistered() {
        // setup, no ECID set in persistence

        let result = state.bootupIfReady(
            getSharedState: {name, _ in
                if name == IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME {
                    return SharedStateResult(status: .set, value: [
                                                IdentityConstants.SharedState.Hub.EXTENSIONS: [
                                                    IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME: [:]
                                                ]])
                }

                return SharedStateResult(status: .none, value: [:])
            },
            createXDMSharedState: {_, _ in
                XCTFail("BootupIfReady not expected to set XDM shared state.")
            })

        XCTAssertFalse(state.hasBooted)
        XCTAssertFalse(result)
    }

    func testBootupIfReadyGeneratesECIDWhenIdentityDirectIsNotRegistered() {
        // setup, no ECID set in persistence

        let expectation = XCTestExpectation(description: "createXDMSharedState callback")
        let result = state.bootupIfReady(
            getSharedState: {name, _ in
                if name == IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME {
                    return SharedStateResult(status: .set, value: [
                                                IdentityConstants.SharedState.Hub.EXTENSIONS: [
                                                    IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME: [:]
                                                ]])
                }

                return SharedStateResult(status: .none, value: [:])
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertNotNil(sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(state.hasBooted)
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
    }

    func testBootupIfReadySetECIDFromIdentityDirectSharedState() {
        // setup, no ECID set in persistence

        let expectation = XCTestExpectation(description: "createXDMSharedState callback")

        // Bootup after Identity direct state change and Identity direct is registered
        let result = state.bootupIfReady(
            getSharedState: {name, _ in
                if name == IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME {
                    return SharedStateResult(status: .set, value: [
                                                IdentityConstants.SharedState.Hub.EXTENSIONS: [
                                                    IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME: [:]
                                                ]])
                }
                // shared state is set but no ECID
                return SharedStateResult(status: .set, value: ["mid": "1234"])
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertEqual("1234", sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

        // expect bootup to return true and new ECID is generated
        XCTAssertTrue(result)
        XCTAssertEqual("1234", state.identityProperties.ecid)
    }

    func testBootupIfReadyGeneratesECIDWhenIdentityDirectSharedStateHasNoECID() {
        // setup, no ECID set in persistence

        let expectation = XCTestExpectation(description: "createXDMSharedState callback")

        // Bootup after Identity direct state change and Identity direct is registered
        let result = state.bootupIfReady(
            getSharedState: {name, _ in
                if name == IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME {
                    return SharedStateResult(status: .set, value: [
                                                IdentityConstants.SharedState.Hub.EXTENSIONS: [
                                                    IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME: [:]
                                                ]])
                }
                // shared state is set but no ECID
                return SharedStateResult(status: .set, value: [:])
            },
            createXDMSharedState: {data, _ in
                let sharedEcid = ((data.flattening()["identityMap.ECID"] as? [Any])?[0] as? [String: Any])?["id"] as? String
                XCTAssertNotNil(sharedEcid)
                expectation.fulfill()
            })

        wait(for: [expectation], timeout: 1)

        // expect bootup to return true and new ECID is generated
        XCTAssertTrue(result)
        XCTAssertNotNil(state.identityProperties.ecid)
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
        state.identityProperties.ecid = ECID().ecidString
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
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        state.updateCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("custom", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testUpdateCustomerIdentifiersNoEventDataResolvesState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: nil)

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.updateCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
                          type: EventType.edgeIdentity,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.removeCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(1, state.identityProperties.identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("identifier", state.identityProperties.identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveCustomerIdentifiersNoEventDataResolvesSharedState() {
        let currentIdentities = IdentityMap()
        currentIdentities.add(item: IdentityItem(id: "identifier"), withNamespace: "space")
        var props = IdentityProperties()
        props.updateCustomerIdentifiers(currentIdentities)

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: nil)
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.removeCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
                          type: EventType.edgeIdentity,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.removeCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
                          type: EventType.edgeIdentity,
                          source: EventSource.removeIdentity,
                          data: customerIdentities.asDictionary())

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.removeCustomerIdentifiers(event: event,
                                        resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() })

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
        props.advertisingIdentifier = "adid"
        props.ecidSecondary = ECID().ecidString
        props.ecid = ECID().ecidString

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.edgeIdentity,
                          source: EventSource.requestReset,
                          data: nil)

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")

        let dispatchedEventsExpectation = XCTestExpectation(description: "Expected dispatched events")
        dispatchedEventsExpectation.expectedFulfillmentCount = 1
        var dispatchedEvents: [Event] = []
        state.resetIdentifiers(event: event,
                               resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill()
                               }, eventDispatcher: { event in
                                // Only edgeIdentity event should be dispatched; consent is not handled as part of the reset flow
                                dispatchedEvents += [event]
                                dispatchedEventsExpectation.fulfill()
                               })

        wait(for: [xdmSharedStateExpectation, dispatchedEventsExpectation], timeout: 2)

        // Verify Event type and source pairs
        // Reset identity request
        XCTAssertEqual(1, dispatchedEvents.count)
        XCTAssertEqual(EventType.edgeIdentity, dispatchedEvents[0].type)
        XCTAssertEqual(EventSource.resetComplete, dispatchedEvents[0].source)

        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertNil(state.identityProperties.advertisingIdentifier)
        XCTAssertNil(state.identityProperties.ecidSecondary)
        XCTAssertNil(state.identityProperties.identityMap.getItems(withNamespace: "space"))
        XCTAssertNotNil(state.identityProperties.ecid)
        XCTAssertNotEqual(props.ecid, state.identityProperties.ecid)
    }

    private func addEcidToIdentityDirectPersistence(ecid: ECID?) {
        let data: [String: ECID?] = ["ecid": ecid]
        let jsonData = try? JSONEncoder().encode(data)
        mockDataStore.dict["identity.properties"] = jsonData
    }

    func testResetIdentitiesAdIdIsEmptyDoesNotDispatchConsentEvent() {
        var props = IdentityProperties()
        props.advertisingIdentifier = ""
        props.ecid = ECID().ecidString

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.edgeIdentity,
                          source: EventSource.requestReset,
                          data: nil)

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.resetIdentifiers(event: event,
                               resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() },
                               eventDispatcher: { event in
                                // Checking both the expected hit and that consent request event not sent
                                XCTAssertTrue(event.type == EventType.edgeIdentity && event.source == EventSource.resetComplete)
                                if event.type == EventType.edgeConsent && event.source == EventSource.updateConsent {
                                    XCTFail("Consent request event should not be dispatched")
                                }
                               })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertNil(state.identityProperties.advertisingIdentifier)
    }

    func testResetIdentitiesAdIdIsNilDoesNotDispatchConsentEvent() {
        var props = IdentityProperties()
        props.advertisingIdentifier = nil
        props.ecid = ECID().ecidString

        state = IdentityState(identityProperties: props)

        let event = Event(name: "Test event",
                          type: EventType.edgeIdentity,
                          source: EventSource.requestReset,
                          data: nil)

        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be resolved")
        state.resetIdentifiers(event: event,
                               resolveXDMSharedState: { _ in xdmSharedStateExpectation.fulfill() },
                               eventDispatcher: { event in
                                // Checking both the expected hit and that consent request event not sent
                                XCTAssertTrue(event.type == EventType.edgeIdentity && event.source == EventSource.resetComplete)
                                if event.type == EventType.edgeConsent && event.source == EventSource.updateConsent {
                                    XCTFail("Consent request event should not be dispatched")
                                }
                               })

        wait(for: [xdmSharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertNil(state.identityProperties.advertisingIdentifier)
    }

    // MARK: updateAdvertisingIdentifier(...)
    // Starting from nil
    /// Test ad ID is updated from nil to valid value on first call, and consent true is dispatched
    func testUpdateAdvertisingIdentifier_whenNil_thenChangedToValid() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: nil, newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID is updated from nil to empty on first call, and consent false is dispatched
    func testUpdateAdvertisingIdentifier_whenNil_thenChangedToEmpty() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: nil, newAdId: "", expectedAdId: nil)
    }

    /// Test ad ID is updated from nil to empty on first call when all zeros is passed, and consent false is dispatched
    func testUpdateAdvertisingIdentifier_whenNil_thenChangedToAllZeros() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: nil, newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: nil)
    }
    // Starting from ""
    /// Test ad ID is updated from empty to valid value and consent true is dispatched
    func testUpdateAdvertisingIdentifier_whenEmpty_thenChangedToValid() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "", newAdId: "adId", expectedAdId: "adId", expectedConsent: "y")
    }

    /// Test ad ID call is ignored when old and new values are empty
    func testUpdateAdvertisingIdentifier_whenEmpty_thenSameValue() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: "", expectedAdId: nil)
    }

    /// Test ad ID call is ignored when old and new values are empty; passing all zeros is converted to empty string
    func testUpdateAdvertisingIdentifier_whenEmpty_thenChangedToAllZeros() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "", newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: nil)
    }
    // Starting from valid
    /// Test ad ID is updated from old value to new value, and no consent event is dispatched
    func testUpdateAdvertisingIdentifier_whenValid_thenChangedToNewValid() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: "oldAdId", newAdId: "adId", expectedAdId: "adId")
    }

    /// Test ad ID is not updated when old and new values are the same
    func testUpdateAdvertisingIdentifier_whenValid_thenSameValue() {
        assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: "adId", newAdId: "adId", expectedAdId: "adId")
    }

    /// Test ad ID is updated from valid value to empty string and consent false is dispatched
    func testUpdateAdvertisingIdentifier_whenValid_thenChangedToEmpty() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: "", expectedAdId: nil, expectedConsent: "n")
    }

    /// Test ad ID is updaed from valid value to empty string when all zeros is passed, and consent false is dispatched
    func testUpdateAdvertisingIdentifier_whenValid_thenChangedToAllZeros() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: "oldAdId", newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: nil, expectedConsent: "n")
    }

    // Starting from all-zeros
    /// Test ad ID is updated from all zeros to empty string and consent false is dispatched
    func testUpdateAdvertisingIdentifier_whenAllZeros_thenChangedToEmpty() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: "", expectedAdId: nil, expectedConsent: "n")
    }

    /// Test ad ID is updated from all zeros to empty string and consent false is dispatched; passing all zeros is converted to empty string
    func testUpdateAdvertisingIdentifier_whenAllZeros_thenSameValue() {
        assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, newAdId: IdentityConstants.Default.ZERO_ADVERTISING_ID, expectedAdId: nil, expectedConsent: "n")
    }

    private func assertUpdateAdvertisingIdentifierIsUpdatedWithConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?, expectedConsent: String?) {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")
        let consentExpectation = XCTestExpectation(description: "Consent event should be dispatched once")

        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        var consentEvent: Event?
        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          eventDispatcher: { event in
                                            consentEvent = event
                                            consentExpectation.fulfill()
                                          })

        // verify
        wait(for: [xdmSharedStateExpectation, consentExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)

        XCTAssertNotNil(consentEvent)
        XCTAssertEqual(expectedConsent, ((consentEvent?.data?[IdentityConstants.XDMKeys.Consent.CONSENTS] as? [String: Any])?[IdentityConstants.XDMKeys.Consent.AD_ID] as? [String: Any])?[IdentityConstants.XDMKeys.Consent.VAL] as? String)
    }

    private func assertUpdateAdvertisingIdentifierIsUpdatedWithoutConsentChange(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        let xdmSharedStateExpectation = XCTestExpectation(description: "XDM shared state should be updated once")

        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in xdmSharedStateExpectation.fulfill() },
                                          eventDispatcher: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        wait(for: [xdmSharedStateExpectation], timeout: 2)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)
    }

    private func assertUpdateAdvertisingIdentifierIsNotUpdated(persistedAdId: String?, newAdId: String?, expectedAdId: String?) {
        // setup
        var props = IdentityProperties()
        props.ecid = ECID().ecidString
        props.advertisingIdentifier = persistedAdId

        state = IdentityState(identityProperties: props)
        let event = Event.fakeGenericIdentityEvent(adId: newAdId)

        state.updateAdvertisingIdentifier(event: event,
                                          createXDMSharedState: { _, _ in XCTFail("XDM Shared state should not be updated") },
                                          eventDispatcher: { _ in XCTFail("Consent event should not be dispatched") })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity edge properties should have been saved to persistence
        XCTAssertEqual(expectedAdId, state.identityProperties.advertisingIdentifier)
    }

}

private extension Event {
    static func fakeIdentityEvent() -> Event {
        return Event(name: "Fake Identity Event", type: EventType.edgeIdentity, source: EventSource.requestContent, data: nil)
    }

    static func fakeGenericIdentityEvent(adId: String?) -> Event {
        return Event(name: "Test Event",
                     type: EventType.genericIdentity,
                     source: EventSource.requestIdentity,
                     data: [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: adId as Any])
    }
}
