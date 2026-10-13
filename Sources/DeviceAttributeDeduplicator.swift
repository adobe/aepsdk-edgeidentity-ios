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

/// Compares paths with Edge-confirmed values and existing owner values. Filtering never writes storage.
struct DeviceAttributeDeduplicator {
    private static let LOG_TAG = IdentityConstants.FRIENDLY_NAME

    let storeName: String

    /// Returns new or changed JSON-compatible values. Supply owner values only when collect consent is "y".
    func filter(_ attributes: [String: Any],
                dedup: Bool,
                messagingState: [String: Any]? = nil,
                timezone: String? = nil) -> [String: Any] {
        let synced = readSynced()
        var toSend: [String: Any] = [:]

        for (path, value) in Self.paths(in: attributes) {
            guard let canonical = Self.canonicalize(value), let key = Self.canonicalize(path) else {
                Log.warning(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - Dropping '\(path)': value is null or not JSON-representable.")
                continue
            }
            if dedup, synced[key] == canonical {
                continue
            }
            if dedup, Self.matchesOwner(path: path, value: value, messagingState: messagingState, timezone: timezone) {
                continue
            }
            // Detach mutable Foundation inputs so the sent payload and later confirmation use the same values.
            guard let data = canonical.data(using: .utf8),
                  let snapshot = ((try? JSONSerialization.jsonObject(with: data)) as? [Any])?.first else {
                Log.warning(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - Cannot snapshot '\(path)'; dropping value.")
                continue
            }
            Self.set(snapshot, at: path, in: &toSend)
        }
        return toSend
    }

    private static func matchesOwner(path: [String],
                                     value: Any,
                                     messagingState: [String: Any]?,
                                     timezone: String?) -> Bool {
        typealias Messaging = IdentityConstants.SharedState.Messaging
        if path == ["timezone"] {
            guard let timezone = timezone, let input = value as? String else { return false }
            return input == timezone
        }
        if path == ["tokens", "pushNotification"] {
            guard let stored = messagingState?[Messaging.PUSH_IDENTIFIER] as? String,
                  let input = value as? String else { return false }
            return input == stored
        }

        let isStart = path == ["tokens", "liveActivityStart"]
        guard isStart || path == ["tokens", "liveActivityUpdate"],
              let input = value as? [[String: Any]],
              let liveActivity = messagingState?[Messaging.LIVE_ACTIVITY] as? [String: Any],
              let stored = liveActivity[isStart ? Messaging.PUSH_TO_START_TOKENS : Messaging.UPDATE_TOKENS]
                as? [String: [String: Any]] else { return false }
        if input.isEmpty { return stored.isEmpty }
        let idKey = isStart ? "attributeType" : "liveActivityID"
        let tokenKey = isStart ? "value" : "token"
        return input.allSatisfy { entry in
            guard let id = entry[idKey] as? String, let token = entry[tokenKey] as? String else { return false }
            return stored[id]?["token"] as? String == token
        }
    }

    /// Called only for the exact payload of a successful Edge request.
    func commit(_ attributes: [String: Any]) {
        var synced = readSynced()
        for (path, value) in Self.paths(in: attributes) {
            guard let canonical = Self.canonicalize(value), let key = Self.canonicalize(path) else {
                Log.warning(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - Cannot confirm '\(path)': value is null or not JSON-representable.")
                continue
            }
            Self.removeRelatedPaths(to: path, from: &synced)
            synced[key] = canonical
        }
        writeSynced(synced)
    }

    static func paths(in attributes: [String: Any], prefix: [String] = []) -> [[String]: Any] {
        var result: [[String]: Any] = [:]
        for (key, value) in attributes {
            let path = prefix + [key]
            if path.first == IdentityConstants.DeviceAttributes.APP { continue }
            if let nested = value as? [String: Any], !nested.isEmpty {
                result.merge(paths(in: nested, prefix: path)) { _, new in new }
            } else {
                result[path] = value
            }
        }
        return result
    }

    private static func removeRelatedPaths(to path: [String], from synced: inout [String: String]) {
        // A confirmed parent/child replacement invalidates older overlapping values, but not siblings.
        // Decode segments so a literal "a.b" key remains distinct from the nested ["a", "b"] path.
        for key in synced.keys {
            guard let paths = try? JSONDecoder().decode([[String]].self, from: Data(key.utf8)),
                  paths.count == 1, let storedPath = paths.first, !storedPath.isEmpty else {
                Log.warning(label: LOG_TAG, "DeviceAttributeDeduplicator - Removing an invalid confirmed attribute path.")
                synced.removeValue(forKey: key)
                continue
            }
            if storedPath.starts(with: path) || path.starts(with: storedPath) {
                synced.removeValue(forKey: key)
            }
        }
    }

    private static func set(_ value: Any, at path: [String], in data: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            data[key] = value
        } else {
            var child = data[key] as? [String: Any] ?? [:]
            set(value, at: Array(path.dropFirst()), in: &child)
            data[key] = child
        }
    }

    func readSynced() -> [String: String] {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES) as? [String: String] ?? [:]
    }

    /// Removes all confirmed device attribute values.
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
        guard !(value is NSNull) else { return nil }
        let wrapper: [Any] = [value]
        guard JSONSerialization.isValidJSONObject(wrapper),
              let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
