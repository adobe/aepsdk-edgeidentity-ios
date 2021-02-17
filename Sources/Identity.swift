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

@objc(AEPMobileIdentity) public class Identity: NSObject, Extension {

    // MARK: Extension
    public let name = IdentityConstants.EXTENSION_NAME
    public let friendlyName = IdentityConstants.FRIENDLY_NAME
    public static let extensionVersion = IdentityConstants.EXTENSION_VERSION
    public let metadata: [String: String]? = nil
    private(set) var state: IdentityState?

    public let runtime: ExtensionRuntime

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        super.init()
        state = IdentityState(identityProperties: IdentityProperties())
    }

    public func onRegistered() {
        registerListener(type: EventType.identity, source: EventSource.requestIdentity, listener: handleIdentityRequest)
        registerListener(type: EventType.genericIdentity, source: EventSource.requestContent, listener: handleRequestContent)
        registerListener(type: EventType.configuration, source: EventSource.responseContent, listener: handleConfigurationResponse)
    }

    public func onUnregistered() {
    }

    public func readyForEvent(_ event: Event) -> Bool {
        guard canProcessEvents(event: event) else { return false }
        return true
    }

    /// Determines if Identity is ready to handle events, this is determined by if the Identity extension has booted up
    /// - Parameter event: An `Event`
    /// - Returns: True if we can process events, false otherwise
    private func canProcessEvents(event: Event) -> Bool {
        guard let state = state else { return false }
        guard !state.hasBooted else { return true } // we have booted, return true

        guard let configSharedState = getSharedState(extensionName: IdentityConstants.SharedStateKeys.CONFIGURATION, event: event)?.value else { return false }
        // attempt to bootup
        if state.bootupIfReady(configSharedState: configSharedState, event: event) {
            createSharedState(data: state.identityProperties.toEventData(), event: nil)
            createXDMSharedState(data: state.identityProperties.toXdmData(), event: nil)
        }

        return false // cannot handle any events until we have booted

    }

    // MARK: Event Listeners

    /// Handles events to set the advertising identifier. Called by listener registered with event hub.
    /// - Parameter event: event containing `advertisingIdentifier` data
    private func handleRequestContent(event: Event) {
        state?.updateAdvertisingIdentifier(event: event,
                                           createSharedState: createSharedState(data:event:),
                                           createXDMSharedState: createXDMSharedState(data:event:),
                                           dispatchEvent: dispatch(event:))
    }

    /// Handles events requesting for identifiers. Called by listener registered with event hub.
    /// - Parameter event: the identity request event
    private func handleIdentityRequest(event: Event) {
        processIdentifiersRequest(event: event)
    }

    /// Handles events requesting identifiers. Dispatches response event containing the identifiers.
    /// - Parameter event: the identity request event
    private func processIdentifiersRequest(event: Event) {
        let xdmData = state?.identityProperties.toXdmData(true)
        let responseEvent = event.createResponseEvent(name: IdentityConstants.EventNames.IDENTITY_RESPONSE_CONTENT_ONE_TIME,
                                                      type: EventType.identity,
                                                      source: EventSource.responseIdentity,
                                                      data: xdmData)

        // dispatch identity response event with shared state data
        dispatch(event: responseEvent)
    }

    /// Handles the configuration response event
    /// - Parameter event: the configuration response event
    private func handleConfigurationResponse(event: Event) {
        if event.data?[IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY] != nil {
            // if config contains new global privacy status, process the request
            state?.processPrivacyChange(event: event,
                                        createSharedState: createSharedState(data:event:),
                                        createXDMSharedState: createXDMSharedState(data:event:))
        }
    }
}
