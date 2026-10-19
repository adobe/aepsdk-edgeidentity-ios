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

/// Stores the values Edge confirmed at the deduplicated paths (`DEDUPLICATED_PATHS`: the timezone, push token and
/// push-to-start tokens) as a nested map, and filters out values that do not need to be sent again. A value at a
/// deduplicated path is compared as a whole, even when it is a map, with the confirmed value at the same path and,
/// when `owners` is given, with the value its owner already holds. Arrays are compared as sets. Values at any other
/// path are always sent and never stored.
final class DeviceAttributeDeduplicator {
    private static let LOG_SOURCE = "DeviceAttributeDeduplicator"
    private let storeName: String
    private var synced: [String: Any]

    init(storeName: String) {
        self.storeName = storeName
        let persisted = Self.readPersisted(storeName: storeName)
        synced = Self.deduplicated(persisted)
        if !(synced as NSDictionary).isEqual(to: persisted) {
            persist()
        }
    }

    /// The result of `filter`: the values to send to Edge, and the owner-held values that are not sent.
    struct FilterResult {
        let changed: [String: Any]
        let ownerMatches: [String: Any]
    }

    /// Splits `attributes` into the values that need to be sent to Edge and the deduplicated values their owner
    /// already holds. The owner is where the value is already set: the profile attributes API for the timezone and
    /// Messaging for the push token and push-to-start tokens. Only values at the deduplicated paths can be unchanged
    /// or owner-held; every other valid value is changed. Owner-held values are not stored here; the caller stores them.
    /// - Parameters:
    ///   - attributes: the attributes to filter
    ///   - dedup: whether to filter out unchanged values; when false, every valid value is returned as changed
    ///   - owners: the values their owners hold, in the same shape as `attributes`; may be nil
    /// - Returns: the changed values (empty when nothing changed) and the owner-held values
    func filter(_ attributes: [String: Any], dedup: Bool, owners: [String: Any]?) -> FilterResult {
        return Self.collect(attributes, synced: dedup ? synced : nil, owners: dedup ? owners : nil, path: [], ancestors: [])
    }

    /// Stores each value of `attributes` at a deduplicated path, replacing the whole confirmed value at that path and
    /// keeping the other confirmed values, then persists them. Values at any other path are not stored; when there
    /// are none at a deduplicated path, nothing is written.
    /// - Parameter attributes: the attributes Edge confirmed, or the owner-held values
    func commit(_ attributes: [String: Any]) {
        let values = Self.deduplicatedValues(attributes)
        guard !values.isEmpty else { return }
        for (path, value) in values {
            Self.set(Self.copy(value), at: path, in: &synced)
        }
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
                                path: [String],
                                ancestors: [ObjectIdentifier]) -> FilterResult {
        var changed: [String: Any] = [:]
        var ownerMatches: [String: Any] = [:]
        for (rawKey, value) in attributes {
            guard let key = rawKey as? String else {
                Log.warning(label: IdentityConstants.LOG_TAG, "\(LOG_SOURCE) - Dropping device attribute with a non-string key.")
                continue
            }
            let isDeduplicated = IdentityConstants.DeviceAttributes.DEDUPLICATED_PATHS.contains(path + [key])
            let identity = referenceIdentity(value)
            if !isDeduplicated, let map = value as? [AnyHashable: Any], !map.isEmpty,
               !(identity.map(ancestors.contains) ?? false) {
                let childResult = collect(map,
                                          synced: child(synced, key),
                                          owners: child(owners, key),
                                          path: path + [key],
                                          ancestors: ancestors + [identity].compactMap { $0 })
                if !childResult.changed.isEmpty { changed[key] = childResult.changed }
                if !childResult.ownerMatches.isEmpty { ownerMatches[key] = childResult.ownerMatches }
                continue
            }
            guard let canonical = canonicalize(value, ancestors: ancestors) else {
                Log.warning(label: IdentityConstants.LOG_TAG, "\(LOG_SOURCE) - Dropping invalid device attribute '\(key)'.")
                continue
            }
            if isDeduplicated, let synced = synced, canonical == canonicalize(synced[key]) { continue }
            if isDeduplicated, let owners = owners, canonical == canonicalize(owners[key]) {
                ownerMatches[key] = copy(value)
                continue
            }
            changed[key] = copy(value)
        }
        return FilterResult(changed: changed, ownerMatches: ownerMatches)
    }

    /// Returns the values of `attributes` at the deduplicated paths, keyed by path.
    private static func deduplicatedValues(_ attributes: [String: Any]) -> [([String], Any)] {
        return IdentityConstants.DeviceAttributes.DEDUPLICATED_PATHS.compactMap { path in
            var value: Any? = attributes
            for key in path {
                value = (value as? [String: Any])?[key]
            }
            return value.map { (path, $0) }
        }
    }

    /// Returns only the values of `attributes` at the deduplicated paths, in the same nested shape.
    private static func deduplicated(_ attributes: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (path, value) in deduplicatedValues(attributes) {
            set(value, at: path, in: &result)
        }
        return result
    }

    /// Sets `value` at `path`, creating or replacing the parent maps on the way.
    private static func set(_ value: Any, at path: [String], in map: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            map[key] = value
            return
        }
        var child = map[key] as? [String: Any] ?? [:]
        set(value, at: Array(path.dropFirst()), in: &child)
        map[key] = child
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

    /// Returns a stable string form of a value directly inside the attributes map for comparison, or nil when the
    /// value is null or invalid.
    static func canonicalize(_ value: Any?) -> String? {
        return canonicalize(value, ancestors: [])
    }

    private static func canonicalize(_ value: Any?, ancestors: [ObjectIdentifier]) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        return canonicalValue(value, ancestors: ancestors)
    }

    /// iOS only: returns the identity of a reference type value, such as an `NSMutableDictionary`, so a collection
    /// that contains itself can be detected. Returns nil for Swift value types, which cannot contain themselves.
    private static func referenceIdentity(_ value: Any) -> ObjectIdentifier? {
        guard type(of: value) is AnyClass else { return nil }
        return ObjectIdentifier(value as AnyObject)
    }

    /// `ancestors` holds the reference type collections that contain `value`, so a collection that contains
    /// itself is invalid instead of recursing forever.
    private static func canonicalValue(_ value: Any, ancestors: [ObjectIdentifier]) -> String? {
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
        var ancestors = ancestors
        if let identity = referenceIdentity(value) {
            guard !ancestors.contains(identity) else { return nil }
            ancestors.append(identity)
        }
        if let map = value as? [AnyHashable: Any] {
            var entries: [(String, String)] = []
            for (rawKey, element) in map {
                guard let key = rawKey as? String, let canonicalElement = canonicalValue(element, ancestors: ancestors) else { return nil }
                entries.append((key, canonicalElement))
            }
            let sorted = entries.sorted { $0.0 < $1.0 }.map { "\(quote($0.0)):\($0.1)" }
            return "{" + sorted.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            // Arrays are compared as sets, so element order and duplicates do not matter.
            var elements = Set<String>()
            for element in array {
                guard let canonicalElement = canonicalValue(element, ancestors: ancestors) else { return nil }
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
        // JSONSerialization raises an Objective-C exception, which `try?` cannot catch, for an invalid object.
        guard JSONSerialization.isValidJSONObject(synced),
              let data = try? JSONSerialization.data(withJSONObject: synced),
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
