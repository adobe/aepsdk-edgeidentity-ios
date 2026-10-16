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

import AEPCore
import AEPServices
import Foundation

@objc(AEPMobileEdgeIdentity) public class Identity: NSObject, Extension {

    // MARK: Extension
    public let name = IdentityConstants.EXTENSION_NAME
    public let friendlyName = IdentityConstants.FRIENDLY_NAME
    public static let extensionVersion = IdentityConstants.EXTENSION_VERSION
    public let metadata: [String: String]? = nil
    private(set) var state: IdentityState

    public let runtime: ExtensionRuntime

    // Central registry of every profile-path AttributeHandler, each bound to the PROFILE_ATTRIBUTES
    // dedup store. Add a new conforming type here to support an additional attribute — the collector in
    // handleProfileAttributes is attribute-agnostic.
    private let profileAttributeHandlers: [AttributeHandler] =
        [TimeZoneAttributeHandler(storeName: IdentityConstants.Store.PROFILE_ATTRIBUTES)]

    private let deviceAttributeDeduplicator = DeviceAttributeDeduplicator(storeName: IdentityConstants.Store.DEVICE_ATTRIBUTES)
    private var deviceAttributeQueue: [Event] = []
    // The Edge bypass request awaiting its result; nil when no request is in flight.
    private var activeDeviceAttributeRequest: Event?

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        state = IdentityState(identityProperties: IdentityProperties())
        super.init()
    }

    public func onRegistered() {
        registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity, listener: handleIdentityRequest)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestContent, listener: handleRequestContent)
        registerListener(type: EventType.genericProfileAttributes, source: EventSource.requestContent, listener: handleProfileAttributes)
        registerListener(type: EventType.edgeIdentity, source: EventSource.requestContent, listener: handleDeviceAttributes)
        registerListener(type: EventType.edgeIdentity,
                         source: IdentityConstants.DeviceAttributes.RULE_RESPONSE_SOURCE,
                         listener: handleDeviceAttributeRuleResponse)
        registerListener(type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                         source: EventSource.responseContent,
                         listener: handleDeviceAttributeResult)
        registerListener(type: EventType.messaging, source: EventSource.requestContent, listener: handleClearLiveActivities)
        registerListener(type: EventType.edgeIdentity, source: EventSource.updateIdentity, listener: handleUpdateIdentity)
        registerListener(type: EventType.edgeIdentity, source: EventSource.removeIdentity, listener: handleRemoveIdentity)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestReset, listener: handleRequestReset)
        registerListener(type: EventType.hub, source: EventSource.sharedState, listener: handleHubSharedState)
    }

    public func onUnregistered() {
    }

    public func readyForEvent(_ event: Event) -> Bool {
        // The closure passed to bootupIfReady is wrapped so that when identity properties are first
        // published, hydrated profile attributes are merged in — preventing the bootup publish from
        // wiping the profile attributes section that `onRegistered` populated.
        // On bootup, also publish the persisted profile attributes in the standard shared state.
        guard state.bootupIfReady(getSharedState: getSharedState(extensionName:event:),
                                  createXDMSharedState: { [weak self] data, sharedStateEvent in
                                      self?.createXDMSharedState(
                                          data: self?.enrichWithProfileAttributes(baseData: data) ?? data,
                                          event: sharedStateEvent)
                                      self?.publishProfileAttributes(event: sharedStateEvent)
                                  }) else {
            return false
        }

        if event.urlVariables {
            return getSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event: event, resolution: .lastSet)?.value != nil
        }

        return true
    }

    /// Collects every handler's persisted contribution into a single map.
    /// Mirrors Android's `collectStoredAttributes()` in `IdentityState`.
    private func collectStoredAttributes() -> [String: String] {
        var merged: [String: String] = [:]
        for handler in profileAttributeHandlers {
            guard let contribution = handler.collectFromStorage() else { continue }
            merged.merge(contribution) { _, new in new }
        }
        return merged
    }

    /// Merges stored profile attributes into the given XDM shared state dict under the
    /// profile-attributes store key. iOS-specific: Android publishes these as a separate
    /// non-XDM shared state rather than embedding them in the identity shared state.
    private func enrichWithProfileAttributes(baseData: [String: Any]) -> [String: Any] {
        var data = baseData
        let merged = collectStoredAttributes()
        if !merged.isEmpty {
            data[IdentityConstants.ProfileAttributes.STORE_NAME] = merged
        }
        return data
    }

    /// Publishes the standard shared state `{"profileAttributes": {...}}`: the synced device attributes
    /// merged with the profile-path timezone.
    private func publishProfileAttributes(event: Event?) {
        var attributes = deviceAttributeDeduplicator.readSynced()
        if let timezone = collectStoredAttributes()[TimeZoneAttributeHandler.key] {
            attributes[IdentityConstants.DeviceAttributes.TIMEZONE] = timezone
        }
        createSharedState(data: [IdentityConstants.ProfileAttributes.SHARED_STATE_KEY: attributes], event: event)
    }

    // MARK: Event Listeners

    /// Handles `genericIdentity + requestContent` events (advertising identifier only).
    private func handleRequestContent(event: Event) {
        if event.isAdIdEvent {
            state.updateAdvertisingIdentifier(event: event,
                                              createXDMSharedState: createXDMSharedState(data:event:),
                                              eventDispatcher: dispatch(event:))
        }
    }

    /// Handles `genericProfileAttributes + requestContent` events. Runs every registered
    /// `AttributeHandler` whose key is present in the event, merges contributions, and
    /// dispatches one Edge event if anything changed. To add a new attribute, create a conforming
    /// type and append it to `profileAttributeHandlers` — this function needs no changes.
    private func handleProfileAttributes(event: Event) {
        guard let eventData = event.data, !eventData.isEmpty else {
            Log.debug(label: friendlyName, "\(#function) - Event data empty, skipping.")
            let resolver = createPendingXDMSharedState(event: event)
            resolver(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
            return
        }
        let resolver = createPendingXDMSharedState(event: event)
        var merged: [String: String] = [:]
        for handler in profileAttributeHandlers {
            guard eventData.keys.contains(handler.attributeKey) else { continue }
            // Profile path always dedups (dedup: true) — this preserves the pre-existing profile-sync
            // behavior; the dedup config flag applies only to the device path.
            guard let contribution = handler.collectFromEvent(event, dedup: true) else { continue }
            merged.merge(contribution) { _, new in new }
        }
        guard !merged.isEmpty else {
            Log.debug(label: friendlyName, "\(#function) - No attribute changes from any handler, skipping dispatch.")
            resolver(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
            return
        }
        publishProfileAttributesSharedState(merged, event: event, resolveSharedState: resolver)
    }

    // MARK: - Shared state + Edge dispatch

    private func publishProfileAttributesSharedState(_ xdm: [String: String], event: Event, resolveSharedState: ([String: Any]) -> Void) {
        resolveSharedState(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
        publishProfileAttributes(event: event)
        dispatchProfileAttributesEdgeEvent(xdmData: xdm)
    }

    // MARK: - Edge event dispatch

    /// Collects all XDM-mapped profile attribute data and dispatches a single Edge event.
    /// Future attributes are merged into the same `data` payload automatically.
    private func dispatchProfileAttributesEdgeEvent(xdmData: [String: String]) {
        let eventData: [String: Any] = [
            IdentityConstants.ProfileAttributes.XDM.XDM_KEY: [
                IdentityConstants.ProfileAttributes.XDM.EVENT_TYPE_KEY: IdentityConstants.ProfileAttributes.XDM.PROFILE_UPDATE_EVENT_TYPE
            ],
            IdentityConstants.ProfileAttributes.XDM.DATA_KEY: xdmData
        ]
        let event = Event(name: IdentityConstants.EventNames.UPDATE_PROFILE_ATTRIBUTES,
                          type: EventType.edge,
                          source: EventSource.requestContent,
                          data: eventData)
        dispatch(event: event)
    }

    /// Handles events requesting for identifiers. Dispatches response event containing the identifiers. Called by listener registered with event hub.
    /// - Parameter event: the identity request event
    private func handleIdentityRequest(event: Event) {
        if event.urlVariables {
            processGetUrlVariablesRequest(event: event)
        } else {
            processGetIdentifiersRequest(event: event)
        }
    }

    /// Handles events requesting for url variables. Dispatches response event containing the url variables string.
    /// - Parameter event: the identity request event
    func processGetUrlVariablesRequest(event: Event) {
        let emptyResponseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_URL_VARIABLES,
                                                           type: EventType.edgeIdentity,
                                                           source: EventSource.responseIdentity,
                                                           data: [IdentityConstants.EventDataKeys.URL_VARIABLES: ""])

        guard let configurationSharedState = getSharedState(
                extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                event: event,
                resolution: .lastSet)?.value
        else {
            Log.warning(label: friendlyName, "\(#function) - Cannot process getUrlVariables request Identity event, configuration not found.")
            dispatch(event: emptyResponseEvent)
            return
        }

        // org id is required to process the URL variables request
        guard let orgId = configurationSharedState[IdentityConstants.ConfigurationKeys.EXPERIENCE_CLOUD_ORGID] as? String, !orgId.isEmpty else {
            Log.warning(label: friendlyName, "\(#function) - Cannot process getUrlVariables request Identity event, experienceCloud.org is invalid or missing in configuration.")
            dispatch(event: emptyResponseEvent)
            return
        }

        guard let ecid = state.identityProperties.ecid else {
            Log.warning(label: friendlyName, "\(#function) - Cannot process getUrlVariables request Identity event, ECID is nil or not yet generated by the SDK.")
            dispatch(event: emptyResponseEvent)
            return
        }
        let tsString = String(Int(Date().timeIntervalSince1970))
        let urlVariables = URLUtils.generateURLVariablesPayload(timestamp: tsString, ecid: ecid, orgId: orgId)

        let responseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_URL_VARIABLES,
                                                      type: EventType.edgeIdentity,
                                                      source: EventSource.responseIdentity,
                                                      data: [IdentityConstants.EventDataKeys.URL_VARIABLES: urlVariables])

        // dispatch identity response event with shared state data
        dispatch(event: responseEvent)
    }

    /// Handles events requesting for identifiers. Dispatches response event containing the identifiers.
    /// - Parameter event: the identity request event
    func processGetIdentifiersRequest(event: Event) {
        // handle getECID or getIdentifiers API
        let xdmData = state.identityProperties.toXdmData(true)
        let responseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_CONTENT_ONE_TIME,
                                                      type: EventType.edgeIdentity,
                                                      source: EventSource.responseIdentity,
                                                      data: xdmData)

        // dispatch identity response event with shared state data
        dispatch(event: responseEvent)
    }

    /// Handles update identity requests to add/update customer identifiers.
    /// - Parameter event: the identity request event
    private func handleUpdateIdentity(event: Event) {
        // Adding pending shared state to avoid race condition between updating and reading identity map
        let resolver = createPendingXDMSharedState(event: event)
        state.updateCustomerIdentifiers(event: event, resolveXDMSharedState: resolver)
    }

    /// Handles remove identity requests to remove customer identifiers.
    /// - Parameter event: the identity request event
    private func handleRemoveIdentity(event: Event) {
        // Adding pending shared state to avoid race condition between updating and reading identity map
        let resolver = createPendingXDMSharedState(event: event)
        state.removeCustomerIdentifiers(event: event, resolveXDMSharedState: resolver)
    }

    /// Handles `EventType.edgeIdentity` request reset events.
    /// - Parameter event: the identity request reset event
    private func handleRequestReset(event: Event) {
        for handler in profileAttributeHandlers {
            ServiceProvider.shared.namedKeyValueService.remove(
                collectionName: handler.storeName, key: handler.attributeKey)
        }
        // Clear stored device attributes and pending requests for the new identity. A late Edge result is ignored.
        // TODO: Publish a sync result event for requests dropped by reset.
        deviceAttributeDeduplicator.clear()
        deviceAttributeQueue.removeAll()
        activeDeviceAttributeRequest = nil
        let resolver = createPendingXDMSharedState(event: event)
        state.resetIdentifiers(event: event,
                               resolveXDMSharedState: resolver,
                               eventDispatcher: dispatch(event:))
        publishProfileAttributes(event: event)
    }

    /// Handler for `EventType.hub` `EventSource.sharedState` events.
    /// If the state change event is for the Identity Direct extension, get the Identity Direct shared state, extract the ECID, and update the legacy ECID property.
    /// - Parameter event: shared state change event
    private func handleHubSharedState(event: Event) {
        guard let eventData = event.data,
              let stateowner = eventData[IdentityConstants.EventDataKeys.STATE_OWNER] as? String,
              stateowner == IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME else {
            return
        }

        guard let identitySharedState = getSharedState(extensionName: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME, event: event)?.value else {
            return
        }

        // Get ECID. If doesn't exist then use empty string to clear legacy value
        let legacyEcid = identitySharedState[IdentityConstants.SharedState.IdentityDirect.VISITOR_ID_ECID] as? String ?? ""

        if state.updateLegacyExperienceCloudId(legacyEcid) {
            createXDMSharedState(data: enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()), event: event)
        }
    }
}

