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
import AEPServices
import Foundation

/// Manages the business logic of the Identity Edge extension
class IdentityEdgeState {
    private let LOG_TAG = "IdentityEdgeState"
    private(set) var hasBooted = false
    #if DEBUG
    var identityEdgeProperties: IdentityEdgeProperties
    #else
    private(set) var identityEdgeProperties: IdentityEdgeProperties
    #endif

    /// List of namespaces which are not allowed to be modified from customer identifier
    private static let reservedNamespaces = [
        IdentityEdgeConstants.Namespaces.ECID,
        IdentityEdgeConstants.Namespaces.IDFA
    ]

    /// Creates a new `IdentityEdgeState` with the given identity edge properties
    /// - Parameter identityEdgeProperties: identity edge properties
    init(identityEdgeProperties: IdentityEdgeProperties) {
        self.identityEdgeProperties = identityEdgeProperties
    }

    /// Completes init for the Identity Edge extension.
    /// - Returns: True if we should share state after bootup, false otherwise
    func bootupIfReady() -> Bool {

        // load data from local storage
        identityEdgeProperties.loadFromPersistence()

        // Get new ECID on first launch
        if identityEdgeProperties.ecid == nil {
            if let ecid = identityEdgeProperties.getEcidFromDirectIdentityPersistence() {
                identityEdgeProperties.ecid = ecid // get ECID from direct extension
                Log.debug(label: LOG_TAG, "Bootup - Loading ECID from direct Identity extension '\(ecid)'")
            } else {
                identityEdgeProperties.ecid = ECID() // generate new ECID
                Log.debug(label: LOG_TAG, "Bootup - Generating new ECID '\(identityEdgeProperties.ecid)'")
            }
            identityEdgeProperties.saveToPersistence()
        }

        hasBooted = true
        Log.debug(label: LOG_TAG, "Identity Edge has successfully booted up")
        return true
    }

    /// When the advertising identifier from the `event` is different from the current value, it updates the persisted value and creates
    /// new shared state and XDM shared state. A consent request event is dispatched when advertising tracking preferences change.
    /// If privacy is optedout the call is ignored
    /// - Parameters:
    ///   - event: event containing a new ADID value.
    ///   - createXDMSharedState: function which creates new XDM shared state
    ///   - dispatchEvent: function which dispatchs events to the event hub
    func updateAdvertisingIdentifier(event: Event,
                                     createXDMSharedState: ([String: Any], Event) -> Void,
                                     dispatchEvent: (Event) -> Void) {

        // update adid if changed and extract the new adid value
        let (adIdChanged, shouldUpdateConsent) = shouldUpdateAdId(newAdID: event.adId)
        if adIdChanged, let adId = event.adId {
            identityEdgeProperties.advertisingIdentifier = adId

            if shouldUpdateConsent {
                let val = adId.isEmpty ? IdentityEdgeConstants.XDMKeys.Consent.NO : IdentityEdgeConstants.XDMKeys.Consent.YES
                dispatchAdIdConsentRequestEvent(val: val, dispatchEvent: dispatchEvent)
            }

            saveToPersistence(and: createXDMSharedState, using: event)
        }

    }

    /// Update the customer identifiers by merging `updateIdentityMap` with the current identifiers. Any identifier in `updateIdentityMap` which
    /// has the same id in the same namespace will update the current identifier.
    /// Certain namespaces are not allowed to be modified and if exist in the given customer identifiers will be removed before the update operation is executed.
    /// The namespaces which cannot be modified through this function call include:
    /// - ECID
    /// - IDFA
    ///
    /// - Parameters
    ///   - event: event containing customer identifiers to add or update with the current customer identifiers
    ///   - createXDMSharedState: function which creates new XDM shared state
    func updateCustomerIdentifiers(event: Event, createXDMSharedState: ([String: Any], Event) -> Void) {
        guard let identifiersData = event.data else {
            Log.debug(label: LOG_TAG, "Failed to update identifiers as no identifiers were found in the event data.")
            return
        }

        guard let updateIdentityMap = IdentityMap.from(eventData: identifiersData) else {
            Log.debug(label: LOG_TAG, "Failed to update identifiers as the event data could not be encoded to an IdentityMap.")
            return
        }

        // Filter out known identifiers to prevent modification of certain namespaces
        removeIdentitiesWithReservedNamespaces(from: updateIdentityMap)

        if identityEdgeProperties.customerIdentifiers == nil {
            identityEdgeProperties.customerIdentifiers = updateIdentityMap
        } else {
            identityEdgeProperties.customerIdentifiers?.merge(map: updateIdentityMap)
        }

        saveToPersistence(and: createXDMSharedState, using: event)
    }

    /// Remove customer identifiers specified in `event` from the current `IdentityMap`.
    /// - Parameters:
    ///   - event: event containing customer identifiers to remove from the current customer identities
    ///   - createXDMSharedState: function which creates new XDM shared states
    func removeCustomerIdentifiers(event: Event, createXDMSharedState: ([String: Any], Event) -> Void) {
        guard let identifiersData = event.data else {
            Log.debug(label: LOG_TAG, "Failed to remove identifier as no identifiers were found in the event data.")
            return
        }

        guard let removeIdentityMap = IdentityMap.from(eventData: identifiersData) else {
            Log.debug(label: LOG_TAG, "Failed to remove identifier as the event data could not be encoded to an IdentityMap.")
            return
        }

        guard let customerIdentityMap = identityEdgeProperties.customerIdentifiers else {
            return
        }

        customerIdentityMap.remove(map: removeIdentityMap)

        saveToPersistence(and: createXDMSharedState, using: event)
    }

