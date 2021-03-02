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
import Foundation

@objc(AEPMobileIdentityEdge) public class IdentityEdge: NSObject, Extension {

    // MARK: Extension
    public let name = IdentityEdgeConstants.EXTENSION_NAME
    public let friendlyName = IdentityEdgeConstants.FRIENDLY_NAME
    public static let extensionVersion = IdentityEdgeConstants.EXTENSION_VERSION
    public let metadata: [String: String]? = nil
    private(set) var state: IdentityEdgeState?

    public let runtime: ExtensionRuntime

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        super.init()
        state = IdentityEdgeState(identityEdgeProperties: IdentityEdgeProperties())
    }

    public func onRegistered() {
        registerListener(type: EventType.identityEdge, source: EventSource.requestIdentity, listener: handleIdentityRequest)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestContent, listener: handleRequestContent)
        registerListener(type: EventType.identityEdge, source: EventSource.updateIdentity, listener: handleUpdateIdentity)
        registerListener(type: EventType.identityEdge, source: EventSource.removeIdentity, listener: handleRemoveIdentity)
        registerListener(type: EventType.identityEdge, source: EventSource.requestReset, listener: handleRequestReset)
        registerListener(type: EventType.hub, source: EventSource.sharedState, listener: handleHubSharedState)
    }

    public func onUnregistered() {
    }

    public func readyForEvent(_ event: Event) -> Bool {
        guard canProcessEvents(event: event) else { return false }
        return true
    }

    /// Determines if Identity Edge is ready to handle events, this is determined by if the Identity Edge extension has booted up
    /// - Parameter event: An `Event`
    /// - Returns: True if we can process events, false otherwise
    private func canProcessEvents(event: Event) -> Bool {
        guard let state = state else { return false }
        guard !state.hasBooted else { return true } // we have booted, return true

        // attempt to bootup
        if state.bootupIfReady() {
            createXDMSharedState(data: state.identityEdgeProperties.toXdmData(), event: nil)
            return true
        }

        return false // cannot handle any events until we have booted

    }

    // MARK: Event Listeners

    /// Handles events to set the advertising identifier. Called by listener registered with event hub.
    /// - Parameter event: event containing `advertisingIdentifier` data
    private func handleRequestContent(event: Event) {
        state?.updateAdvertisingIdentifier(event: event,
                                           createXDMSharedState: createXDMSharedState(data:event:),
                                           dispatchEvent: dispatch(event:))
    }

    /// Handles events requesting for identifiers. Dispatches response event containing the identifiers. Called by listener registered with event hub.
    /// - Parameter event: the identity request event
    private func handleIdentityRequest(event: Event) {
        let xdmData = state?.identityEdgeProperties.toXdmData(true)
        let responseEvent = event.createResponseEvent(name: IdentityEdgeConstants.EventNames.IDENTITY_RESPONSE_CONTENT_ONE_TIME,
                                                      type: EventType.identityEdge,
                                                      source: EventSource.responseIdentity,
                                                      data: xdmData)

        // dispatch identity response event with shared state data
        dispatch(event: responseEvent)
    }

    /// Handles update identity requests to add/update customer identifiers.
    /// - Parameter event: the identity request event
    private func handleUpdateIdentity(event: Event) {
        state?.updateCustomerIdentifiers(event: event, createXDMSharedState: createXDMSharedState(data:event:))
    }

    /// Handles remove identity requests to remove customer identififers.
    /// - Parameter event: the identity request event
    private func handleRemoveIdentity(event: Event) {
        state?.removeCustomerIdentifiers(event: event, createXDMSharedState: createXDMSharedState(data:event:))
    }

    /// Handles IdentityEdge request reset events.
    /// - Parameter event: the identity request reset event
    private func handleRequestReset(event: Event) {
        state?.resetIdentifiers(event: event,
                                createXDMSharedState: createXDMSharedState(data:event:),
                                dispatchEvent: dispatch(event:))
    }

    /// Handler for `EventType.hub` `EventSource.sharedState` events.
    /// If the state change event is for the Identity Direct extension, get the Identity Direct shared state, extract the ECID, and update the legacy ECID property.
    /// - Parameter event: shared state change event
    private func handleHubSharedState(event: Event) {
        guard let state = state else { return }

        guard let eventData = event.data,
              let stateowner = eventData[IdentityEdgeConstants.EventDataKeys.STATE_OWNER] as? String,
              stateowner == IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT else {
            return
        }

        guard let identitySharedState = getSharedState(extensionName: IdentityEdgeConstants.SharedStateKeys.IDENTITY_DIRECT, event: event)?.value else {
            return
        }

        // Get ECID. If doesn't exist then use empty string to clear legacy value
        let legacyEcid = identitySharedState[IdentityEdgeConstants.EventDataKeys.VISITOR_ID_ECID] as? String ?? ""

        if state.updateLegacyExperienceCloudId(legacyEcid) {
            createXDMSharedState(data: state.identityEdgeProperties.toXdmData(), event: event)
        }
    }
}