// MARK: - Device attributes (consent-independent) -> operational-data event

extension Identity {
    /// Sends the public API's attributes to rules without checking or changing dedup state.
    private func handleDeviceAttributes(event: Event) {
        // The edgeIdentity/requestContent pair is shared; only the API's own request may be forwarded,
        // so data from any other event on this pair never reaches the consent-independent path.
        guard event.name == IdentityConstants.EventNames.UPDATE_DEVICE_ATTRIBUTES else {
            Log.trace(label: friendlyName, "\(#function) - Ignoring event '\(event.name)', not a device-attributes request.")
            return
        }
        guard let eventData = event.data, !eventData.isEmpty else {
            Log.warning(label: friendlyName, "\(#function) - Device attributes request has no data, dropping it.")
            return
        }

        Log.debug(label: friendlyName, "\(#function) - Forwarding device attributes to the rules engine. " +
                    "Nothing is sent unless a forward operational data rule matches.")
        let operationalEvent = event.createChainedEvent(
            name: IdentityConstants.EventNames.DEVICE_ATTRIBUTES_TO_RULES_ENGINE,
            type: IdentityConstants.DeviceAttributes.OPERATIONAL_DATA_TYPE,
            source: IdentityConstants.DeviceAttributes.OPERATIONAL_DATA_SOURCE,
            data: eventData)
        dispatch(event: operationalEvent)
    }

