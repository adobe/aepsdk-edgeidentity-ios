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

/// Sends device attributes from `updateDeviceAttributesBypassConsent` to Edge without checking collect consent.
/// The public API data is forwarded to the rules engine; a forward operational data rule responds with the
/// attributes that may be sent. Rule responses are queued and sent to Edge one at a time, and each Edge result
/// releases the active request.
final class DeviceAttributeSync {
    private static let LOG_SOURCE = "DeviceAttributeSync"

    private let runtime: ExtensionRuntime
    private let deduplicator = DeviceAttributeDeduplicator(storeName: IdentityConstants.DataStoreKeys.DEVICE_ATTRIBUTES_DATASTORE_NAME)
    private var pendingRequests: [Event] = []
    private var activeRequest: Event?

    init(runtime: ExtensionRuntime) {
        self.runtime = runtime
    }

    /// Forwards public API data to the rules engine, which decides which attributes may be sent.
    func handleDeviceAttributes(event: Event) {
        guard let data = event.data, !data.isEmpty else {
            Log.warning(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Ignoring empty device attribute request.")
            return
        }
        Log.debug(label: IdentityConstants.LOG_TAG,
                  "\(Self.LOG_SOURCE) - Forwarding device attributes to the rules engine. " +
                    "Nothing is sent to Edge unless a forward operational data rule matches.")
        runtime.dispatch(event: event.createChainedEvent(name: IdentityConstants.EventNames.DEVICE_ATTRIBUTES_TO_RULES_ENGINE,
                                                         type: IdentityConstants.DeviceAttributes.OPERATIONAL_DATA_TYPE,
                                                         source: EventSource.requestContent,
                                                         data: data))
    }

    /// Queues a rule consequence until the active Edge request has completed.
    func handleDeviceAttributeRuleResponse(event: Event) {
        guard let data = event.data, !data.isEmpty else {
            Log.debug(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Rule response contains no device attributes.")
            return
        }
        pendingRequests.append(event)
        processQueue()
    }

    /// Sends queued requests until one is waiting for an Edge response or the queue is empty.
    private func processQueue() {
        while activeRequest == nil, !pendingRequests.isEmpty {
            guard let request = buildEdgeRequest(pendingRequests.removeFirst()) else { continue }
            activeRequest = request
            Log.debug(label: IdentityConstants.LOG_TAG,
                      "\(Self.LOG_SOURCE) - Sending device attributes to Edge (request '\(request.id.uuidString)').")
            runtime.dispatch(event: request)
        }
    }

    /// Returns the Edge request for the changed values in `ruleResponse`, or nil if there is nothing to send.
    private func buildEdgeRequest(_ ruleResponse: Event) -> Event? {
        typealias Keys = IdentityConstants.DeviceAttributes
        var attributes = ruleResponse.data ?? [:]
        attributes.removeValue(forKey: Keys.APP)
        let config = configuration()
        let dedup = config[Keys.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC] as? Bool ?? true
        let owners = dedup && isCollectConsentYes() ? ownerValues(attributes) : nil
        let result = deduplicator.filter(attributes, dedup: dedup, owners: owners)
        if !result.ownerMatches.isEmpty {
            deduplicator.commit(result.ownerMatches)
            Log.debug(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Marked device attributes held by their owner as synced.")
            publishProfileAttributes(event: ruleResponse)
        }
        var changed = result.changed
        guard !changed.isEmpty else {
            // TODO: Publish a result event when all values are deduplicated.
            Log.debug(label: IdentityConstants.LOG_TAG,
                      "\(Self.LOG_SOURCE) - Device attributes unchanged, not sending to Edge (rule event '\(ruleResponse.id.uuidString)').")
            return nil
        }

        guard let appId = Bundle.main.bundleIdentifier, !appId.isEmpty else {
            Log.warning(label: IdentityConstants.LOG_TAG,
                        "\(Self.LOG_SOURCE) - Cannot send device attributes without an app identifier. " +
                            "Dropping rule event '\(ruleResponse.id.uuidString)'.")
            return nil
        }
        let useSandbox = config[Keys.MESSAGING_USE_SANDBOX] as? Bool ?? false
        changed[Keys.APP] = [
            Keys.APP_ID: appId,
            Keys.APP_PLATFORM: useSandbox ? Keys.PLATFORM_APNS_SANDBOX : Keys.PLATFORM_APNS
        ]
        return ruleResponse.createChainedEvent(name: IdentityConstants.EventNames.DEVICE_ATTRIBUTES_EDGE_REQUEST,
                                               type: Keys.BYPASS_TYPE,
                                               source: EventSource.requestContent,
                                               data: changed)
    }

    /// Handles the Edge response for the active request, then sends the next queued request.
    func handleDeviceAttributeResult(event: Event) {
        typealias Keys = IdentityConstants.DeviceAttributes
        guard let request = activeRequest, isResponseToActiveRequest(event) else {
            Log.debug(label: IdentityConstants.LOG_TAG,
                      "\(Self.LOG_SOURCE) - Ignoring device attribute response '\(event.id.uuidString)', it does not match the active request.")
            return
        }
        let requestId = request.id.uuidString
        var attributes = request.data ?? [:]
        attributes.removeValue(forKey: Keys.APP)
        activeRequest = nil

        let status = event.data?[Keys.STATUS] as? String
        var result: [String: Any] = [:]
        if status == Keys.STATUS_SUCCESS {
            deduplicator.commit(attributes)
            if let timezone = attributes[Keys.TIMEZONE] as? String {
                ServiceProvider.shared.namedKeyValueService
                    .set(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: Keys.TIME_ZONE, value: timezone)
            }
            publishProfileAttributes(event: event)
            Log.debug(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Device attributes synced (request '\(requestId)').")
            result[Keys.STATUS] = Keys.STATUS_SUCCESS
            result[Keys.REASON] = ""
        } else {
            let reason = event.data?[Keys.REASON] as? String ?? Keys.UNKNOWN_REASON
            Log.warning(label: IdentityConstants.LOG_TAG,
                        "\(Self.LOG_SOURCE) - Device attribute sync failed (request '\(requestId)') with status '\(status ?? "missing")' " +
                            "and reason '\(reason)'. Values remain unsynced.")
            result[Keys.STATUS] = Keys.STATUS_FAILED
            result[Keys.REASON] = reason
        }
        result[Keys.ATTRIBUTES] = attributes
        runtime.dispatch(event: event.createChainedEvent(name: IdentityConstants.EventNames.DEVICE_ATTRIBUTES_SYNC_RESULT,
                                                         type: EventType.edgeIdentity,
                                                         source: EventSource.responseContent,
                                                         data: result))
        processQueue()
    }

    /// A response matches when it is chained to the active request or names it in `requestEventId`.
    private func isResponseToActiveRequest(_ event: Event) -> Bool {
        guard let request = activeRequest else { return false }
        return event.parentID == request.id ||
            event.data?[IdentityConstants.DeviceAttributes.REQUEST_EVENT_ID] as? String == request.id.uuidString
    }

    /// Returns the values owned by other sources, in the same shape as the device attributes: the timezone set
    /// through the profile attributes API and the push token in the Messaging shared state.
    /// iOS only: a Live Activity token list is an owner value when Messaging holds every token in it, so
    /// `attributes` is needed to build those values.
    private func ownerValues(_ attributes: [String: Any]) -> [String: Any] {
        typealias Keys = IdentityConstants.DeviceAttributes
        typealias Messaging = IdentityConstants.SharedState.Messaging
        var owners: [String: Any] = [:]
        if let timezone = profileTimezone() {
            owners[Keys.TIMEZONE] = timezone
        }

        guard let messaging = runtime.getSharedState(extensionName: Messaging.SHARED_OWNER_NAME,
                                                     event: nil,
                                                     barrier: false,
                                                     resolution: .lastSet),
              messaging.status == .set, let messagingState = messaging.value else {
            return owners
        }
        var tokens: [String: Any] = [:]
        if let pushToken = messagingState[Messaging.PUSH_IDENTIFIER] as? String {
            tokens[Keys.PUSH_NOTIFICATION] = pushToken
        }
        let liveActivity = messagingState[Messaging.LIVE_ACTIVITY] as? [String: Any]
        let input = attributes[Keys.TOKENS] as? [String: Any]
        for (key, storedKey, idKey, tokenKey) in [(Keys.LIVE_ACTIVITY_START, Messaging.PUSH_TO_START_TOKENS, "attributeType", "value"),
                                                  (Keys.LIVE_ACTIVITY_UPDATE, Messaging.UPDATE_TOKENS, "liveActivityID", "token")] {
            guard let entries = input?[key] as? [[String: Any]],
                  let stored = liveActivity?[storedKey] as? [String: [String: Any]] else { continue }
            let held = entries.isEmpty ? stored.isEmpty : entries.allSatisfy { entry in
                guard let id = entry[idKey] as? String, let token = entry[tokenKey] as? String else { return false }
                return stored[id]?["token"] as? String == token
            }
            if held {
                tokens[key] = entries
            }
        }
        if !tokens.isEmpty {
            owners[Keys.TOKENS] = tokens
        }
        return owners
    }

    /// Returns true when collect consent is "y". When the Consent extension is not registered, consent is treated
    /// as "y", matching the Edge extension.
    private func isCollectConsentYes() -> Bool {
        typealias Consent = IdentityConstants.XDMKeys.Consent
        guard let hub = runtime.getSharedState(extensionName: IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME,
                                               event: nil,
                                               barrier: false,
                                               resolution: .lastSet),
              hub.status == .set else {
            return false
        }
        let extensions = hub.value?[IdentityConstants.SharedState.Hub.EXTENSIONS] as? [String: Any]
        let consentExtension = extensions?[IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME] as? [String: Any]
        guard let consentExtension = consentExtension, !consentExtension.isEmpty else { return true }

        guard let consentResult = runtime.getXDMSharedState(extensionName: IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME,
                                                            event: nil,
                                                            barrier: false,
                                                            resolution: .any),
              consentResult.status == .set else {
            return false
        }
        let consents = consentResult.value?[Consent.CONSENTS] as? [String: Any]
        let collect = consents?[Consent.COLLECT] as? [String: Any]
        return collect?[Consent.VAL] as? String == Consent.YES
    }

    /// Clears queued requests and all synced values, then republishes the profile attributes. The profile
    /// attribute store itself is cleared by `Identity.handleRequestReset`.
    func reset(event: Event) {
        // TODO: Publish a result event for requests dropped by a reset.
        pendingRequests.removeAll()
        activeRequest = nil
        deduplicator.clear()
        publishProfileAttributes(event: event)
        Log.debug(label: IdentityConstants.LOG_TAG,
                  "\(Self.LOG_SOURCE) - Cleared device attribute requests and synced values after identity reset.")
    }

    /// iOS only: removes the Live Activity tokens when Messaging clears its Live Activities.
    func handleClearLiveActivities(event: Event) {
        typealias Keys = IdentityConstants.DeviceAttributes
        guard event.data?[Keys.CLEAR_LIVE_ACTIVITIES] as? Bool == true else { return }
        deduplicator.remove(paths: [[Keys.TOKENS, Keys.LIVE_ACTIVITY_START], [Keys.TOKENS, Keys.LIVE_ACTIVITY_UPDATE]])
        publishProfileAttributes(event: event)
        Log.debug(label: IdentityConstants.LOG_TAG,
                  "\(Self.LOG_SOURCE) - Cleared Live Activity tokens after Messaging cleared Live Activities.")
    }

    /// Publishes the synced device attributes merged with the consent-path timezone in the standard shared state.
    func publishProfileAttributes(event: Event?) {
        var attributes = deduplicator.readSynced()
        if let timezone = profileTimezone() {
            attributes[IdentityConstants.DeviceAttributes.TIMEZONE] = timezone
        }
        runtime.createSharedState(data: [IdentityConstants.ProfileAttributes.SHARED_STATE_KEY: attributes], event: event)
    }

    private func profileTimezone() -> String? {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME,
                 key: IdentityConstants.DeviceAttributes.TIME_ZONE) as? String
    }

    private func configuration() -> [String: Any] {
        return runtime.getSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                      event: nil,
                                      barrier: false,
                                      resolution: .lastSet)?.value ?? [:]
    }
}
