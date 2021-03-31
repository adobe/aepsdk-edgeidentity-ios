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

enum IdentityConstants {
    static let EXTENSION_NAME = "com.adobe.edge.identity"
    static let FRIENDLY_NAME = "Edge Identity"
    static let EXTENSION_VERSION = "1.0.0"
    static let DATASTORE_NAME = EXTENSION_NAME
    static let LOG_TAG = FRIENDLY_NAME

    enum Default {
        static let ZERO_ADVERTISING_ID = "00000000-0000-0000-0000-000000000000"
    }

    enum SharedStateKeys {
        static let CONFIGURATION = "com.adobe.module.configuration"
        static let IDENTITY_DIRECT = "com.adobe.module.identity"
    }

    enum EventNames {
        static let REQUEST_IDENTITY_ECID = "Edge Identity Request ECID"
        static let REQUEST_IDENTITIES = "Edge Identity Request Identities"
        static let UPDATE_IDENTITIES = "Edge Identity Update Identities"
        static let REMOVE_IDENTITIES = "Edge Identity Remove Identities"
        static let IDENTITY_RESPONSE_CONTENT_ONE_TIME = "Edge Identity Response Content One Time"
        static let CONSENT_REQUEST_AD_ID = "Consent Request for Ad ID"
        static let RESET_IDENTITIES_COMPLETE = "Edge Identity Reset Identities Complete"
    }

    enum EventDataKeys {
        static let VISITOR_ID_ECID = "mid"
        static let STATE_OWNER = "stateowner"
    }

    enum DataStoreKeys {
        static let IDENTITY_PROPERTIES = "identity.properties"
    }

    enum Namespaces {
        static let ECID = "ECID"
        static let IDFA = "IDFA"
        static let GAID = "GAID"
    }

    enum AuthenticatedStates {
        static let AMBIGUOUS = "ambiguous"
        static let AUTHENTICATED = "authenticated"
        static let LOGGED_OUT = "loggedOut"
    }

    enum XDMKeys {
        static let IDENTITY_MAP = "identityMap"

        enum Consent {
            static let CONSENTS = "consents"
            static let VAL = "val"
            static let YES = "y"
            static let NO = "n"
        }
    }

}
