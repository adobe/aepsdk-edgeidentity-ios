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

/// Manages the business logic of the Identity extension
class IdentityState {
    private let LOG_TAG = "IdentityState"
    private(set) var hasBooted = false
    #if DEBUG
    var identityProperties: IdentityProperties
    #else
    private(set) var identityProperties: IdentityProperties
    #endif

    /// List of namespaces which are not allowed to be modified from customer identifier
    private static let reservedNamspaces = [
        IdentityConstants.Namespaces.ECID,
        IdentityConstants.Namespaces.IDFA
    ]

    /// Creates a new `IdentityState` with the given identity properties
    /// - Parameter identityProperties: identity properties
    init(identityProperties: IdentityProperties) {
        self.identityProperties = identityProperties
    }

    /// Completes init for the Identity extension.
    /// - Parameters:
    ///   - configSharedState: the current configuration shared state available at registration time
    ///   - event: The `Event` triggering the bootup
    /// - Returns: True if we should share state after bootup, false otherwise
    func bootupIfReady(configSharedState: [String: Any], event: Event) -> Bool {

        // load data from local storage
        identityProperties.loadFromPersistence()

        // Load privacy status
        let privacyStatusString = configSharedState[IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY] as? String ?? ""
        identityProperties.privacyStatus = PrivacyStatus(rawValue: privacyStatusString) ?? IdentityConstants.Default.PRIVACY_STATUS

        // Generate new ECID if privacy status allows
        if identityProperties.privacyStatus != .optedOut && identityProperties.ecid == nil {
            identityProperties.ecid = ECID()
        }

        hasBooted = true
        Log.debug(label: LOG_TAG, "Identity has successfully booted up")
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

        // Early exit if privacy is opt-out
        if identityProperties.privacyStatus == .optedOut {
            Log.debug(label: LOG_TAG, "Ignoring sync advertising identifiers request as privacy is opted-out")
            return
        }

        // update adid if changed and extract the new adid value
        let (adIdChanged, shouldUpdateConsent) = shouldUpdateAdId(newAdID: event.adId)
        if adIdChanged, let adId = event.adId {
            identityProperties.advertisingIdentifier = adId

            if shouldUpdateConsent {
                let val = adId.isEmpty ? IdentityConstants.XDMKeys.Consent.NO : IdentityConstants.XDMKeys.Consent.YES
                dispatchAdIdConsentRequestEvent(val: val, dispatchEvent: dispatchEvent)
            }

            identityProperties.saveToPersistence()
            createXDMSharedState(identityProperties.toXdmData(), event)
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
            Log.debug(label: LOG_TAG, "Failed to update customer identifiers as no identifiers were found in the event data.")
            return
        }

        guard let updateIdentityMap = IdentityMap.from(eventData: identifiersData) else {
            Log.debug(label: LOG_TAG, "Failed to update customer identifiers as the event data could not be encoded to an IdentityMap.")
            return
        }

        // Filter out known identifiers to prevent modification of certain namespaces
        removeIdentitiesWithReservedNamespaces(from: updateIdentityMap)

        if identityProperties.customerIdentifiers == nil {
            identityProperties.customerIdentifiers = updateIdentityMap
        } else {
            identityProperties.customerIdentifiers?.merge(map: updateIdentityMap)
        }

        identityProperties.saveToPersistence()
        createXDMSharedState(identityProperties.toXdmData(), event)
    }

    /// Remove customer identifiers specified in `event` from the current `IdentityMap`.
    /// - Parameters:
    ///   - event: event containing customer identifiers to remove from the current customer identities
    ///   - createXDMSharedState: function which creates new XDM shared states
    func removeCustomerIdentifiers(event: Event, createXDMSharedState: ([String: Any], Event) -> Void) {
        guard let identifiersData = event.data else {
            Log.debug(label: LOG_TAG, "Failed to remove customer identifier as no identifiers were found in the event data.")
            return
        }

        guard let removeIdentityMap = IdentityMap.from(eventData: identifiersData) else {
            Log.debug(label: LOG_TAG, "Failed to remove customer identifier as the event data could not be encoded to an IdentityMap.")
            return
        }

        guard let customerIdentityMap = identityProperties.customerIdentifiers else {
            return
        }

        customerIdentityMap.remove(map: removeIdentityMap)

        identityProperties.saveToPersistence()
        createXDMSharedState(identityProperties.toXdmData(), event)
    }

    /// Updates and makes any required actions when the privacy status has updated
    /// - Parameters:
    ///   - event: the event triggering the privacy change
    ///   - createXDMSharedState: a function which can create XDM formatted Identity shared states
    func processPrivacyChange(event: Event, createXDMSharedState: ([String: Any], Event) -> Void) {
        let privacyStatusStr = event.data?[IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY] as? String ?? ""
        let newPrivacyStatus = PrivacyStatus(rawValue: privacyStatusStr) ?? PrivacyStatus.unknown

        if newPrivacyStatus == identityProperties.privacyStatus {
            return
        }

        identityProperties.privacyStatus = newPrivacyStatus

        if newPrivacyStatus == .optedOut {
            identityProperties.ecid = nil
            identityProperties.advertisingIdentifier = nil
            identityProperties.customerIdentifiers = nil
            identityProperties.saveToPersistence()
            createXDMSharedState(identityProperties.toXdmData(), event)
        } else if identityProperties.ecid == nil {
            // When changing privacy status from optedout, need to generate a new Experience Cloud ID for the user
            identityProperties.ecid = ECID()
            identityProperties.saveToPersistence()
            createXDMSharedState(identityProperties.toXdmData(), event)
        }

    }

    /// Determines if we should update the advertising identifier with `newAdID` and if the advertising tracking consent has changed.
    /// - Parameter newAdID: the new ad id
    /// - Returns: A tuple indicating if the ad id has changed, and if the consent should be updated
    private func shouldUpdateAdId(newAdID: String?) -> (adIdChanged: Bool, updateConsent: Bool) {
        guard let newAdID = newAdID else { return (false, false) }

        guard let existingAdId = identityProperties.advertisingIdentifier else {
            // existing is nil but new is not, update with new and update consent
            // covers first call case where existing ad ID is not set and new ad ID is empty/all zeros
            return (true, true)
        }

        // did the advertising identifier change?
        if (!newAdID.isEmpty && newAdID != existingAdId)
            || (newAdID.isEmpty && !existingAdId.isEmpty) {
            // Now we know the value changed, but did it change to/from null?
            // Handle case where existingAdId loaded from persistence with all zeros and new value is not empty.
            if newAdID.isEmpty || existingAdId.isEmpty || existingAdId == IdentityConstants.Default.ZERO_ADVERTISING_ID {
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
        let event = Event(name: IdentityConstants.EventNames.CONSENT_REQUEST_AD_ID,
                          type: EventType.consent,
                          source: EventSource.requestContent,
                          data: [IdentityConstants.XDMKeys.Consent.CONSENTS:
                                    [IdentityConstants.XDMKeys.Consent.AD_ID:
                                        [IdentityConstants.XDMKeys.Consent.VAL: val]
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
        for namespace in IdentityState.reservedNamspaces {
            if let items = identityMap.getItems(withNamespace: namespace) {
                Log.debug(label: LOG_TAG, "Adding/Updating customer identifiers in namespace '\(namespace)' is not allowed.")
                for item in items {
                    filterItems.add(item: item, withNamespace: namespace)
                }
            }
        }

        if !filterItems.isEmpty {
            identityMap.remove(map: filterItems)
        }
    }
}
