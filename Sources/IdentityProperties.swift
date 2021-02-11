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

/// Represents a type which contains instances variables for the Identity extension
struct IdentityProperties: Codable {
    /// The current Experience Cloud ID
    var ecid: ECID?

    /// The IDFA from retrieved Apple APIs
    var advertisingIdentifier: String?

    /// Customer Identifiers.
    var customerIdentifiers: IdentityMap?

    /// The current privacy status provided by the Configuration extension, defaults to `unknown`
    var privacyStatus = IdentityConstants.Default.PRIVACY_STATUS

    /// Converts `IdentityProperties` into an event data representation
    /// - Returns: A dictionary representing this `IdentityProperties`
    func toEventData() -> [String: Any] {
        var eventData = [String: Any]()
        eventData[IdentityConstants.EventDataKeys.VISITOR_ID_ECID] = ecid?.ecidString
        if let adId = advertisingIdentifier, !adId.isEmpty {
            eventData[IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] = advertisingIdentifier
        }
        return eventData
    }

    /// Converts `IdentityProperties` into an event data representation in XDM format
    /// - Parameter allowEmpty: If this `IdentityProperties` contains no data, return a dictionary with a single `identityMap` key
    /// to represent an empty IdentityMap when `allowEmpty` is true
    /// - Returns: A dictionary representing this `IdentityProperties` in XDM format
    func toXdmData(_ allowEmpty: Bool = false) -> [String: Any] {
        var map: [String: Any] = [:]

        let identityMap = IdentityMap()

        // add ECID
        if let ecid = ecid {
            identityMap.add(item: IdentityItem(id: ecid.ecidString, authenticationState: .ambiguous, primary: true),
                            withNamespace: IdentityConstants.Namespaces.ECID)
        }

        // add IDFA
        if let adId = advertisingIdentifier, !adId.isEmpty {
            identityMap.add(item: IdentityItem(id: adId),
                            withNamespace: IdentityConstants.Namespaces.IDFA)
        }

        // add identifiers
        if let customerIdentifiers = customerIdentifiers {
            identityMap.merge(customerIdentifiers)
        }

        // encode to event data
        if let dict = identityMap.asDictionary(), !dict.isEmpty || allowEmpty {
            map[IdentityConstants.XDMKeys.IDENTITY_MAP] = dict
        }

        return map
    }

    /// Populates the fields with values stored in the Identity data store
    mutating func loadFromPersistence() {
        let dataStore = NamedCollectionDataStore(name: IdentityConstants.DATASTORE_NAME)
        let savedProperties: IdentityProperties? = dataStore.getObject(key: IdentityConstants.DataStoreKeys.IDENTITY_PROPERTIES)

        if let savedProperties = savedProperties {
            self = savedProperties
        }
    }

    /// Saves this instance of `IdentityProperties` to the Identity data store
    func saveToPersistence() {
        let dataStore = NamedCollectionDataStore(name: IdentityConstants.DATASTORE_NAME)
        dataStore.setObject(key: IdentityConstants.DataStoreKeys.IDENTITY_PROPERTIES, value: self)
    }

}
