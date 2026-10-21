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

/// Sends operational data from `updateOperationalData` to Edge without checking collect consent.
/// The public API data is forwarded to the rules engine; a Launch rule with a forward operational data consequence
/// responds with the attributes that may be sent. The timezone, push token and push-to-start tokens are sent only
/// when they change; all other values are always sent. Rule responses are queued and sent to Edge one at a time as
/// device attributes request events; the next one is sent when the device attributes response event arrives.
final class OperationalDataSync {
    private static let LOG_SOURCE = "OperationalDataSync"

    private let runtime: ExtensionRuntime
    private let deduplicator = OperationalDataDeduplicator(storeName: IdentityConstants.DataStoreKeys.OPERATIONAL_DATA_DATASTORE_NAME)
    private var pendingRequests: [Event] = []
    private var activeRequest: Event?

    init(runtime: ExtensionRuntime) {
        self.runtime = runtime
    }

    /// Forwards public API data to the rules engine, which decides which attributes may be sent.
    func handleOperationalData(event: Event) {
        guard let data = event.data, !data.isEmpty else {
            Log.warning(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Ignoring empty operational data request.")
            return
        }
        Log.debug(label: IdentityConstants.LOG_TAG,
                  "\(Self.LOG_SOURCE) - Forwarding operational data to the rules engine. " +
                    "Nothing is sent to Edge unless a forward operational data rule matches.")
        runtime.dispatch(event: event.createChainedEvent(name: IdentityConstants.EventNames.OPERATIONAL_DATA_TO_RULES_ENGINE,
                                                         type: IdentityConstants.OperationalData.OPERATIONAL_DATA_TYPE,
                                                         source: EventSource.requestContent,
                                                         data: data))
    }

    /// Queues a rule response until the active request gets its device attributes response event.
    func handleOperationalDataRuleResponse(event: Event) {
        guard let data = event.data, !data.isEmpty else {
            Log.debug(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Rule response contains no operational data.")
            return
        }
        pendingRequests.append(event)
        processQueue()
    }

    /// Sends queued requests until one is waiting for its device attributes response event or the queue is empty.
    private func processQueue() {
        while activeRequest == nil, !pendingRequests.isEmpty {
            guard let request = buildEdgeRequest(pendingRequests.removeFirst()) else { continue }
            activeRequest = request
            Log.debug(label: IdentityConstants.LOG_TAG,
                      "\(Self.LOG_SOURCE) - Sending operational data to Edge (request '\(request.id.uuidString)').")
            runtime.dispatch(event: request)
        }
    }

    /// Returns the device attributes request event for the changed values in `ruleResponse`, or nil if there is
    /// nothing to send.
    private func buildEdgeRequest(_ ruleResponse: Event) -> Event? {
        typealias Keys = IdentityConstants.OperationalData
        var attributes = ruleResponse.data ?? [:]
        attributes.removeValue(forKey: Keys.APP)
        let config = configuration()
        let dedup = config[Keys.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC] as? Bool ?? true
        let result = dedup
            ? deduplicator.filter(attributes, owners: isCollectConsentYes() ? ownerValues(attributes) : nil)
            : OperationalDataDeduplicator.FilterResult(changed: attributes, ownerMatches: [:])
        if !result.ownerMatches.isEmpty {
            deduplicator.commit(result.ownerMatches)
            Log.debug(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Marked operational data held by its owner as synced.")
            publishProfileAttributes(event: ruleResponse)
        }
        var changed = result.changed
        guard !changed.isEmpty else {
            Log.debug(label: IdentityConstants.LOG_TAG,
                      "\(Self.LOG_SOURCE) - Operational data unchanged, not sending to Edge (rule event '\(ruleResponse.id.uuidString)').")
            dispatchSyncResult(status: Keys.STATUS_SUCCESS, reason: Keys.REASON_UNCHANGED, attributes: attributes, parent: ruleResponse)
            return nil
        }

        guard let appId = Bundle.main.bundleIdentifier, !appId.isEmpty else {
            Log.warning(label: IdentityConstants.LOG_TAG,
                        "\(Self.LOG_SOURCE) - Cannot send operational data without an app identifier. " +
                            "Dropping rule event '\(ruleResponse.id.uuidString)'.")
            dispatchSyncResult(status: Keys.STATUS_FAILED, reason: Keys.REASON_MISSING_APP_IDENTIFIER, attributes: changed, parent: ruleResponse)
            return nil
        }
        let useSandbox = config[Keys.MESSAGING_USE_SANDBOX] as? Bool ?? false
        changed[Keys.APP] = [
            Keys.APP_ID: appId,
            Keys.APP_PLATFORM: useSandbox ? Keys.PLATFORM_APNS_SANDBOX : Keys.PLATFORM_APNS
        ]
        return ruleResponse.createChainedEvent(name: IdentityConstants.EventNames.EDGE_DEVICE_ATTRIBUTES_REQUEST,
                                               type: Keys.EDGE_DEVICE_ATTRIBUTES_TYPE,
                                               source: EventSource.requestContent,
                                               data: changed)
    }

    /// Handles the device attributes response event for the active request, then sends the next queued request.
    func handleOperationalDataResult(event: Event) {
        typealias Keys = IdentityConstants.OperationalData
        guard let request = activeRequest, isResponseToActiveRequest(event) else {
            Log.debug(label: IdentityConstants.LOG_TAG,
                      "\(Self.LOG_SOURCE) - Ignoring device attribute response '\(event.id.uuidString)', it does not match the active request.")
            return
        }
        activeRequest = nil
        let requestId = request.id.uuidString
        var attributes = request.data ?? [:]
        attributes.removeValue(forKey: Keys.APP)

        let status = event.data?[Keys.STATUS] as? String
        if status == Keys.STATUS_SUCCESS {
            deduplicator.commit(attributes)
            if let timezone = attributes[Keys.TIMEZONE] as? String {
                ServiceProvider.shared.namedKeyValueService
                    .set(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: Keys.TIME_ZONE, value: timezone)
            }
            publishProfileAttributes(event: event)
            Log.debug(label: IdentityConstants.LOG_TAG, "\(Self.LOG_SOURCE) - Operational data synced (request '\(requestId)').")
            dispatchTokensConfirmed(attributes: attributes, parent: event)
            dispatchSyncResult(status: Keys.STATUS_SUCCESS, reason: "", attributes: attributes, parent: event)
        } else {
            let reason = event.data?[Keys.REASON] as? String ?? Keys.UNKNOWN_REASON
            Log.warning(label: IdentityConstants.LOG_TAG,
                        "\(Self.LOG_SOURCE) - Operational data sync failed (request '\(requestId)') with status '\(status ?? "missing")' " +
                            "and reason '\(reason)'. Values remain unsynced.")
            dispatchSyncResult(status: Keys.STATUS_FAILED, reason: reason, attributes: attributes, parent: event)
        }
        processQueue()
    }

    /// Dispatches the sync result for a request, with `parent` as its parent event. `attributes` must not contain `app`.
    private func dispatchSyncResult(status: String, reason: String, attributes: [String: Any], parent: Event) {
        typealias Keys = IdentityConstants.OperationalData
        let data: [String: Any] = [Keys.STATUS: status, Keys.REASON: reason, Keys.ATTRIBUTES: attributes]
        runtime.dispatch(event: parent.createChainedEvent(name: IdentityConstants.EventNames.OPERATIONAL_DATA_SYNC_RESULT,
                                                          type: EventType.edgeIdentity,
                                                          source: EventSource.responseContent,
                                                          data: data))
    }

    /// Tells Messaging which tokens Edge confirmed, with `parent` as the parent event. Nothing is dispatched without
    /// tokens.
    private func dispatchTokensConfirmed(attributes: [String: Any], parent: Event) {
        guard let tokens = attributes[IdentityConstants.OperationalData.TOKENS] as? [String: Any], !tokens.isEmpty else { return }
        runtime.dispatch(event: parent.createChainedEvent(name: IdentityConstants.EventNames.OPERATIONAL_DATA_CONFIRMED,
                                                          type: EventType.messaging,
                                                          source: EventSource.responseContent,
                                                          data: [IdentityConstants.OperationalData.TOKENS: tokens]))
    }

    /// A response matches when its parent event is the active request or its `requestEventId` names it.
    private func isResponseToActiveRequest(_ event: Event) -> Bool {
        guard let request = activeRequest else { return false }
        return event.parentID == request.id ||
            event.data?[IdentityConstants.OperationalData.REQUEST_EVENT_ID] as? String == request.id.uuidString
    }

    /// Returns the values their owners already hold, in the same shape as the operational data: the timezone set
    /// through the profile attributes API and the push token in Messaging's shared state.
    /// iOS only: the push-to-start token list is owner-held when Messaging holds every token in it, so `attributes`
    /// is needed to build it.
    private func ownerValues(_ attributes: [String: Any]) -> [String: Any] {
        typealias Keys = IdentityConstants.OperationalData
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
        if let entries = input?[Keys.LIVE_ACTIVITY_START] as? [[String: Any]],
           let stored = liveActivity?[Messaging.PUSH_TO_START_TOKENS] as? [String: [String: Any]] {
            let held = entries.isEmpty ? stored.isEmpty : entries.allSatisfy { entry in
                guard let id = entry[Keys.ATTRIBUTE_TYPE] as? String, let token = entry[Keys.VALUE] as? String else { return false }
                return stored[id]?[Messaging.TOKEN] as? String == token
            }
            if held {
                tokens[Keys.LIVE_ACTIVITY_START] = entries
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

    /// Dispatches a failed result for the active request and each queued request, then clears them and all confirmed
    /// operational data and republishes the profile attributes. The profile attribute store itself is cleared by
    /// `Identity.handleRequestReset`.
    func reset(event: Event) {
        typealias Keys = IdentityConstants.OperationalData
        if let request = activeRequest {
            dispatchSyncResult(status: Keys.STATUS_FAILED,
                               reason: Keys.REASON_IDENTITY_RESET,
                               attributes: (request.data ?? [:]).filter { $0.key != Keys.APP },
                               parent: request)
        }
        for ruleResponse in pendingRequests {
            dispatchSyncResult(status: Keys.STATUS_FAILED,
                               reason: Keys.REASON_IDENTITY_RESET,
                               attributes: (ruleResponse.data ?? [:]).filter { $0.key != Keys.APP },
                               parent: ruleResponse)
        }
        pendingRequests.removeAll()
        activeRequest = nil
        deduplicator.clear()
        publishProfileAttributes(event: event)
        Log.debug(label: IdentityConstants.LOG_TAG,
                  "\(Self.LOG_SOURCE) - Cleared operational data requests and synced values after identity reset.")
    }

    /// iOS only: removes the confirmed Live Activity push-to-start tokens when Messaging clears its Live Activities.
    func handleClearLiveActivities(event: Event) {
        typealias Keys = IdentityConstants.OperationalData
        guard event.data?[Keys.CLEAR_LIVE_ACTIVITIES] as? Bool == true else { return }
        deduplicator.clearLiveActivityStart()
        publishProfileAttributes(event: event)
        Log.debug(label: IdentityConstants.LOG_TAG,
                  "\(Self.LOG_SOURCE) - Cleared Live Activity tokens after Messaging cleared Live Activities.")
    }

    /// Publishes the confirmed operational data, merged with the timezone from the profile attribute store, in the
    /// standard shared state.
    func publishProfileAttributes(event: Event?) {
        runtime.createSharedState(data: [IdentityConstants.ProfileAttributes.SHARED_STATE_KEY: profileAttributes()], event: event)
    }

    /// Publishes the persisted profile attributes at registration. Nothing is published when nothing is stored.
    func publishStoredProfileAttributes() {
        let attributes = profileAttributes()
        guard !attributes.isEmpty else { return }
        runtime.createSharedState(data: [IdentityConstants.ProfileAttributes.SHARED_STATE_KEY: attributes], event: nil)
    }

    private func profileAttributes() -> [String: Any] {
        var attributes = deduplicator.readSynced()
        if let timezone = profileTimezone() {
            attributes[IdentityConstants.OperationalData.TIMEZONE] = timezone
        }
        return attributes
    }

    private func profileTimezone() -> String? {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME,
                 key: IdentityConstants.OperationalData.TIME_ZONE) as? String
    }

    private func configuration() -> [String: Any] {
        return runtime.getSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                      event: nil,
                                      barrier: false,
                                      resolution: .lastSet)?.value ?? [:]
    }
}
