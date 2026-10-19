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

/// Stores the confirmed values of the deduplicated device attributes, the timezone (`timezone`), push token
/// (`tokens.pushNotification`) and Live Activity push-to-start tokens (`tokens.liveActivityStart`), and filters out
/// those that do not need to be sent again. Push-to-start tokens are compared ignoring order. Values at any other path,
/// and deduplicated values of an unexpected type, are always sent and never stored.
final class DeviceAttributeDeduplicator {
    private typealias Keys = IdentityConstants.DeviceAttributes
    private let storeName: String

    init(storeName: String) {
        self.storeName = storeName
    }

    /// The result of `filter`: the values to send to Edge, and the owner-held values that are not sent.
    struct FilterResult {
        let changed: [String: Any]
        let ownerMatches: [String: Any]
    }

    /// Removes the deduplicated values that match the confirmed value or, when `owners` is given, the value their owner
    /// already holds. The owner is where the value is already set: the profile attributes API for the timezone and
    /// Messaging for the push token and push-to-start tokens. Owner-held values are returned separately and are not
    /// stored here; the caller stores them as confirmed.
    /// - Parameters:
    ///   - attributes: the attributes to filter
    ///   - owners: the values their owners hold, in the same shape as `attributes`; may be nil
    /// - Returns: the values to send (empty when nothing changed) and the owner-held values
    func filter(_ attributes: [String: Any], owners: [String: Any]?) -> FilterResult {
        var changed = attributes
        var ownerMatches: [String: Any] = [:]
        let timezone = Self.match(attributes[Keys.TIMEZONE] as? String,
                                  synced: read(Keys.TIMEZONE) as? String,
                                  owner: owners?[Keys.TIMEZONE] as? String)
        Self.apply(timezone, key: Keys.TIMEZONE, from: attributes, to: &changed, ownerMatches: &ownerMatches)

        guard let tokens = attributes[Keys.TOKENS] as? [String: Any] else {
            return FilterResult(changed: changed, ownerMatches: ownerMatches)
        }
        let ownerTokens = owners?[Keys.TOKENS] as? [String: Any]
        var changedTokens = tokens
        var matchedTokens: [String: Any] = [:]
        let pushToken = Self.match(tokens[Keys.PUSH_NOTIFICATION] as? String,
                                   synced: read(Keys.PUSH_NOTIFICATION) as? String,
                                   owner: ownerTokens?[Keys.PUSH_NOTIFICATION] as? String)
        Self.apply(pushToken, key: Keys.PUSH_NOTIFICATION, from: tokens, to: &changedTokens, ownerMatches: &matchedTokens)
        let startTokens = Self.match(Self.startTokens(tokens[Keys.LIVE_ACTIVITY_START]),
                                     synced: Self.startTokens(read(Keys.LIVE_ACTIVITY_START)),
                                     owner: Self.startTokens(ownerTokens?[Keys.LIVE_ACTIVITY_START]))
        Self.apply(startTokens, key: Keys.LIVE_ACTIVITY_START, from: tokens, to: &changedTokens, ownerMatches: &matchedTokens)

        if changedTokens.count != tokens.count {
            changed[Keys.TOKENS] = changedTokens.isEmpty ? nil : changedTokens
        }
        if !matchedTokens.isEmpty {
            ownerMatches[Keys.TOKENS] = matchedTokens
        }
        return FilterResult(changed: changed, ownerMatches: ownerMatches)
    }

    /// Stores the deduplicated values in `attributes`, replacing the confirmed value of each. Other values are ignored.
    /// - Parameter attributes: the attributes Edge confirmed, or the owner-held values
    func commit(_ attributes: [String: Any]) {
        if let timezone = attributes[Keys.TIMEZONE] as? String {
            write(Keys.TIMEZONE, timezone)
        }
        let tokens = attributes[Keys.TOKENS] as? [String: Any]
        if let pushToken = tokens?[Keys.PUSH_NOTIFICATION] as? String {
            write(Keys.PUSH_NOTIFICATION, pushToken)
        }
        if let startTokens = Self.startTokens(tokens?[Keys.LIVE_ACTIVITY_START]) {
            let sorted = startTokens.sorted {
                ($0[Keys.ATTRIBUTE_TYPE] ?? "", $0[Keys.VALUE] ?? "") < ($1[Keys.ATTRIBUTE_TYPE] ?? "", $1[Keys.VALUE] ?? "")
            }
            write(Keys.LIVE_ACTIVITY_START, sorted)
        }
    }

    /// Returns the confirmed values in the same nested shape as the device attributes.
    func readSynced() -> [String: Any] {
        var synced: [String: Any] = [:]
        if let timezone = read(Keys.TIMEZONE) as? String {
            synced[Keys.TIMEZONE] = timezone
        }
        var tokens: [String: Any] = [:]
        if let pushToken = read(Keys.PUSH_NOTIFICATION) as? String {
            tokens[Keys.PUSH_NOTIFICATION] = pushToken
        }
        if let startTokens = read(Keys.LIVE_ACTIVITY_START) as? [[String: String]] {
            tokens[Keys.LIVE_ACTIVITY_START] = startTokens
        }
        if !tokens.isEmpty {
            synced[Keys.TOKENS] = tokens
        }
        return synced
    }

    /// Removes all confirmed values.
    func clear() {
        [Keys.TIMEZONE, Keys.PUSH_NOTIFICATION, Keys.LIVE_ACTIVITY_START].forEach(remove)
    }

    /// Removes the confirmed Live Activity push-to-start tokens.
    func clearLiveActivityStart() {
        remove(Keys.LIVE_ACTIVITY_START)
    }

    private enum Match {
        case changed, synced, owner
    }

    private static func match<T: Equatable>(_ value: T?, synced: T?, owner: T?) -> Match {
        guard let value = value else { return .changed }
        if value == synced { return .synced }
        if value == owner { return .owner }
        return .changed
    }

    /// Removes `key` from `changed` when its value is unchanged, and records the original value when it is owner-held.
    private static func apply(_ match: Match,
                              key: String,
                              from source: [String: Any],
                              to changed: inout [String: Any],
                              ownerMatches: inout [String: Any]) {
        guard match != .changed else { return }
        changed[key] = nil
        if match == .owner {
            ownerMatches[key] = source[key]
        }
    }

    /// Returns the push-to-start tokens `[{attributeType, value}]` as a set, or nil when `value` is not a list of them.
    private static func startTokens(_ value: Any?) -> Set<[String: String]>? {
        guard let entries = value as? [[String: Any]] else { return nil }
        var result = Set<[String: String]>()
        for entry in entries {
            guard let type = entry[Keys.ATTRIBUTE_TYPE] as? String, let token = entry[Keys.VALUE] as? String else { return nil }
            result.insert([Keys.ATTRIBUTE_TYPE: type, Keys.VALUE: token])
        }
        return result
    }

    private func read(_ key: String) -> Any? {
        return ServiceProvider.shared.namedKeyValueService.get(collectionName: storeName, key: key)
    }

    private func write(_ key: String, _ value: Any) {
        ServiceProvider.shared.namedKeyValueService.set(collectionName: storeName, key: key, value: value)
    }

    private func remove(_ key: String) {
        ServiceProvider.shared.namedKeyValueService.remove(collectionName: storeName, key: key)
    }
}