    /// Clears all identities and regenerates a new ECID value. Saves identites to persistance and creates a new XDM shared state after operation completes.
    /// Dispatches Consent request event setting `adId` to 'no' if previous advertising identifier is nil or empty
    /// - Parameters:
    ///   - event: event which triggered the reset call
    ///   - createXDMSharedState: function which creates new XDM shared states
    ///   - dispatchEvent: function which dispatches event to the event hub
    func resetIdentifiers(event: Event,
                          createXDMSharedState: ([String: Any], Event) -> Void,
                          dispatchEvent: (Event) -> Void) {
        let shouldDispatchConsent = identityEdgeProperties.advertisingIdentifier != nil && !(identityEdgeProperties.advertisingIdentifier?.isEmpty ?? true)

        identityEdgeProperties.advertisingIdentifier = nil
        identityEdgeProperties.customerIdentifiers = nil
        identityEdgeProperties.ecid = ECID()

        saveToPersistence(and: createXDMSharedState, using: event)
        if shouldDispatchConsent {
            dispatchAdIdConsentRequestEvent(val: IdentityEdgeConstants.XDMKeys.Consent.NO, dispatchEvent: dispatchEvent)
        }
    }

    /// Update the legacy ECID property with `legacyEcid` provided it does not equal the current ECID or legacy ECID.
    /// - Parameter legacyEcid: the current ECID for the Identity Direct extension
    /// - Returns: true if the legacy ECID was updated, or false if the legacy ECID did not change
    func updateLegacyExperienceCloudId(_ legacyEcid: String) -> Bool {
        if legacyEcid == identityEdgeProperties.ecid?.ecidString || legacyEcid == identityEdgeProperties.ecidLegacy {
            return false
        }

        identityEdgeProperties.ecidLegacy = legacyEcid
        identityEdgeProperties.saveToPersistence()
        return true
    }

    /// Determines if we should update the advertising identifier with `newAdID` and if the advertising tracking consent has changed.
    /// - Parameter newAdID: the new ad id
    /// - Returns: A tuple indicating if the ad id has changed, and if the consent should be updated
    private func shouldUpdateAdId(newAdID: String?) -> (adIdChanged: Bool, updateConsent: Bool) {
        guard let newAdID = newAdID else { return (false, false) }

        guard let existingAdId = identityEdgeProperties.advertisingIdentifier else {
            // existing is nil but new is not, update with new and update consent
            // covers first call case where existing ad ID is not set and new ad ID is empty/all zeros
            return (true, true)
        }

        // did the advertising identifier change?
        if (!newAdID.isEmpty && newAdID != existingAdId)
            || (newAdID.isEmpty && !existingAdId.isEmpty) {
            // Now we know the value changed, but did it change to/from null?
            // Handle case where existingAdId loaded from persistence with all zeros and new value is not empty.
            if newAdID.isEmpty || existingAdId.isEmpty || existingAdId == IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID {
                return (true, true)
            }

            return (true, false)
        }

        return (false, false)
    }

    /// Dispatch a consent request `Event` with `EventType.consent` and `EventSource.requestContent` which contains the consent value specifying
    /// new advertising tracking preferences.
    /// - Parameters:
    ///   -  val: The new adId consent value, either "y" or "n"
    ///   - dispatchEvent: a function which sends an event to the event hub
    private func dispatchAdIdConsentRequestEvent(val: String, dispatchEvent: (Event) -> Void) {
        let event = Event(name: IdentityEdgeConstants.EventNames.CONSENT_REQUEST_AD_ID,
                          type: EventType.consent,
                          source: EventSource.requestContent,
                          data: [IdentityEdgeConstants.XDMKeys.Consent.CONSENTS:
                                    [IdentityEdgeConstants.XDMKeys.Consent.AD_ID:
                                        [IdentityEdgeConstants.XDMKeys.Consent.VAL: val]
                                    ]
                          ])
        dispatchEvent(event)
    }

    /// Filter out any items contained in reserved namespaces from the given `identityMap`.
    /// The list of reserved namespaces can be found at `IdentityState.reservedNamespaces`.
    /// - Parameter identityMap: the `IdentityMap` to filter out items contained in reserved namespaces.
    private func removeIdentitiesWithReservedNamespaces(from identityMap: IdentityMap) {
        // Filter out known identifiers to prevent modification of certain namespaces
        let filterItems = IdentityMap()
        for namespace in IdentityEdgeState.reservedNamespaces {
            if let items = identityMap.getItems(withNamespace: namespace) {
                Log.debug(label: LOG_TAG, "Adding/Updating identifiers in namespace '\(namespace)' is not allowed.")
                for item in items {
                    filterItems.add(item: item, withNamespace: namespace)
                }
            }
        }

        if !filterItems.isEmpty {
            identityMap.remove(map: filterItems)
        }
    }

    /// Save `identityEdgeProperties` to persistence and create an XDM shared state.
    /// - Parameters:
    ///   - createXDMSharedState: function which creates an XDM shared state
    ///   - event: the event used to share the XDM state
    private func saveToPersistence(and createXDMSharedState: ([String: Any], Event) -> Void, using event: Event) {
        identityEdgeProperties.saveToPersistence()
        createXDMSharedState(identityEdgeProperties.toXdmData(), event)
    }
}
