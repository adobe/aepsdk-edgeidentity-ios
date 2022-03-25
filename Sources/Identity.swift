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

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        state = IdentityState(identityProperties: IdentityProperties())
        super.init()
    }

    public func onRegistered() {
        registerListener(type: EventType.edgeIdentity, source: EventSource.requestIdentity, listener: handleIdentityRequest)
        registerListener(type: EventType.edgeIdentity, source: EventSource.updateIdentity, listener: handleUpdateIdentity)
        registerListener(type: EventType.edgeIdentity, source: EventSource.removeIdentity, listener: handleRemoveIdentity)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestReset, listener: handleRequestReset)
        registerListener(type: EventType.hub, source: EventSource.sharedState, listener: handleHubSharedState)
    }

    public func onUnregistered() {
    }

    public func readyForEvent(_ event: Event) -> Bool {
        return state.bootupIfReady(getSharedState: getSharedState(extensionName:event:),
                                   createXDMSharedState: createXDMSharedState(data:event:))
    }

    // MARK: Event Listeners

    /// Handles events requesting for identifiers. Called by listener registered with event hub.
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
        guard let configurationSharedState = getSharedState(extensionName: IdentityConstants.SharedState.Configuration.SHARED_OWNER_NAME, event: event)?.value else { return }

        // if config doesn't have org id we cannot proceed.
        guard let orgId = configurationSharedState[IdentityConstants.ConfigurationKeys.EXPERIENCE_CLOUD_ORGID] as? String, !orgId.isEmpty else {
            Log.trace(label: friendlyName, "\(#function) - Cannot process getUrlVariables request Identity event, experienceCloud.org is invalid or missing in configuration ")
            return
        }

        let properties = state.identityProperties
        let urlVariables = Self.generateURLVariablesPayload(configSharedState: configurationSharedState, identityProperties: properties)

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
        state.updateCustomerIdentifiers(event: event, createXDMSharedState: createXDMSharedState(data:event:))
    }

    /// Handles remove identity requests to remove customer identifiers.
    /// - Parameter event: the identity request event
    private func handleRemoveIdentity(event: Event) {
        state.removeCustomerIdentifiers(event: event, createXDMSharedState: createXDMSharedState(data:event:))
    }

    /// Handles `EventType.edgeIdentity` request reset events.
    /// - Parameter event: the identity request reset event
    private func handleRequestReset(event: Event) {
        state.resetIdentifiers(event: event,
                               createXDMSharedState: createXDMSharedState(data:event:),
                               eventDispatcher: dispatch(event:))
    }

    /// Handler for `EventType.hub` `EventSource.sharedState` events.
    /// If the state change event is for the Identity Direct extension, get the Identity Direct shared state, extract the ECID, and update the legacy ECID property.
    /// - Parameter event: shared state change event
    private func handleHubSharedState(event: Event) {
        guard let eventData = event.data,
              let stateowner = eventData[IdentityConstants.SharedState.STATE_OWNER] as? String,
              stateowner == IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME else {
            return
        }

        guard let identitySharedState = getSharedState(extensionName: IdentityConstants.SharedState.IdentityDirect.SHARED_OWNER_NAME, event: event)?.value else {
            return
        }

        // Get ECID. If doesn't exist then use empty string to clear legacy value
        let legacyEcid = identitySharedState[IdentityConstants.SharedState.IdentityDirect.VISITOR_ID_ECID] as? String ?? ""

        if state.updateLegacyExperienceCloudId(legacyEcid) {
            createXDMSharedState(data: state.identityProperties.toXdmData(), event: event)
        }
    }

    // MARK: GetUrlVariables helpers

    /// Helper function to generate url variables in format acceptable by the AEP web SDK
    static func generateURLVariablesPayload(configSharedState: [String: Any], identityProperties: IdentityProperties) -> String {
        // append timestamp
        var theIdString = appendParameterToUrlVariablesString(original: "", key: IdentityConstants.URLKeys.TIMESTAMP_KEY, value: String(Int(Date().timeIntervalSince1970)))

        // append ecid
        if let ecid = identityProperties.ecid {
            theIdString = appendParameterToUrlVariablesString(original: theIdString, key: IdentityConstants.URLKeys.MARKETING_CLOUD_ID_KEY, value: ecid)
        }

        // append org id
        if let orgId = configSharedState[IdentityConstants.ConfigurationKeys.EXPERIENCE_CLOUD_ORGID] as? String {
            theIdString = appendParameterToUrlVariablesString(original: theIdString, key: IdentityConstants.URLKeys.MARKETING_CLOUD_ORG_ID, value: orgId)
        }

        // encode adobe_mc string and append to the url
        let urlFragment = "\(IdentityConstants.URLKeys.PAYLOAD_KEY)=\(URLEncoder.encode(value: theIdString))"

        return urlFragment
    }

    /// Helper function to append key value to the url variable string
    private static func appendParameterToUrlVariablesString(original: String, key: String, value: String) -> String {
        if key.isEmpty || value.isEmpty {
            return original
        }

        let newUrlVar = "\(key)=\(value)"
        if original.isEmpty {
            return newUrlVar
        }

        return "\(original)|\(newUrlVar)"
    }
}