    /// Queues a forward operational data rule consequence and sends it when no other request is active.
    private func handleDeviceAttributeRuleResponse(event: Event) {
        guard let data = event.data, !data.isEmpty else {
            Log.debug(label: friendlyName, "Rule response contains no device attributes.")
            return
        }
        deviceAttributeQueue.append(event)
        processDeviceAttributeQueue()
    }

    /// Sends queued requests to Edge one at a time. Requests with nothing left to send are skipped.
    private func processDeviceAttributeQueue() {
        while activeDeviceAttributeRequest == nil, !deviceAttributeQueue.isEmpty {
            let request = deviceAttributeQueue.removeFirst()
            guard let edgeEvent = makeDeviceAttributeEdgeEvent(for: request) else { continue }
            activeDeviceAttributeRequest = edgeEvent
            dispatch(event: edgeEvent)
        }
    }

    /// Builds the Edge bypass event for a rule consequence, or returns nil when nothing needs to be sent.
    private func makeDeviceAttributeEdgeEvent(for request: Event) -> Event? {
        let config = getSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME,
                                    event: nil,
                                    resolution: .lastSet)?.value
        let dedup = config?[IdentityConstants.ConfigKeys.OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC] as? Bool ?? true
        // Owner values are trusted only with collect consent "y"; otherwise only the device attributes store is compared.
        let compareOwners = dedup && isCollectConsentGranted()
        let messagingState = compareOwners
            ? getSharedState(extensionName: IdentityConstants.SharedState.Messaging.SHARED_OWNER_NAME,
                             event: nil,
                             resolution: .lastSet)?.value : nil
        let timezone = compareOwners ? collectStoredAttributes()[TimeZoneAttributeHandler.key] : nil
        let result = deviceAttributeDeduplicator.filter(request.data ?? [:],
                                                        dedup: dedup,
                                                        messagingState: messagingState,
                                                        timezone: timezone)
        if !result.ownerMatches.isEmpty {
            // The owner already holds these values; store them so later requests dedup without the owner.
            deviceAttributeDeduplicator.commit(result.ownerMatches)
        }

