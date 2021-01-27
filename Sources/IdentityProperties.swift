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

    /// The current privacy status provided by the Configuration extension, defaults to `unknown`
    var privacyStatus = PrivacyStatus.unknown

    /// Converts `IdentityProperties` into an event data representation
    /// - Returns: A dictionary representing this `IdentityProperties`
    func toEventData() -> [String: Any] {
        var eventData = [String: Any]()
        eventData[IdentityEdgeConstants.EventDataKeys.VISITOR_ID_ECID] = ecid?.ecidString
        return eventData
    }

    /// Converts `IdentityProperties` into an event data representation in XDM format
    /// - Returns: A dictionary representing this `IdentityProperties` in XDM format
    func toXdmData() -> [String: Any] {
        var map: [String: Any] = [:]

        var identityMap = IdentityMap()
        if let ecid = ecid {
            identityMap.addItem(namespace: IdentityEdgeConstants.Namespaces.ECID,
                                id: ecid.ecidString)
        }

        if let dict = identityMap.asDictionary() {
            map[IdentityEdgeConstants.XDMKeys.IDENTITY_MAP] = dict
        }

        return map
    }

    /// Populates the fields with values stored in the Identity data store
    mutating func loadFromPersistence() {
        let dataStore = NamedCollectionDataStore(name: IdentityEdgeConstants.DATASTORE_NAME)
        let savedProperties: IdentityProperties? = dataStore.getObject(key: IdentityEdgeConstants.DataStoreKeys.IDENTITY_PROPERTIES)

        if let savedProperties = savedProperties {
            self = savedProperties
        }
    }

    /// Saves this instance of `IdentityProperties` to the Identity data store
    func saveToPersistence() {
        let dataStore = NamedCollectionDataStore(name: IdentityEdgeConstants.DATASTORE_NAME)
        dataStore.setObject(key: IdentityEdgeConstants.DataStoreKeys.IDENTITY_PROPERTIES, value: self)
    }

}
