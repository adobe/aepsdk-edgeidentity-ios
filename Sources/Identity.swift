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
    private var lastObservedConsent: String?

    public let runtime: ExtensionRuntime

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        state = IdentityState(identityProperties: IdentityProperties())
        super.init()
    }

    public func onRegistered() {
        registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity, listener: handleIdentityRequest)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestContent, listener: handleRequestContent)
        registerListener(type: EventType.genericProfileAttributes, source: EventSource.requestContent, listener: handleProfileAttributesContent)
        registerListener(type: EventType.edgeIdentity, source: EventSource.updateIdentity, listener: handleUpdateIdentity)
        registerListener(type: EventType.edgeIdentity, source: EventSource.removeIdentity, listener: handleRemoveIdentity)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestReset, listener: handleRequestReset)
        registerListener(type: EventType.hub, source: EventSource.sharedState, listener: handleHubSharedState)
        registerListener(type: EventType.edgeConsent, source: EventSource.responseContent, listener: handleConsentResponse(event:))
    }

    public func onUnregistered() {
    }

    public func readyForEvent(_ event: Event) -> Bool {
        // The closure passed to bootupIfReady is wrapped so that when identity properties are first
        // published, hydrated profile attributes are merged in — preventing the bootup publish from
        // wiping the profile attributes section that `onRegistered` populated.
        guard state.bootupIfReady(getSharedState: getSharedState(extensionName:event:),
                                  createXDMSharedState: { [weak self] data, sharedStateEvent in
                                      self?.createXDMSharedState(
                                          data: self?.enrichWithProfileAttributes(baseData: data) ?? data,
                                          event: sharedStateEvent)
                                  }) else {
            return false
        }

        if event.urlVariables {
            return getSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event: event, resolution: .lastSet)?.value != nil
        }

        return true
    }

    /// Adds hydrated profile attributes (read from persistent storage) into the given XDM shared
    /// state dict. Called from the bootupIfReady closure wrapper so the identity-properties publish
    /// also carries profile attributes from a previous session.
    private func enrichWithProfileAttributes(baseData: [String: Any]) -> [String: Any] {
        var data = baseData
        var hydrated: [String: String] = [:]
        for key in IdentityConstants.ProfileAttributes.allKeys {
            if let value = readStoredAttribute(key: key) {
                hydrated[key] = value
            }
        }
        let xdmAttributes = buildXdmData(from: hydrated)
        if !xdmAttributes.isEmpty {
            data[IdentityConstants.ProfileAttributes.STORE_NAME] = xdmAttributes
        }
        return data
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

    /// Handles `genericProfileAttributes + requestContent` events. Every event landing here is —
    /// by listener registration — a profile attribute event; there's nothing to discriminate
    /// against. Each handler self-checks for its own attribute (`guard let timezone = event.timezone`)
    /// and returns its XDM contribution or `nil`. All contributions are merged into a single
    /// `mergedXdm` dict so that a multi-attribute event produces exactly one shared-state update
    /// and one Edge event — never N separate dispatches.
    /// To add a new attribute: add a `handleFooSync` that returns its XDM contribution, an entry
    /// in `xdmKeyMap`, and one line in the routing block below. The merge step is automatic.
    private func handleProfileAttributesContent(event: Event) {
        let resolver = createPendingXDMSharedState(event: event)
        var mergedXdm: [String: String] = [:]

        if let xdm = handleTimezoneSync(event: event) {
            mergedXdm.merge(xdm) { _, new in new }
        }
        // if let xdm = handlePushIdentifierSync(event: event) {
        //     mergedXdm.merge(xdm) { _, new in new }
        // }

        guard !mergedXdm.isEmpty else {
            Log.debug(label: friendlyName, "\(#function) - No XDM contributions from any handler, skipping dispatch.")
            resolver(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
            return
        }
        publishMergedXdm(mergedXdm, event: event, resolveSharedState: resolver)
    }

    // MARK: - Attribute-specific handlers

    /// Extracts the timezone, validates it is a known IANA identifier, dedups against storage
    /// (inline check), persists, and returns its XDM contribution. The caller
    /// (`handleProfileAttributesContent`) merges this with other handlers' contributions and
    /// performs one shared-state update + one Edge dispatch. Returns `nil` when nothing should
    /// be contributed (invalid, unchanged, or no XDM mapping).
    private func handleTimezoneSync(event: Event) -> [String: String]? {
        guard let timezone = event.timezone else {
            Log.debug(label: friendlyName, "\(#function) - Timezone value missing or invalid in event data, ignoring.")
            return nil
        }
        guard TimeZone(identifier: timezone) != nil else {
            Log.warning(label: friendlyName, "\(#function) - '\(timezone)' is not a valid IANA timezone identifier, ignoring.")
            return nil
        }
        guard readStoredAttribute(key: IdentityConstants.ProfileAttributes.TIMEZONE) != timezone else {
            Log.debug(label: friendlyName, "\(#function) - Timezone unchanged, skipping sync.")
            return nil
        }

        writeStoredAttribute(key: IdentityConstants.ProfileAttributes.TIMEZONE, value: timezone)
        let xdmData = buildXdmData(from: [IdentityConstants.ProfileAttributes.TIMEZONE: timezone])
        return xdmData.isEmpty ? nil : xdmData
    }

    // Example: attribute-specific handler for push identifier.
    // Push token sync is owned by the app's push manager which already dedups (APNS only fires
    // when the token changes), so this handler skips the storage-equality check and proceeds
    // unconditionally. Compare with `handleTimezoneSync` which has an inline storage guard.
    //
    // private func handlePushIdentifierSync(event: Event) -> [String: String]? {
    //     guard let token = event.pushIdentifier else {
    //         Log.debug(label: friendlyName, "\(#function) - Push identifier missing in event data, ignoring.")
    //         return nil
    //     }
    //     writeStoredAttribute(key: IdentityConstants.ProfileAttributes.PUSH_IDENTIFIER, value: token)
    //     let xdmData = buildXdmData(from: [IdentityConstants.ProfileAttributes.PUSH_IDENTIFIER: token])
    //     return xdmData.isEmpty ? nil : xdmData
    // }

    // MARK: - Sync utilities

    /// Re-triggers the sync flow for every profile attribute the user previously opted into.
    /// Storage acts as the opt-in flag: presence of a key means "user has called the API for this
    /// attribute at least once." Each `syncFresh<X>` returns its XDM contribution; contributions
    /// are merged into a single shared-state update + Edge dispatch — exactly mirroring the
    /// inbound merge in `handleProfileAttributesContent`. Dedup is intentionally skipped because
    /// Edge dropped the original event during `n`.
    private func reSyncStoredProfileAttributes(event: Event) {
        let resolver = createPendingXDMSharedState(event: event)
        let optedInKeys = IdentityConstants.ProfileAttributes.allKeys.filter {
            readStoredAttribute(key: $0) != nil
        }

        guard !optedInKeys.isEmpty else {
            Log.debug(label: friendlyName, "\(#function) - No opted-in profile attributes to re-sync.")
            resolver(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
            return
        }

        var mergedXdm: [String: String] = [:]
        for key in optedInKeys {
            if let xdm = triggerFreshSync(for: key, event: event) {
                mergedXdm.merge(xdm) { _, new in new }
            }
        }

        guard !mergedXdm.isEmpty else {
            Log.debug(label: friendlyName, "\(#function) - No XDM contributions from re-sync, skipping dispatch.")
            resolver(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
            return
        }
        publishMergedXdm(mergedXdm, event: event, resolveSharedState: resolver)
    }

    /// Routes a re-sync request to the attribute-specific fresh-value flow, returning its XDM
    /// contribution. Adding a new attribute = one new case here + one new `syncFresh<Attribute>`.
    /// Without a registered handler, the key is silently skipped (logged) and contributes nothing.
    private func triggerFreshSync(for key: String, event: Event) -> [String: String]? {
        switch key {
        case IdentityConstants.ProfileAttributes.TIMEZONE:
            return syncFreshTimezone(event: event)
        // case IdentityConstants.ProfileAttributes.PUSH_IDENTIFIER:
        //     return syncFreshPushIdentifier(event: event)
        default:
            Log.warning(label: friendlyName, "\(#function) - No fresh-sync handler registered for key '\(key)', skipping.")
            return nil
        }
    }

    /// Reads the stored timezone (originally written and validated by `handleTimezoneSync`) and
    /// returns its XDM contribution for the caller to merge. No storage-equality check — consent
    /// re-sync must contribute even when the value equals storage, because Edge dropped the
    /// original event during `n`. The OS is never re-read from EdgeIdentity.
    private func syncFreshTimezone(event: Event) -> [String: String]? {
        guard let stored = readStoredAttribute(key: IdentityConstants.ProfileAttributes.TIMEZONE) else {
            Log.debug(label: friendlyName, "\(#function) - No stored timezone to re-sync, skipping.")
            return nil
        }
        let xdmData = buildXdmData(from: [IdentityConstants.ProfileAttributes.TIMEZONE: stored])
        return xdmData.isEmpty ? nil : xdmData
    }

    // Example: fresh-sync for an attribute the SDK can't re-resolve itself (push token is app-provided).
    // Returns the stored-value XDM contribution; the caller merges. Storage write is skipped because
    // the value is already there. Alternatively, the flow could publish a "please re-send" event.
    //
    // private func syncFreshPushIdentifier(event: Event) -> [String: String]? {
    //     guard let stored = readStoredAttribute(key: IdentityConstants.ProfileAttributes.PUSH_IDENTIFIER) else {
    //         Log.debug(label: friendlyName, "\(#function) - No stored push identifier to re-sync, skipping.")
    //         return nil
    //     }
    //     let xdmData = buildXdmData(from: [IdentityConstants.ProfileAttributes.PUSH_IDENTIFIER: stored])
    //     return xdmData.isEmpty ? nil : xdmData
    // }

    // MARK: - Merged XDM publish (future batching seam)

    /// Single choke point where fully-merged, deduped, already-persisted XDM exits EdgeIdentity:
    /// shared state is updated and one Edge event is dispatched. Both the inbound path
    /// (`handleProfileAttributesContent`) and the consent re-sync path (`reSyncStoredProfileAttributes`)
    /// funnel through here.
    ///
    /// Today this is a pass-through. It exists as a named seam so a future temporal-batching layer
    /// — buffer recent contributions, flush on a timer / foreground / consent change — can be added
    /// here without touching any handler or merge loop. Sketch of what the future body would do:
    ///
    ///     pendingXdm.merge(xdm) { _, new in new }
    ///     scheduleFlush(after: .milliseconds(N))
    ///     // …and a flush() that calls updateSharedState + dispatch once, with a chosen
    ///     // "representative event" for shared-state sequencing, plus drain-on-reset/consent-n.
    ///
    /// Not adding the buffer until profiling shows AEPEdge's hit queue isn't already absorbing the
    /// temporal proximity. The seam costs one indirection and zero runtime overhead.
    private func publishMergedXdm(_ xdm: [String: String], event: Event, resolveSharedState: ([String: Any]) -> Void) {
        resolveSharedState(enrichWithProfileAttributes(baseData: state.identityProperties.toXdmData()))
        dispatchProfileAttributesEdgeEvent(xdmData: xdm)
    }

    // MARK: - Storage helpers

    private func readStoredAttribute(key: String) -> String? {
        return ServiceProvider.shared.namedKeyValueService
            .get(collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: key) as? String
    }

    private func writeStoredAttribute(key: String, value: String) {
        ServiceProvider.shared.namedKeyValueService.remove(
            collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: key)
        ServiceProvider.shared.namedKeyValueService.set(
            collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: key, value: value)
    }

    /// Maps persistence storage keys → XDM data keys using `xdmKeyMap`.
    /// Unmapped keys are silently dropped — add them to `xdmKeyMap` to include them.
    private func buildXdmData(from attributes: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in attributes {
            if let xdmKey = IdentityConstants.ProfileAttributes.xdmKeyMap[key] {
                result[xdmKey] = value
            }
        }
        return result
    }

    // MARK: - Edge event dispatch

    /// Collects all XDM-mapped profile attribute data and dispatches a single Edge event.
    /// Future attributes are merged into the same `data` payload automatically via `buildXdmData`.
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
        for key in IdentityConstants.ProfileAttributes.allKeys {
            ServiceProvider.shared.namedKeyValueService.remove(
                collectionName: IdentityConstants.ProfileAttributes.STORE_NAME, key: key
            )
        }
        // Adding pending shared state to avoid race condition between updating and reading identity map
        let resolver = createPendingXDMSharedState(event: event)
        state.resetIdentifiers(event: event,
                               resolveXDMSharedState: resolver,
                               eventDispatcher: dispatch(event:))
    }

    /// Handles consent response events. When collect consent transitions to granted, re-syncs stored profile attributes to Edge.
    private func handleConsentResponse(event: Event) {
        let newConsent = extractCollectConsent(from: event.data)
        let wasNotGranted = lastObservedConsent == IdentityConstants.XDMKeys.Consent.NO
        lastObservedConsent = newConsent
        guard newConsent == IdentityConstants.XDMKeys.Consent.YES && wasNotGranted else {
            Log.debug(label: friendlyName, "\(#function) - Consent condition not met (new=\(newConsent ?? "nil"), wasNotGranted=\(wasNotGranted)), skipping re-sync.")
            return
        }

        reSyncStoredProfileAttributes(event: event)
    }

    private func extractCollectConsent(from eventData: [String: Any]?) -> String? {
        guard let consents = eventData?[IdentityConstants.XDMKeys.Consent.CONSENTS] as? [String: Any],
              let collect = consents[IdentityConstants.XDMKeys.Consent.COLLECT] as? [String: Any],
              let val = collect[IdentityConstants.XDMKeys.Consent.VAL] as? String else { return nil }
        return val
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
