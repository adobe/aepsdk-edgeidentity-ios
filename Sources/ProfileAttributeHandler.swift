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

/// Handles a single profile attribute end-to-end: it claims a key on the incoming
/// `genericProfileAttributes` event, owns its dedup and persistence, and reports its
/// contribution to the outgoing collated `profile.updateAttributes` Edge payload and to the
/// profile-attributes XDM shared state.
///
/// Each attribute (timezone today; locale, push identifier, ... in the future) is one conforming
/// type registered in `Identity.profileAttributeHandlers`. The collector in
/// `handleProfileAttributes` iterates every registered handler and stitches their contributions
/// into a single Edge event and into shared state.
protocol ProfileAttributeHandler {

    /// The key on the incoming event data and in persistence that this handler owns (e.g. `"timeZone"`).
    /// The collector uses this as an input filter: `collectFromEvent` is invoked only when this key
    /// is present in the event data. It is also the key this handler emits in its outgoing payload.
    var attributeKey: String { get }

    /// Reads this handler's value from the update event, dedups against persistence, and on change
    /// writes the new value to persistence before returning its contribution to add to the outgoing
    /// collated `profile.updateAttributes` Edge payload. Returns `nil` when nothing should be
    /// contributed (key absent, value invalid, or unchanged).
    ///
    /// Persistence is written before the caller dispatches so that a crash between persist and
    /// dispatch leaves the value in storage; the next update will pick it up via dedup.
    func collectFromEvent(_ event: Event) -> [String: String]?

    /// Returns this handler's persisted contribution as it should appear in the profile-attributes
    /// XDM shared state, or `nil` when nothing is stored.
    func collectFromStorage() -> [String: String]?
}
