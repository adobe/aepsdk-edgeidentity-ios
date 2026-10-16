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

/// Stores confirmed device attributes as a nested map and filters out values that are already synced.
struct DeviceAttributeDeduplicator {
    private static let LOG_TAG = IdentityConstants.FRIENDLY_NAME

    let storeName: String

    /// Splits `attributes` into values to send and values that already match their owner.
    /// A value equal to the stored value is dropped. Owner values (`messagingState`, `timezone`) are compared only
    /// when supplied, which the caller does only when collect consent is "y". When `dedup` is false, every value is sent.
    /// Filtering never writes storage.
    func filter(_ attributes: [String: Any],
                dedup: Bool,
                messagingState: [String: Any]? = nil,
                timezone: String? = nil) -> (toSend: [String: Any], ownerMatches: [String: Any]) {
        let synced = readSynced()
        var toSend: [String: Any] = [:]
        var ownerMatches: [String: Any] = [:]

        for (path, value) in Self.paths(in: attributes) {
            // Detach mutable Foundation inputs so the sent payload and later confirmation use the same values.
            guard let snapshot = Self.snapshot(value) else {
                Log.warning(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - Dropping '\(path)': value is null or not JSON-representable.")
                continue
            }
            if dedup, Self.isEqual(Self.value(at: path, in: synced), snapshot) {
                continue
            }
            if dedup, Self.matchesOwner(path: path, value: snapshot, messagingState: messagingState, timezone: timezone) {
                Self.set(snapshot, at: path, in: &ownerMatches)
                continue
            }
            Self.set(snapshot, at: path, in: &toSend)
        }
        return (toSend, ownerMatches)
    }

    /// Deep-merges `attributes` into the store. A map merges into a map; any other value, or an empty map,
    /// replaces the whole subtree at its key. The SDK-owned root `app` entry is never stored.
    func commit(_ attributes: [String: Any]) {
        var incoming = attributes
        incoming.removeValue(forKey: IdentityConstants.DeviceAttributes.APP)
        writeSynced(Self.merge(incoming, into: readSynced()))
    }

    /// Removes the values at the given paths from the store.
    func remove(paths: [[String]]) {
        var synced = readSynced()
        for path in paths {
            Self.remove(at: path, in: &synced)
        }
        writeSynced(synced)
    }

    /// Returns the confirmed values as a nested map.
    func readSynced() -> [String: Any] {
        guard let json = ServiceProvider.shared.namedKeyValueService
                .get(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES) as? String,
              let data = json.data(using: .utf8),
              let synced = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return synced
    }

    /// Removes all confirmed device attribute values.
    func clear() {
        ServiceProvider.shared.namedKeyValueService
            .remove(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES)
    }

    // Persisted as JSON so any JSON value (including null inside arrays) can be stored safely.
    private func writeSynced(_ values: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            Log.warning(label: Self.LOG_TAG, "DeviceAttributeDeduplicator - Cannot persist confirmed device attributes.")
            return
        }
        ServiceProvider.shared.namedKeyValueService
            .set(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES, value: json)
    }

    /// Returns each leaf value keyed by its path. Non-empty maps are walked; the root `app` entry is skipped.
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

    /// Arrays are compared as sets of elements, so reordering is not a change. Other values compare by canonical JSON.
    static func isEqual(_ stored: Any?, _ value: Any) -> Bool {
        guard let stored = stored else { return false }
        if let storedArray = stored as? [Any], let array = value as? [Any] {
            return elementSet(storedArray) == elementSet(array)
        }
        return canonicalize(stored) == canonicalize(value)
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

    private static func elementSet(_ array: [Any]) -> Set<String> {
        return Set(array.map { canonicalize($0) ?? "null" })
    }

    private static func snapshot(_ value: Any) -> Any? {
        guard let canonical = canonicalize(value), let data = canonical.data(using: .utf8) else { return nil }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [Any])?.first
    }

    private static func matchesOwner(path: [String],
                                     value: Any,
                                     messagingState: [String: Any]?,
                                     timezone: String?) -> Bool {
        typealias Keys = IdentityConstants.DeviceAttributes
        typealias Messaging = IdentityConstants.SharedState.Messaging
        if path == [Keys.TIMEZONE] {
            guard let timezone = timezone, let input = value as? String else { return false }
            return input == timezone
        }
        if path == [Keys.TOKENS, Keys.PUSH_NOTIFICATION] {
            guard let stored = messagingState?[Messaging.PUSH_IDENTIFIER] as? String,
                  let input = value as? String else { return false }
            return input == stored
        }

        let isStart = path == [Keys.TOKENS, Keys.LIVE_ACTIVITY_START]
        guard isStart || path == [Keys.TOKENS, Keys.LIVE_ACTIVITY_UPDATE],
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

    private static func value(at path: [String], in map: [String: Any]) -> Any? {
        var current: Any? = map
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    private static func merge(_ incoming: [String: Any], into stored: [String: Any]) -> [String: Any] {
        var result = stored
        for (key, value) in incoming {
            if let map = value as? [String: Any], !map.isEmpty {
                result[key] = merge(map, into: result[key] as? [String: Any] ?? [:])
            } else {
                result[key] = value
            }
        }
        return result
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

    private static func remove(at path: [String], in data: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            data.removeValue(forKey: key)
        } else if var child = data[key] as? [String: Any] {
            remove(at: Array(path.dropFirst()), in: &child)
            data[key] = child.isEmpty ? nil : child
        }
    }
}
