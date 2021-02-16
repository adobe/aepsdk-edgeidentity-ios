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

import AEPServices
import Foundation

/// The state this identity is authenticated.
/// - ambiguous - Ambiguous.
/// - authenticated - User identified by a login or similar action that was valid at the time of the event observation.
/// - loggedOut - User was identified by a login action at some point of time previously, but is not currently logged in.
@objc(AEPAuthenticationState)
public enum AuthenticationState: Int, RawRepresentable, Codable {
    case ambiguous = 0
    case authenticated = 1
    case loggedOut = 2

    public typealias RawValue = String

    public var rawValue: RawValue {
        switch self {
        case .ambiguous:
            return IdentityConstants.AuthenticationStates.AMBIGUOUS
        case .authenticated:
            return IdentityConstants.AuthenticationStates.AUTHENTICATED
        case .loggedOut:
            return IdentityConstants.AuthenticationStates.LOGGED_OUT
        }
    }

    public init?(rawValue: RawValue) {
        switch rawValue {
        case IdentityConstants.AuthenticationStates.AMBIGUOUS:
            self = .ambiguous
        case IdentityConstants.AuthenticationStates.AUTHENTICATED:
            self = .authenticated
        case IdentityConstants.AuthenticationStates.LOGGED_OUT:
            self = .loggedOut
        default:
            self = .ambiguous
        }
    }
}

/// Defines a map containing a set of end user identities, keyed on either namespace integration code or the namespace ID of the identity.
/// Within each namespace, the identity is unique. The values of the map are an array, meaning that more than one identity of each namespace may be carried.
@objc(AEPIdentityMap)
public class IdentityMap: NSObject, Codable {
    private static let LOG_TAG = "IdentityMap"
    private var items: [String: [IdentityItem]] = [:]

    public override init() {}

    /// Adds an `IdentityItem` to this map. If an item is added which shares the same `namespace` and `id` as an item
    /// already in the map, then the new item replaces the existing item.
    /// - Parameters:
    ///   - item: The identity as an `IdentityItem` object
    ///   - namespace: The namespace for this identity
    @objc(addItem:withNamespace:)
    public func add(item: IdentityItem, withNamespace: String) {
        if var namespaceItems = items[withNamespace] {
            if let index = namespaceItems.firstIndex(of: item) {
                namespaceItems[index] = item
            } else {
                namespaceItems.append(item)
            }
            items[withNamespace] = namespaceItems
        } else {
            items[withNamespace] = [item]
        }
    }

    /// Get the array of `IdentityItem`(s) for the given namespace.
    /// - Parameter namespace: the namespace of items to retrieve
    /// - Returns: An array of `IdentityItem` for the given `namespace` or nil if this `IdentityMap` does not contain the `namespace`.
    @objc(getItemsWithNamespace:)
    public func getItems(withNamespace: String) -> [IdentityItem]? {
        return items[withNamespace]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let identityItems = try? container.decode([String: [IdentityItem]].self) {
            items = identityItems
        }
    }

    /// Decodes a [String: Any] dictionary into an `IdentityMap`
    /// - Parameter eventData: the event data representing `IdentityMap`
    /// - Returns: an `IdentityMap` that is represented in the event data, nil if data is not in the correct format
    static func from(eventData: [String: Any]) -> IdentityMap? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: eventData) else {
            Log.debug(label: LOG_TAG, "Unable to serialize identity event data.")
            return nil
        }

        guard let identityMap = try? JSONDecoder().decode(IdentityMap.self, from: jsonData) else {
            Log.debug(label: LOG_TAG, "Unable to decode identity data into an IdentityMap.")
            return nil
        }

        return identityMap
    }

}

/// Identity is used to clearly distinguish people that are interacting with digital experiences.
@objc(AEPIdentityItem)
@objcMembers
public class IdentityItem: NSObject, Codable {
    public let id: String
    public let authenticationState: AuthenticationState
    public let primary: Bool

    /// Creates a new `IdentityItem`.
    /// - Parameters:
    ///   - id: Identity of the consumer in the related namespace.
    ///   - authenticationState: The state this identity is authenticated as. Default is 'ambiguous'.
    ///   - primary: Indicates this identity is the preferred identity. Is used as a hint to help systems better organize how identities are queried. Default is false.
    public init(id: String, authenticationState: AuthenticationState = .ambiguous, primary: Bool = false) {
        self.id = id
        self.authenticationState = authenticationState
        self.primary = primary
    }

    /// Defines two `IdentityItem` objects are equal if they have the same `id`.
    public override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? IdentityItem else { return false }
        return self.id == object.id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authenticationState
        case primary
    }

    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try values.decode(String.self, forKey: .id)

        if let state = try? values.decode(AuthenticationState.self, forKey: .authenticationState) {
            self.authenticationState = state
        } else {
            self.authenticationState = .ambiguous
        }

        if let primaryId = try? values.decode(Bool.self, forKey: .primary) {
            self.primary = primaryId
        } else {
            self.primary = false
        }
    }
}
