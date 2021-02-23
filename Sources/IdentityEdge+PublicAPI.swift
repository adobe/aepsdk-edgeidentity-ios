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
@objc public extension IdentityEdge {
    private static let LOG_TAG = "IdentityEdge"

    /// Returns the Experience Cloud ID, or an `AEPError` if any occurred. An empty string is returned if the Experience Cloud ID was previously cleared.
    /// - Parameter completion: closure which will be invoked once Experience Cloud ID is available, along with an 'AEPError'' if any occurred
    @objc(getExperienceCloudId:)
    static func getExperienceCloudId(completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: IdentityEdgeConstants.EventNames.REQUEST_IDENTITY_ECID,
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: nil)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, AEPError.callbackTimeout)
                return
            }

            guard let data = responseEvent.data?[IdentityEdgeConstants.XDMKeys.IDENTITY_MAP] as? [String: Any],
                  let identityMap = IdentityMap.from(eventData: data) else {
                completion(nil, AEPError.unexpected)
                return
            }

            guard let items = identityMap.getItems(withNamespace: IdentityEdgeConstants.Namespaces.ECID), let ecidItem = items.first else {
                completion("", .none) // IdentityMap exists but ECID has no value, return an empty string
                return
            }

            completion(ecidItem.id, .none)
        }
    }

    /// Returns all  identifiers, including customer identifiers which were previously added, or an `AEPError` if any occurred. If there are no identifiers stored
    /// in the `IdentityEdge` extension, then an empty `IdentityMap` is returned.
    /// - Parameter completion: closure which will be invoked once the identifiers are available, along with an 'AEPError' if any occurred
    @objc(getIdentities:)
    static func getIdentities(completion: @escaping (IdentityMap?, Error?) -> Void) {
        let event = Event(name: IdentityEdgeConstants.EventNames.REQUEST_IDENTITIES,
                          type: EventType.identityEdge,
                          source: EventSource.requestIdentity,
                          data: nil)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, AEPError.callbackTimeout)
                return
            }

            guard let data = responseEvent.data?[IdentityEdgeConstants.XDMKeys.IDENTITY_MAP] as? [String: Any],
                  let identityMap = IdentityMap.from(eventData: data) else {
                completion(nil, AEPError.unexpected)
                return
            }

            completion(identityMap, .none)
        }
    }

    /// Updates the currently known `IdentityMap` within the SDK and XDM shared state. The IdentityEdge extension will merge the received identifiers
    ///  with the previously saved one in an additive manner, no identifiers will be removed using this API.
    ///  Identifiers which have an empty  `id` or empty `namespace` are not allowed and are ignored.
    /// - Parameter map: The identifiers to add or update
    @objc(updateIdentitiesWith:)
    static func updateIdentities(with map: IdentityMap) {
        guard !map.isEmpty, let identityDict = map.asDictionary() else {
            Log.debug(label: LOG_TAG, "Unable to updateIdentites as IdentityMap is empty or could not be encoded to a dictionary.")
            return
        }

        let event = Event(name: IdentityEdgeConstants.EventNames.UPDATE_IDENTITIES,
                          type: EventType.identityEdge,
                          source: EventSource.updateIdentity,
                          data: identityDict)

        MobileCore.dispatch(event: event)
    }

    /// Removes the identity from the stored client-side `IdentityMap` and XDM shared state. The IdentityEdge extension will stop sending this identifier.
    /// This does not clear the identifier from the User Profile Graph.
    /// Identifiers which have an empty `id` or empty `namespace` are not allowed and are ignored.
    /// - Parameters:
    ///   - item: The identity to remove.
    ///   - withNamespace: The namespace the identity to remove is under.
    @objc(removeIdentityItem:withNamespace:)
    static func removeIdentity(item: IdentityItem, withNamespace: String) {
        let identities = IdentityMap()
        identities.add(item: item, withNamespace: withNamespace)

        guard !identities.isEmpty, let identityDict = identities.asDictionary() else {
            Log.debug(label: LOG_TAG, "Unable to removeIdentity as IdentityItem is empty or could not be encoded to a dictionary.")
            return
        }

        let event = Event(name: IdentityEdgeConstants.EventNames.REMOVE_IDENTITIES,
                          type: EventType.identityEdge,
                          source: EventSource.removeIdentity,
                          data: identityDict)

        MobileCore.dispatch(event: event)
    }

    /// Clears all identifiers and generates a new Experience Cloud ID (ECID).
    @objc(resetIdentities)
    static func resetIdentities() {
        let event = Event(name: IdentityEdgeConstants.EventNames.REQUEST_RESET,
                          type: EventType.identityEdge,
                          source: EventSource.requestReset,
                          data: nil)

        MobileCore.dispatch(event: event)
    }
}
