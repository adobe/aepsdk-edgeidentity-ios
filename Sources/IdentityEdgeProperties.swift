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
    private static let LOG_TAG = "IdentityEdgeProperties"

    /// List of namespaces which are not allowed to be modified from customer identifier
    private static let reservedNamespaces = [
        IdentityEdgeConstants.Namespaces.ECID,
        IdentityEdgeConstants.Namespaces.IDFA
    ]

    /// The underlying IdentityMap structure which holds all the properties
    private(set) var identityMap: IdentityMap = IdentityMap()

    /// The current Experience Cloud ID
    var ecid: String? {
        get {
            return getPrimaryEcid()
        }

        set {
            // Remove previous ECID
            if let primaryEcid = getPrimaryEcid() {
                identityMap.remove(item: IdentityItem(id: primaryEcid), withNamespace: IdentityEdgeConstants.Namespaces.ECID)
            }

            // Update ECID if new is not empty
            if let newEcid = newValue, !newEcid.isEmpty {
                identityMap.add(item: IdentityItem(id: newEcid, authenticationState: .ambiguous, primary: true),
                                withNamespace: IdentityEdgeConstants.Namespaces.ECID)
            }
        }
    }

    /// The secondary Experience Cloud ID taken from the Identity direct extension
    var ecidLegacy: String? {
        get {
            return getSecondaryEcid()
        }

        set {
            // Remove previous ECID
            if let secondaryEcid = getSecondaryEcid() {
                identityMap.remove(item: IdentityItem(id: secondaryEcid), withNamespace: IdentityEdgeConstants.Namespaces.ECID)
            }

            // Update ECID if new is not empty
            if let newEcid = newValue, !newEcid.isEmpty {
                identityMap.add(item: IdentityItem(id: newEcid, authenticationState: .ambiguous, primary: false),
                                withNamespace: IdentityEdgeConstants.Namespaces.ECID)
            }
        }
    }

    /// The IDFA from retrieved Apple APIs
    var advertisingIdentifier: String? {
        get {
            return getAdvertisingIdentifier()
        }

        set {
            // remove current Ad ID; there can be only one!
            if let currentAdId = getAdvertisingIdentifier() {
                identityMap.remove(item: IdentityItem(id: currentAdId), withNamespace: IdentityEdgeConstants.Namespaces.IDFA)
            }

            guard let newAdId = newValue, !newAdId.isEmpty else {
                return // new ID is nil or empty
            }

            // Update IDFA
            identityMap.add(item: IdentityItem(id: newAdId), withNamespace: IdentityEdgeConstants.Namespaces.IDFA)
        }
    }

    /// Merge the given `identifiersMap` with the current properties. Items in `identifiersMap` will overrite current properties where the `id` and
    /// `namespace` match. No items are removed. Identifiers under the namespaces "ECID" and "IDFA" are reserved and cannot be updated using this function.
    /// - Parameter identifiersMap: the `IdentityMap` to merge with the current properties
    mutating func updateCustomerIdentifiers(_ identifiersMap: IdentityMap) {
        removeIdentitiesWithReservedNamespaces(from: identifiersMap)
        identityMap.merge(map: identifiersMap)
    }

    /// Remove the given `identifiersMap` from the current properties.
    /// Identifiers under the namespaces "ECID" and "IDFA" are reserved and cannot be removed using this function.
    /// - Parameter identifiersMap: this `IdentityMap` with items to remove from the current properties
    mutating func removeCustomerIdentifiers(_ identifiersMap: IdentityMap) {
        removeIdentitiesWithReservedNamespaces(from: identifiersMap)
        identityMap.remove(map: identifiersMap)
    }

    /// Clear all identifiers
    mutating func clear() {
        identityMap = IdentityMap()
    }

    /// Converts `identityEdgeProperties` into an event data representation in XDM format
    /// - Parameter allowEmpty: If this `identityEdgeProperties` contains no data, return a dictionary with a single `identityMap` key
    /// to represent an empty IdentityMap when `allowEmpty` is true
    /// - Returns: A dictionary representing this `identityEdgeProperties` in XDM format
    func toXdmData(_ allowEmpty: Bool = false) -> [String: Any] {
        var map: [String: Any] = [:]

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

    /// Load the ECID value from the Identity direct extension datastore if available.
    /// - Returns: `ECID` from the Identity direct extension datastore, or nil if the datastore or the ECID are not found
    func getEcidFromDirectIdentityPersistence() -> ECID? {
        let dataStore = NamedCollectionDataStore(name: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT)
        let identityDirectProperties: IdentityDirectProperties? = dataStore.getObject(key: IdentityEdgeConstants.DataStoreKeys.IDENTITY_PROPERTIES)
        return identityDirectProperties?.ecid
    }

    /// Get the primary ECID from the properties map.
    /// - Returns: the primary ECID or nil if a primary ECID was not found
    private func getPrimaryEcid() -> String? {
        guard let ecidList = identityMap.getItems(withNamespace: IdentityEdgeConstants.Namespaces.ECID) else {
            return nil
        }

        for ecidItem in ecidList where ecidItem.primary {
            return ecidItem.id
        }

        return nil
    }

    /// Get the secondary ECID from the properties map. It is assumed there is at most two ECID entries an the secondary ECID is the first non-primary id.
    /// If the primary and secondary ECID ids are the same, then only the primary ECID is set and this function will return nil.
    /// - Returns: the secondary ECID or nil if a secondary ECID was not found
    private func getSecondaryEcid() -> String? {
        guard let ecidList = identityMap.getItems(withNamespace: IdentityEdgeConstants.Namespaces.ECID) else {
            return nil
        }

        for ecidItem in ecidList where !ecidItem.primary {
            return ecidItem.id
        }

        return nil
    }

    /// Get the advertising identifier from the properties map. Assumes only one `IdentityItem` under the "IDFA" namespace.
    /// - Returns: the advertising identifier or nil if not found
    private func getAdvertisingIdentifier() -> String? {
        guard let adIdList = identityMap.getItems(withNamespace: IdentityEdgeConstants.Namespaces.IDFA), !adIdList.isEmpty else {
            return nil
        }

        return adIdList[0].id
    }

    /// Filter out any items contained in reserved namespaces from the given `identityMap`.
    /// The list of reserved namespaces can be found at `reservedNamespaces`.
    /// - Parameter identifiersMap: the `IdentityMap` to filter out items contained in reserved namespaces.
    private func removeIdentitiesWithReservedNamespaces(from identifiersMap: IdentityMap) {
        // Filter out known identifiers to prevent modification of certain namespaces
        let filterItems = IdentityMap()
        for namespace in IdentityEdgeProperties.reservedNamespaces {
            if let items = identifiersMap.getItems(withNamespace: namespace) {
                Log.debug(label: IdentityEdgeProperties.LOG_TAG, "Adding/Updating identifiers in namespace '\(namespace)' is not allowed.")
                for item in items {
                    filterItems.add(item: item, withNamespace: namespace)
                }
            }
        }

        if !filterItems.isEmpty {
            identifiersMap.remove(map: filterItems)
        }
    }
}

/// Helper structure which mimics the Identity Direct properties class. Used to decode the Identity Direct datastore.
private struct IdentityDirectProperties: Codable {
    var ecid: ECID?
}
