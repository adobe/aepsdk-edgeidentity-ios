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
            return IdentityEdgeConstants.AuthenticationStates.AMBIGUOUS
        case .authenticated:
            return IdentityEdgeConstants.AuthenticationStates.AUTHENTICATED
        case .loggedOut:
            return IdentityEdgeConstants.AuthenticationStates.LOGGED_OUT
        }
    }

    public init?(rawValue: RawValue) {
        switch rawValue {
        case IdentityEdgeConstants.AuthenticationStates.AMBIGUOUS:
            self = .ambiguous
        case IdentityEdgeConstants.AuthenticationStates.AUTHENTICATED:
            self = .authenticated
        case IdentityEdgeConstants.AuthenticationStates.LOGGED_OUT:
            self = .loggedOut
        default:
            self = .ambiguous
        }
    }
}

/// Defines a map containing a set of end user identities, keyed on either namespace integration code or the namespace ID of the identity.
/// Within each namespace, the identity is unique. The values of the map are an array, meaning that more than one identity of each namespace may be carried.
@objc(AEPIdentityEdgeMap)
public class IdentityEdgeMap: NSObject, Codable {
    private static let LOG_TAG = "IdentityEdgeMap"
    private var items: [String: [IdentityItem]] = [:]

    /// Determine if this `IdentityEdgeMap` is empty.
    public var isEmpty: Bool {
        return items.isEmpty
    }

    public override init() {}

    /// Adds an `IdentityItem` to this map. If an item is added which shares the same `withNamespace` and `item.id` as an item
    /// already in the map, then the new item replaces the existing item. Empty `withNamepace` or items with an empty `item.id` are not allowed and are ignored.
    /// - Parameters:
    ///   - item: The identity as an `IdentityItem` object
    ///   - namespace: The namespace for this identity
    @objc(addItem:withNamespace:)
    public func add(item: IdentityItem, withNamespace: String) {
        if item.id.isEmpty || withNamespace.isEmpty {
            Log.debug(label: IdentityEdgeMap.LOG_TAG, "Ignoring add:item:withNamespace, empty identifiers and namespaces are not allowed.")
            return
        }

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
    /// - Returns: An array of `IdentityItem` for the given `namespace` or nil if this `IdentityEdgeMap` does not contain the `namespace`.
    @objc(getItemsWithNamespace:)
    public func getItems(withNamespace: String) -> [IdentityItem]? {
        return items[withNamespace]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }

    public required init(from decoder: Decoder) throws {
        super.init()
        let container = try decoder.singleValueContainer()
        if let identityItems = try? container.decode([String: [IdentityItem]].self) {
            for (namespace, items) in identityItems {
                for item in items {
                    self.add(item: item, withNamespace: namespace)
                }
            }
        }
    }

    /// Decodes a [String: Any] dictionary into an `IdentityEdgeMap`
    /// - Parameter eventData: the event data representing `IdentityEdgeMap`
    /// - Returns: an `IdentityEdgeMap` that is represented in the event data, nil if data is not in the correct format
    static func from(eventData: [String: Any]) -> IdentityEdgeMap? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: eventData) else {
            Log.debug(label: LOG_TAG, "Unable to serialize identity event data.")
            return nil
        }

        guard let identityEdgeMap = try? JSONDecoder().decode(IdentityEdgeMap.self, from: jsonData) else {
            Log.debug(label: LOG_TAG, "Unable to decode identity data into an IdentityEdgeMap.")
            return nil
        }

        return identityEdgeMap
    }

}

/// Identity Edge is used to clearly distinguish people that are interacting with digital experiences.
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
