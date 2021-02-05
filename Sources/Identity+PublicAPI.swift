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

/// Defines the public interface for the Identity extension
@objc public extension Identity {

    /// Returns the Experience Cloud ID.
    /// - Parameter completion: closure which will be invoked once Experience Cloud ID is available.
    @objc(getExperienceCloudId:)
    static func getExperienceCloudId(completion: @escaping (String?, Error?) -> Void) {
        let event = Event(name: IdentityConstants.EventNames.IDENTITY_REQUEST_IDENTITY,
                          type: EventType.identity,
                          source: EventSource.requestIdentity,
                          data: nil)

        MobileCore.dispatch(event: event) { responseEvent in
            guard let responseEvent = responseEvent else {
                completion(nil, AEPError.callbackTimeout)
                return
            }

            guard let experienceCloudId = responseEvent.data?[IdentityConstants.EventDataKeys.VISITOR_ID_ECID] as? String else {
                completion(nil, AEPError.unexpected)
                return
            }

            completion(experienceCloudId, .none)
        }
    }
}
