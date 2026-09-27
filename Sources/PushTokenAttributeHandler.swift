// Copyright 2026 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.

import AEPCore
import AEPServices
import Foundation

/// `AttributeHandler` for the device push token. Reads the token from the incoming event under
/// `"pushidentifier"`, optionally dedups against the injected `storeName`, persists on change, and
/// contributes to the outgoing operational-data payload under the `"pushidentifier"` key (mapped to the
/// `"pushNotification"` Launch rule token via `operationalDataKey`).
struct PushTokenAttributeHandler: AttributeHandler {

    private static let LOG_TAG = IdentityConstants.FRIENDLY_NAME

    // Canonical key for event data, persistence, and the operational-data payload / rule token.
    static let key = IdentityConstants.DeviceAttributes.PUSH_IDENTIFIER

    var attributeKey: String { PushTokenAttributeHandler.key }

    // Input/storage key is "pushidentifier"; the Launch rule token is "pushNotification".
    var operationalDataKey: String { IdentityConstants.DeviceAttributes.PUSH_NOTIFICATION }

    // Injected dedup namespace (the device-attributes store).
    let storeName: String

    init(storeName: String) {
        self.storeName = storeName
    }

    func collectFromEvent(_ event: Event, dedup: Bool) -> [String: String]? {
        guard let token = event.data?[attributeKey] as? String, !token.isEmpty else {
            Log.debug(label: Self.LOG_TAG, "PushTokenAttributeHandler - Push token missing or empty in event data, ignoring.")
            return nil
        }
        if dedup, readStored() == token {
            Log.debug(label: Self.LOG_TAG, "PushTokenAttributeHandler - Push token unchanged, skipping.")
            return nil
        }
        writeStored(token)
        return [attributeKey: token]
    }

    func collectFromStorage() -> [String: String]? {
        guard let stored = readStored() else { return nil }
        return [attributeKey: stored]
    }

    private func readStored() -> String? {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: storeName, key: attributeKey) as? String
    }

    private func writeStored(_ value: String) {
        ServiceProvider.shared.namedKeyValueService
            .set(collectionName: storeName, key: attributeKey, value: value)
    }
}
