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

enum IdentityEdgeConstants {
    static let EXTENSION_NAME = "com.adobe.identityedge"
    static let FRIENDLY_NAME = "IdentityEdge"
    static let EXTENSION_VERSION = "1.0.0-alpha.1"
    static let DATASTORE_NAME = EXTENSION_NAME

    enum Default {
        static let PRIVACY_STATUS = PrivacyStatus.unknown
        static let ZERO_ADVERTISING_ID = "00000000-0000-0000-0000-000000000000"
    }

    enum SharedStateKeys {
        static let CONFIGURATION = "com.adobe.module.configuration"
    }

    enum Configuration {
        static let GLOBAL_CONFIG_PRIVACY = "global.privacy"
    }

    enum EventNames {
        static let REQUEST_IDENTITY_ECID = "Identity Request ECID"
        static let REQUEST_IDENTITIES = "Identity Request Identities"
        static let IDENTITY_RESPONSE_CONTENT_ONE_TIME = "IDENTITY_RESPONSE_CONTENT_ONE_TIME"
        static let CONSENT_REQUEST_AD_ID = "Consent Request for Ad ID"
    }

    enum EventDataKeys {
        static let VISITOR_ID_ECID = "mid"
        static let ADVERTISING_IDENTIFIER = "advertisingidentifier"
    }

    enum DataStoreKeys {
        static let IDENTITY_PROPERTIES = "identity.properties"
    }

    enum Namespaces {
        static let ECID = "ECID"
        static let IDFA = "IDFA"
    }

    enum AuthenticationStates {
        static let AMBIGUOUS = "ambiguous"
        static let AUTHENTICATED = "authenticated"
        static let LOGGED_OUT = "loggedOut"
    }

    enum XDMKeys {
        static let IDENTITY_MAP = "identityMap"

        enum Consent {
            static let CONSENTS = "consents"
            static let AD_ID = "adId"
            static let VAL = "val"
            static let YES = "y"
            static let NO = "n"
        }
    }

}