        var payload = result.toSend
        guard !payload.isEmpty else {
            // TODO: Publish a sync result event when every value is deduplicated.
            Log.debug(label: friendlyName, "No device attributes remain after deduplication for rule event \(request.id). Skipping Edge dispatch.")
            return nil
        }
        guard let appId = Bundle.main.bundleIdentifier, !appId.isEmpty else {
            Log.warning(label: friendlyName, "Cannot send device attributes without an app bundle identifier. Dropping rule event \(request.id).")
            return nil
        }
        let useSandbox = config?[IdentityConstants.DeviceAttributes.MESSAGING_USE_SANDBOX] as? Bool ?? false
        payload[IdentityConstants.DeviceAttributes.APP] = [
            IdentityConstants.DeviceAttributes.APP_ID: appId,
            IdentityConstants.DeviceAttributes.APP_PLATFORM: useSandbox
                ? IdentityConstants.DeviceAttributes.PLATFORM_APNS_SANDBOX : IdentityConstants.DeviceAttributes.PLATFORM_APNS
        ]
        return request.createChainedEvent(name: IdentityConstants.EventNames.DEVICE_ATTRIBUTES_BYPASS_REQUEST,
                                          type: IdentityConstants.DeviceAttributes.BYPASS_TYPE,
                                          source: EventSource.requestContent,
                                          data: payload)
    }

    /// Returns true when collect consent is "y". Like the Edge extension, consent is "y" when the Consent extension is not registered.
    /// Before the Event Hub publishes its registered extensions, consent is treated as not "y".
    private func isCollectConsentGranted() -> Bool {
        typealias Consent = IdentityConstants.XDMKeys.Consent
        guard let hubState = getSharedState(extensionName: IdentityConstants.SharedState.Hub.SHARED_OWNER_NAME, event: nil)?.value else {
            return false
        }
        let extensions = hubState[IdentityConstants.SharedState.Hub.EXTENSIONS] as? [String: Any]
        let consentExtension = extensions?[IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME] as? [String: Any]
        guard let consentExtension = consentExtension, !consentExtension.isEmpty else { return true }
        // Do not fall back to an older "y" when the latest consent state is pending.
        guard let state = getXDMSharedState(extensionName: IdentityConstants.SharedState.Consent.SHARED_OWNER_NAME,
                                            event: nil,
                                            resolution: .any),
              state.status == .set,
              let consents = state.value?[Consent.CONSENTS] as? [String: Any],
              let collect = consents[Consent.COLLECT] as? [String: Any] else { return false }
        return collect[Consent.VAL] as? String == Consent.YES
    }

    /// Handles the Edge result for a device attributes request. A result for the active request always
    /// releases it and advances the queue. Any status other than success is treated as failed.
    private func handleDeviceAttributeResult(event: Event) {
        typealias Keys = IdentityConstants.DeviceAttributes
        guard let request = activeDeviceAttributeRequest, isResult(event, for: request) else {
            Log.debug(label: friendlyName, "Ignoring device attribute result \(event.id), it does not match the active request.")
            return
        }
        activeDeviceAttributeRequest = nil

        if event.data?[Keys.STATUS] as? String == Keys.STATUS_SUCCESS {
            var attributes = request.data ?? [:]
            attributes.removeValue(forKey: Keys.APP)
            deviceAttributeDeduplicator.commit(attributes)
            if let timezone = attributes[Keys.TIMEZONE] as? String {
                ServiceProvider.shared.namedKeyValueService.set(collectionName: IdentityConstants.Store.PROFILE_ATTRIBUTES,
                                                                key: TimeZoneAttributeHandler.key,
                                                                value: timezone)
            }
            publishProfileAttributes(event: event)
            dispatchDeviceAttributeSyncResult([Keys.STATUS: Keys.STATUS_SUCCESS, Keys.ATTRIBUTES: attributes], for: event)
            Log.debug(label: friendlyName, "Device attributes confirmed by Edge for request \(request.id).")
        } else {
            var data: [String: Any] = [Keys.STATUS: Keys.STATUS_FAILED]
            if let reason = event.data?[Keys.REASON] {
                data[Keys.REASON] = reason
            }
            dispatchDeviceAttributeSyncResult(data, for: event)
            Log.warning(label: friendlyName, "Device attribute sync failed with status '\(event.data?[Keys.STATUS] ?? "missing")', " +
                            "reason: \(event.data?[Keys.REASON] ?? "unknown"). Values remain unsynced.")
        }
        processDeviceAttributeQueue()
    }

    /// An Edge result belongs to a request when it is chained to it, or names it in `requestEventId` (unchained results).
    private func isResult(_ event: Event, for request: Event) -> Bool {
        if event.parentID == request.id { return true }
        guard let requestEventId = event.data?[IdentityConstants.DeviceAttributes.REQUEST_EVENT_ID] as? String else { return false }
        return UUID(uuidString: requestEventId) == request.id
    }

    private func dispatchDeviceAttributeSyncResult(_ data: [String: Any], for event: Event) {
        dispatch(event: event.createChainedEvent(name: IdentityConstants.EventNames.DEVICE_ATTRIBUTES_SYNC_RESULT,
                                                 type: EventType.edgeIdentity,
                                                 source: EventSource.responseContent,
                                                 data: data))
    }

    /// Removes the Live Activity tokens when Messaging clears its Live Activities.
    private func handleClearLiveActivities(event: Event) {
        typealias Keys = IdentityConstants.DeviceAttributes
        guard event.data?[Keys.CLEAR_LIVE_ACTIVITIES] as? Bool == true else { return }
        deviceAttributeDeduplicator.remove(paths: [[Keys.TOKENS, Keys.LIVE_ACTIVITY_START],
                                                   [Keys.TOKENS, Keys.LIVE_ACTIVITY_UPDATE]])
        publishProfileAttributes(event: event)
    }
}
