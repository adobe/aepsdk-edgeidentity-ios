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
        let privacyStatusString = configSharedState[IdentityEdgeConstants.Configuration.GLOBAL_CONFIG_PRIVACY] as? String ?? ""
        identityProperties.privacyStatus = PrivacyStatus(rawValue: privacyStatusString) ?? IdentityEdgeConstants.Default.PRIVACY_STATUS

        // Generate new ECID if privacy status allows
        if identityProperties.privacyStatus != .optedOut && identityProperties.ecid == nil {
            identityProperties.ecid = ECID()
        }

        hasBooted = true
        Log.debug(label: LOG_TAG, "Identity has successfully booted up")
        return true
    }

    /// Sets the advertising identifier from the `event` if changed from current value.
    /// Updates the persistence values for the ad id and creates new shared state
    /// Dispatches consent request event if advertising ID consent changed.
    /// If privacy is optedout, call is ignored
    /// - Parameters:
    ///   - event: event containing a new ADID value.
    ///   - createSharedState: function which creates a new shared state
    ///   - createXDMSharedState: function which creates new XDM shared state
    func syncAdvertisingIdentifier(event: Event,
                                   createSharedState: ([String: Any], Event) -> Void,
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
                // TODO use Consent object
                let val = adId.isEmpty ? "n" : "y"
                let consentPayload = ["consents": ["adId": ["val": val]]]
                let event = Event(name: "IDFA Consent Request", type: "consent", source: EventSource.requestContent, data: consentPayload)
                dispatchEvent(event)
            }

            identityProperties.saveToPersistence()
            createSharedState(identityProperties.toEventData(), event)
            createXDMSharedState(identityProperties.toXdmData(), event)
        }

    }

    /// Updates and makes any required actions when the privacy status has updated
    /// - Parameters:
    ///   - event: the event triggering the privacy change
    ///   - createSharedState: a function which can create Identity shared state
    ///   - createXDMSharedState: a function which can create XDM formatted Identity shared states
    func processPrivacyChange(event: Event, createSharedState: ([String: Any], Event) -> Void, createXDMSharedState: ([String: Any], Event) -> Void) {
        let privacyStatusStr = event.data?[IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY] as? String ?? ""
        let newPrivacyStatus = PrivacyStatus(rawValue: privacyStatusStr) ?? PrivacyStatus.unknown

        if newPrivacyStatus == identityProperties.privacyStatus {
            return
        }

        identityProperties.privacyStatus = newPrivacyStatus

        if newPrivacyStatus == .optedOut {
            identityProperties.ecid = nil
            identityProperties.advertisingIdentifier = nil
            identityProperties.saveToPersistence()
            createSharedState(identityProperties.toEventData(), event)
            createXDMSharedState(identityProperties.toXdmData(), event)
        } else if identityProperties.ecid == nil {
            // When changing privacy status from optedout, need to generate a new Experience Cloud ID for the user
            identityProperties.ecid = ECID()
            identityProperties.saveToPersistence()
            createSharedState(identityProperties.toEventData(), event)
            createXDMSharedState(identityProperties.toXdmData(), event)
        }

    }

    /// Determines if we should update the ad id with `newAdID`
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
            if newAdID.isEmpty || existingAdId.isEmpty || existingAdId == IdentityEdgeConstants.Default.ZERO_ADVERTISING_ID {
                return (true, true)
            }

            return (true, false)
        }

        return (false, false)
    }

}
