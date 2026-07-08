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

/// `ProfileAttributeHandler` for the device timezone. Reads the IANA identifier from the
/// incoming event under `"timeZone"`, persists it, and contributes to the outgoing payload
/// under the same `"timeZone"` key.
struct TimeZoneAttributeHandler: ProfileAttributeHandler {

    // NOTE: IANA timezone validation (TimeZone(identifier:)) is present here but absent in the
    // Android implementation. Android should add equivalent validation to reject non-IANA strings.

    private static let LOG_TAG = IdentityConstants.FRIENDLY_NAME

    // Canonical key for event data, persistence, and the Edge payload. Mirrors Android's
    // TimeZoneAttributeHandler.getAttributeKey() — both platforms use "timeZone".
    static let key = "timeZone"

    var attributeKey: String { TimeZoneAttributeHandler.key }

    func collectFromEvent(_ event: Event) -> [String: String]? {
        guard let timezone = event.data?[attributeKey] as? String, !timezone.isEmpty else {
            Log.debug(label: Self.LOG_TAG, "TimeZoneAttributeHandler - Timezone missing or empty in event data, ignoring.")
            return nil
        }
        guard TimeZone(identifier: timezone) != nil else {
            Log.warning(label: Self.LOG_TAG, "TimeZoneAttributeHandler - '\(timezone)' is not a valid IANA timezone identifier, ignoring.")
            return nil
        }
        guard readStored() != timezone else {
            Log.debug(label: Self.LOG_TAG, "TimeZoneAttributeHandler - Timezone unchanged, skipping.")
            return nil
        }
        writeStored(timezone)
        return [attributeKey: timezone]
    }

    func collectFromStorage() -> [String: String]? {
        guard let stored = readStored() else { return nil }
        return [attributeKey: stored]
    }

    private func readStored() -> String? {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: attributeKey) as? String
    }

    private func writeStored(_ value: String) {
        ServiceProvider.shared.namedKeyValueService
            .set(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: attributeKey, value: value)
    }
}
