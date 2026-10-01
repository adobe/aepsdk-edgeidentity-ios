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
import Foundation

/// Handles a single attribute end-to-end: it claims a key on the incoming event, owns its dedup and
/// persistence against an injected store, and reports its contribution to the outgoing collated payload
/// (profile XDM payload for the consent-gated profile path, or operational-data payload for the
/// consent-independent device path).
///
/// Each attribute (timezone, push identifier, ...) is one conforming type registered in
/// `Identity.profileAttributeHandlers` and/or `Identity.deviceAttributeHandlers`. The same conforming
/// type can be registered on both paths with a different `storeName` so the two paths never
/// cross-suppress each other's values.
protocol AttributeHandler {

    /// The key this handler owns on the incoming event data, in persistence (dedup), and in the profile
    /// XDM output. Three roles for one string: (1) input filter — `collectFromEvent` runs only when this
    /// key is present in the event data; (2) storage key under `storeName`; (3) the key emitted in the
    /// profile-path output payload. (e.g. `"timeZone"`).
    var attributeKey: String { get }

    /// The persistence (dedup) namespace this handler reads/writes, injected at registration.
    var storeName: String { get }

    /// Reads this handler's value from the update event and returns its contribution to add to the
    /// outgoing collated payload, or `nil` when nothing should be contributed (key absent, value
    /// invalid, or — when `dedup` is true — unchanged from the persisted value).
    ///
    /// When `dedup` is true, an unchanged value is skipped (returns `nil`). When `dedup` is false, the
    /// value is always returned. In both cases a returned value is written to persistence before the
    /// caller dispatches, so a crash between persist and dispatch leaves the value in storage.
    func collectFromEvent(_ event: Event, dedup: Bool) -> [String: String]?

    /// Returns this handler's persisted contribution as it should appear in shared state, or `nil` when
    /// nothing is stored.
    func collectFromStorage() -> [String: String]?
}
