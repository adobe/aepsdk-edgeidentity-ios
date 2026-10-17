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

/// Keeps the device attributes confirmed by Edge as a nested map and filters out values that do not need to be
/// sent again. A value is compared with the confirmed value at the same path and, when owner values are given
/// (collect consent is "y"), with the owner value at that path. Arrays are compared as sets.
final class DeviceAttributeDeduplicator {
    private static let LOG_SOURCE = "DeviceAttributeDeduplicator"
    private let storeName: String
    private var synced: [String: Any]

    init(storeName: String) {
        self.storeName = storeName
        synced = Self.readPersisted(storeName: storeName)
    }

    /// The result of `filter`: the values to send to Edge, and the values that are not sent because their owner
    /// already holds them.
    struct FilterResult {
        let changed: [String: Any]
        let ownerMatches: [String: Any]
    }

    /// Splits `attributes` into the values that need to be sent to Edge and the values that match an owner value.
    /// Owner matches are not committed here; the caller commits them.
    /// - Parameters:
    ///   - attributes: the attributes to filter
    ///   - dedup: whether to filter out unchanged values; when false, every valid value is returned as changed
    ///   - owners: owner values to compare with, in the same shape as `attributes`; may be nil
    /// - Returns: the changed values (empty when nothing changed) and the owner matches
    func filter(_ attributes: [String: Any], dedup: Bool, owners: [String: Any]?) -> FilterResult {
        var changed: [String: Any] = [:]
        var ownerMatches: [String: Any] = [:]
        Self.collect(attributes,
                     synced: dedup ? synced : nil,
                     owners: dedup ? owners : nil,
                     changed: &changed,
                     ownerMatches: &ownerMatches)
        return FilterResult(changed: changed, ownerMatches: ownerMatches)
    }

    /// Deep-merges `attributes` into the confirmed values and persists them. A map merges into an existing
    /// map; any other value, or an empty map, replaces the existing value at that key.
    /// - Parameter attributes: the attributes confirmed by Edge
    func commit(_ attributes: [String: Any]) {
        synced = Self.merge(synced, attributes)
        persist()
    }

    func readSynced() -> [String: Any] {
        return synced
    }

    func clear() {
        synced = [:]
        ServiceProvider.shared.namedKeyValueService.remove(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES)
    }

    /// Removes the values at the given paths and any parent map left empty. iOS only (Live Activity tokens).
    func remove(paths: [[String]]) {
        for path in paths {
            Self.remove(at: path, in: &synced)
        }
        persist()
    }

    private static func collect(_ attributes: [AnyHashable: Any],
                                synced: [AnyHashable: Any]?,
                                owners: [AnyHashable: Any]?,
                                changed: inout [String: Any],
                                ownerMatches: inout [String: Any]) {
        for (rawKey, value) in attributes {
            guard let key = rawKey as? String else {
                Log.warning(label: IdentityConstants.LOG_TAG, "\(LOG_SOURCE) - Dropping device attribute with a non-string key.")
                continue
            }
            if let map = value as? [AnyHashable: Any], !map.isEmpty {
                var changedChild: [String: Any] = [:]
                var ownerMatchesChild: [String: Any] = [:]
                collect(map,
                        synced: child(synced, key),
                        owners: child(owners, key),
                        changed: &changedChild,
                        ownerMatches: &ownerMatchesChild)
                if !changedChild.isEmpty { changed[key] = changedChild }
                if !ownerMatchesChild.isEmpty { ownerMatches[key] = ownerMatchesChild }
                continue
            }
            guard let canonical = canonicalize(value) else {
                Log.warning(label: IdentityConstants.LOG_TAG, "\(LOG_SOURCE) - Dropping invalid device attribute '\(key)'.")
                continue
            }
            if let synced = synced, canonical == canonicalize(synced[key]) { continue }
            if let owners = owners, canonical == canonicalize(owners[key]) {
                ownerMatches[key] = copy(value)
                continue
            }
            changed[key] = copy(value)
        }
    }

    private static func merge(_ base: [String: Any], _ attributes: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in attributes {
            if let map = value as? [String: Any], !map.isEmpty, let existing = result[key] as? [String: Any] {
                result[key] = merge(existing, map)
            } else {
                result[key] = copy(value)
            }
        }
        return result
    }

    private static func child(_ map: [AnyHashable: Any]?, _ key: String) -> [AnyHashable: Any]? {
        return map?[key] as? [AnyHashable: Any]
    }

    /// Deep copies a valid attribute value so later changes to the caller's collections are not retained.
    private static func copy(_ value: Any) -> Any {
        if let map = value as? [String: Any] {
            return map.mapValues(copy)
        }
        if let array = value as? [Any] {
            return array.map(copy)
        }
        if let string = value as? String {
            return string
        }
        return value
    }

    private static func remove(at path: [String], in map: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            map.removeValue(forKey: key)
        } else if var child = map[key] as? [String: Any] {
            remove(at: Array(path.dropFirst()), in: &child)
            map[key] = child.isEmpty ? nil : child
        }
    }

    /// Returns a stable string form of a value for comparison, or nil when the value is null or invalid.
    static func canonicalize(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        return canonicalValue(value)
    }

    private static func canonicalValue(_ value: Any) -> String? {
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return quote(string)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            if double == 0 { return "0" }
            if CFNumberIsFloatType(number) {
                // Integral values compare equal across integer and floating point types (1 == 1.0).
                return double.rounded() == double && abs(double) < 1e18 ? String(Int64(double)) : String(double)
            }
            return number.stringValue
        }
        if let map = value as? [AnyHashable: Any] {
            var entries: [(String, String)] = []
            for (rawKey, element) in map {
                guard let key = rawKey as? String, let canonicalElement = canonicalValue(element) else { return nil }
                entries.append((key, canonicalElement))
            }
            let sorted = entries.sorted { $0.0 < $1.0 }.map { "\(quote($0.0)):\($0.1)" }
            return "{" + sorted.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            // Arrays are compared as sets, so element order and duplicates do not matter.
            var elements = Set<String>()
            for element in array {
                guard let canonicalElement = canonicalValue(element) else { return nil }
                elements.insert(canonicalElement)
            }
            return "[" + elements.sorted().joined(separator: ",") + "]"
        }
        return nil
    }

    /// Quotes a string as Android's `JSONObject.quote` does, so canonical forms match across platforms.
    private static func quote(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"", "\\", "/": result += "\\" + String(scalar)
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\u{0C}": result += "\\f"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    // Persisted as a JSON string so any JSON value, including null inside arrays, can be stored.
    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: synced),
              let json = String(data: data, encoding: .utf8) else {
            Log.warning(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Cannot persist synced device attributes.")
            return
        }
        ServiceProvider.shared.namedKeyValueService
            .set(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES, value: json)
    }

    private static func readPersisted(storeName: String) -> [String: Any] {
        guard let json = ServiceProvider.shared.namedKeyValueService
                .get(collectionName: storeName, key: IdentityConstants.DeviceAttributes.SYNCED_VALUES) as? String,
              let data = json.data(using: .utf8),
              let persisted = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return persisted
    }
}
