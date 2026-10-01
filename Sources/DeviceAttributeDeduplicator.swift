//
// Copyright 2026 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

import AEPServices
import Foundation

/// Key-based dedup for the consent-independent device-attribute sync.
///
/// Remembers the last synced value of every key as a canonical JSON string, persisted as a single
/// `[key: canonicalValue]` map in `storeName`. A key is sent again only when its value changes. This store
/// MUST differ from the profile-attributes store (see `IdentityConstants.Store`).
struct DeviceAttributeDeduplicator {
    private static let LOG_TAG = IdentityConstants.FRIENDLY_NAME

    let storeName: String

    /// Returns the entries of `attributes` to send, unmodified: every entry when `dedup` is false, otherwise
    /// only keys that are new or whose value changed since the last sync. Returned entries are recorded as
    /// synced before the caller dispatches. Entries whose value is not JSON-representable are dropped.
    func filter(_ attributes: [String: Any], dedup: Bool) -> [String: Any] {
        var synced = readSynced()
        var toSend: [String: Any] = [:]

        for (key, value) in attributes {
            guard let canonical = Self.canonicalize(value) else {
                Log.warning(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - Dropping '\(key)': value is not JSON-representable.")
                continue
            }
            if dedup, synced[key] == canonical {
                Log.debug(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - '\(key)' unchanged since last sync, skipping.")
                continue
            }
            synced[key] = canonical
            toSend[key] = value
        }

        if !toSend.isEmpty {
            writeSynced(synced)
        }
        return toSend
    }

    func readSynced() -> [String: String] {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES) as? [String: String] ?? [:]
    }

    /// Forgets every synced value, so the next update sends each key again.
    func clear() {
        ServiceProvider.shared.namedKeyValueService
            .remove(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES)
    }

    private func writeSynced(_ values: [String: String]) {
        ServiceProvider.shared.namedKeyValueService
            .set(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES, value: values)
    }

    /// Stable string form of a value for comparison. Dictionary keys are sorted so key order never counts
    /// as a change; booleans stay distinct from numbers (`true` vs `1`).
    static func canonicalize(_ value: Any) -> String? {
        let wrapper: [Any] = [value]
        guard JSONSerialization.isValidJSONObject(wrapper),
              let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
