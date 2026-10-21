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

/// Defines the public interface for the Identity extension
@objc public extension Identity {

    /// Returns the Experience Cloud ID, or an `AEPError` if any occurred. An empty string is returned if the Experience Cloud ID was previously cleared.
    /// - Parameter completion: invoked once the Experience Cloud ID is available, or
    ///                         an `AEPError` if an unexpected error occurs or the request timed out.
    @objc(getExperienceCloudId:)
    static func getExperienceCloudId(completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: IdentityConstants.EventNames.REQUEST_IDENTITY_ECID,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestIdentity,
                          data: nil)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, AEPError.callbackTimeout)
                return
            }

            guard let data = responseEvent.data?[IdentityConstants.XDMKeys.IDENTITY_MAP] as? [String: Any],
                  let identityMap = IdentityMap.from(eventData: data) else {
                completion(nil, AEPError.unexpected)
                return
            }

            guard let items = identityMap.getItems(withNamespace: IdentityConstants.Namespaces.ECID), let ecidItem = items.first else {
                completion("", .none) // IdentityMap exists but ECID has no value, return an empty string
                return
            }

            completion(ecidItem.id, nil)
        }
    }

    /// Returns the identifiers in URL query parameter format for consumption in hybrid mobile applications.
    /// There is no leading & or ? punctuation as the caller is responsible for placing the variables in their resulting URL in the correct locations.
    /// If an error occurs while retrieving the URL variables, the completion handler is called with a nil value and AEPError instance.
    /// Otherwise, the encoded string is returned, for ex: `"adobe_mc=TS%3DTIMESTAMP_VALUE%7CMCMID%3DYOUR_ECID%7CMCORGID%3D9YOUR_EXPERIENCE_CLOUD_ID"`
    /// The `adobe_mc` attribute is an URL encoded list that contains:
    ///     - TS: a timestamp taken when the request was made
    ///     - MCMID: Experience Cloud ID (ECID)
    ///     - MCORGID: Experience Cloud Org ID
    /// - Parameter completion: invoked with a value containing the identifiers in query parameter format or an AEPError if an unexpected error occurs or the request times out.
    @objc(getUrlVariables:)
    static func getUrlVariables(completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: IdentityConstants.EventNames.REQUEST_IDENTITY_URL_VARIABLES,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestIdentity,
                          data: [IdentityConstants.EventDataKeys.URL_VARIABLES: true])

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, AEPError.callbackTimeout)
                return
            }

            guard let urlVariables = responseEvent.data?[IdentityConstants.EventDataKeys.URL_VARIABLES] as? String, !urlVariables.isEmpty else {
                completion(nil, AEPError.unexpected)
                return
            }

            completion(urlVariables, nil)
        }
    }

    /// Returns all  identifiers, including customer identifiers which were previously added, or an `AEPError` if an unexpected error occurs or the request timed out.
    /// If there are no identifiers stored in the `Identity` extension, then an empty `IdentityMap` is returned.
    /// - Parameter completion: invoked once the identifiers are available, or
    ///                         an `AEPError` if an unexpected error occurs or the request timed out.
    @objc(getIdentities:)
    static func getIdentities(completion: @escaping (IdentityMap?, Error?) -> Void) {
        let event = Event(name: IdentityConstants.EventNames.REQUEST_IDENTITIES,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestIdentity,
                          data: nil)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, AEPError.callbackTimeout)
                return
            }

            guard let data = responseEvent.data?[IdentityConstants.XDMKeys.IDENTITY_MAP] as? [String: Any],
                  let identityMap = IdentityMap.from(eventData: data) else {
                completion(nil, AEPError.unexpected)
                return
            }

            completion(identityMap, nil)
        }
    }

    /// Updates the currently known `IdentityMap` within the SDK. The Identity extension will merge the received identifiers
    /// with the previously saved one in an additive manner, no identifiers will be removed using this API.
    /// Identifiers which have an empty  `id` or empty `namespace` are not allowed and are ignored.
    /// - Parameter map: The identifiers to add or update
    @objc(updateIdentities:)
    static func updateIdentities(with map: IdentityMap) {
        guard !map.isEmpty, let identityDict = map.asDictionary() else {
            Log.debug(label: IdentityConstants.LOG_TAG, "Identity - Unable to updateIdentites as IdentityMap is empty or could not be encoded to a dictionary.")
            return
        }

        let event = Event(name: IdentityConstants.EventNames.UPDATE_IDENTITIES,
                          type: EventType.edgeIdentity,
                          source: EventSource.updateIdentity,
                          data: identityDict)

        MobileCore.dispatch(event: event)
    }

    /// Updates operational data that should be delivered to the Edge Network
    /// **independently of collect consent**.
    ///
    /// Accepts an open map. Only values that a Launch rule allows are sent to Edge.
    /// The timezone (`timezone`), push token (`tokens.pushNotification`) and Live Activity push-to-start tokens
    /// (`tokens.liveActivityStart`) are sent only when they change from the last values Edge confirmed, whatever the
    /// collect consent; all other values are always sent.
    /// When collect consent is `"y"`, or the Consent extension is not registered, they are also not sent when they
    /// match the timezone set through the profile attributes API or Messaging's push token and push-to-start tokens
    /// (disable all comparisons with `edgeidentity.optimizeOperationalProfileDataSync: false`).
    /// Values from a failed request are not stored as confirmed, so a later API call may send them again.
    /// Every dispatched update also carries an SDK-generated `app { id, platform }` entry, using the bundle identifier
    /// and the latest `messaging.useSandbox` setting at send time. Caller-provided `app` values do not override routing.
    ///
    /// - Parameter attributes: Map of attribute key to a JSON-compatible value (`String`, `NSNumber`/`Bool`,
    ///   or arrays/dictionaries of those). Values are not validated by the SDK and are sent as provided.
    ///   An empty map is a no-op.
    @objc(updateOperationalData:)
    static func updateOperationalData(_ attributes: [String: Any]) {
        guard !attributes.isEmpty else {
            Log.warning(label: IdentityConstants.LOG_TAG, "Identity - Unable to update operational data, attributes are null or empty.")
            return
        }
        let event = Event(name: IdentityConstants.EventNames.UPDATE_OPERATIONAL_DATA,
                          type: EventType.edgeIdentity,
                          source: EventSource.requestContent,
                          data: attributes)
        MobileCore.dispatch(event: event)
    }

    /// Removes the identity from the stored client-side `IdentityMap`. The Identity extension will stop sending this identifier.
    /// This does not clear the identifier from the User Profile Graph.
    /// - Parameters:
    ///   - item: The identity to remove.
    ///   - withNamespace: The namespace of the identity to remove.
    @objc(removeIdentityItem:withNamespace:)
    static func removeIdentity(item: IdentityItem, withNamespace: String) {
        let identities = IdentityMap()
        identities.add(item: item, withNamespace: withNamespace)

        guard !identities.isEmpty, let identityDict = identities.asDictionary() else {
            Log.debug(label: IdentityConstants.LOG_TAG, "Identity - Unable to removeIdentity as IdentityItem is empty or could not be encoded to a dictionary.")
            return
        }

        let event = Event(name: IdentityConstants.EventNames.REMOVE_IDENTITIES,
                          type: EventType.edgeIdentity,
                          source: EventSource.removeIdentity,
                          data: identityDict)

        MobileCore.dispatch(event: event)
    }
}
