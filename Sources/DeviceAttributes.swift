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

import Foundation

/// Extensible input for `Identity.updateDeviceAttributesBypassConsent(_:)`, the consent-independent device-attribute
/// sync. Mirrors Core's `ProfileAttributes` shape but is intentionally a distinct type: the device path
/// and the profile path evolve independently, so we do not reuse Core's `ProfileAttributes`.
///
/// Adding a future device attribute is source-compatible: append a new defaulted field here (and a
/// matching `AttributeHandler`), leaving existing call sites unchanged.
public struct DeviceAttributes {
    public let timeZone: TimeZone?
    public let pushToken: String?
    public init(timeZone: TimeZone? = nil, pushToken: String? = nil) {
        self.timeZone = timeZone
        self.pushToken = pushToken
    }
}
