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

/// Represents a type which contains instances variables for the Identity Edge extension
struct IdentityEdgeProperties: Codable {
    /// The current Experience Cloud ID
    var ecid: ECID?

    /// The IDFA from retrieved Apple APIs
    var advertisingIdentifier: String?

    /// Customer Identifiers.
    var customerIdentifiers: IdentityMap?

    /// The current privacy status provided by the Configuration extension, defaults to `unknown`
    var privacyStatus = IdentityEdgeConstants.Default.PRIVACY_STATUS

    /// Converts `identityEdgeProperties` into an event data representation in XDM format
    /// - Parameter allowEmpty: If this `identityEdgeProperties` contains no data, return a dictionary with a single `identityMap` key
    /// to represent an empty IdentityMap when `allowEmpty` is true
    /// - Returns: A dictionary representing this `identityEdgeProperties` in XDM format
    func toXdmData(_ allowEmpty: Bool = false) -> [String: Any] {
        var map: [String: Any] = [:]

        let identityMap = IdentityMap()

        // add ECID
        if let ecid = ecid {
            identityMap.add(item: IdentityItem(id: ecid.ecidString, authenticationState: .ambiguous, primary: true),
                            withNamespace: IdentityEdgeConstants.Namespaces.ECID)
        }

        // add IDFA
        if let adId = advertisingIdentifier, !adId.isEmpty {
            identityMap.add(item: IdentityItem(id: adId),
                            withNamespace: IdentityEdgeConstants.Namespaces.IDFA)
        }

        // add identifiers
        if let customerIdentifiers = customerIdentifiers, !customerIdentifiers.isEmpty {
            identityMap.merge(map: customerIdentifiers)
        }

        // encode to event data
        if let dict = identityMap.asDictionary(), !dict.isEmpty || allowEmpty {
            map[IdentityEdgeConstants.XDMKeys.IDENTITY_MAP] = dict
        }

        return map
    }

    /// Populates the fields with values stored in the Identity Edge data store
    mutating func loadFromPersistence() {
        let dataStore = NamedCollectionDataStore(name: IdentityEdgeConstants.DATASTORE_NAME)
        let savedProperties: IdentityEdgeProperties? = dataStore.getObject(key: IdentityEdgeConstants.DataStoreKeys.IDENTITY_PROPERTIES)

        if let savedProperties = savedProperties {
            self = savedProperties
        }
    }

    /// Saves this instance of `IdentityEdgeProperties` to the Identity data store
    func saveToPersistence() {
        let dataStore = NamedCollectionDataStore(name: IdentityEdgeConstants.DATASTORE_NAME)
        dataStore.setObject(key: IdentityEdgeConstants.DataStoreKeys.IDENTITY_PROPERTIES, value: self)
    }

}
