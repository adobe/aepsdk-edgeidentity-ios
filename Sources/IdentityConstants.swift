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
    static let EXTENSION_VERSION = "5.2.0"
    static let DATASTORE_NAME = EXTENSION_NAME
    static let LOG_TAG = FRIENDLY_NAME

    enum Default {
        static let ZERO_ADVERTISING_ID = "00000000-0000-0000-0000-000000000000"
    }

    enum SharedState {
        enum Configuration {
            static let SHARED_OWNER_NAME = "com.adobe.module.configuration"
        }

        enum IdentityDirect {
            static let SHARED_OWNER_NAME = "com.adobe.module.identity"
            static let VISITOR_ID_ECID = "mid"
        }

        enum Hub {
            static let SHARED_OWNER_NAME = "com.adobe.module.eventhub"
            static let EXTENSIONS = "extensions"
        }

        enum Consent {
            static let SHARED_OWNER_NAME = "com.adobe.edge.consent"
        }

        enum Messaging {
            static let SHARED_OWNER_NAME = "com.adobe.messaging"
            static let PUSH_IDENTIFIER = "pushidentifier"
            static let LIVE_ACTIVITY = "liveActivity"
            static let PUSH_TO_START_TOKENS = "pushToStartTokens"
            static let TOKEN = "token"
        }
    }

    enum ProfileAttributes {
        // Per-attribute keys (event data, persistence, and XDM payload) are owned by each
        // ProfileAttributeHandler — e.g. TimeZoneAttributeHandler.key = "timeZone".
        // Add a new attribute by creating a new ProfileAttributeHandler conforming type.

        static let STORE_NAME = "com.adobe.mobilecore.profileAttributes"

        // Standard shared state key holding the synced device attributes merged with the profile timezone.
        static let SHARED_STATE_KEY = "profileAttributes"

        enum XDM {
            static let XDM_KEY = "xdm"
            static let DATA_KEY = "data"
            static let EVENT_TYPE_KEY = "eventType"
            static let PROFILE_UPDATE_EVENT_TYPE = "profile.updateAttributes"
        }

    }

    /// Constants for the consent-independent device attribute sync (`updateDeviceAttributesBypassConsent` API).
    enum DeviceAttributes {
        static let RULE_RESPONSE_SOURCE = "com.adobe.eventSource.responseOperationalData"
        static let BYPASS_TYPE = "com.adobe.eventType.edgeBypassConsent"
        static let OPERATIONAL_DATA_TYPE = "com.adobe.eventType.generic.operationalData"
        static let OPTIMIZE_OPERATIONAL_PROFILE_DATA_SYNC = "edgeidentity.optimizeOperationalProfileDataSync"

        static let TIME_ZONE = "timeZone"
        static let TIMEZONE = "timezone"
        static let TOKENS = "tokens"
        static let PUSH_NOTIFICATION = "pushNotification"
        static let APP = "app"
        static let APP_ID = "id"
        static let APP_PLATFORM = "platform"

        static let STATUS = "status"
        static let STATUS_SUCCESS = "success"
        static let STATUS_FAILED = "failed"
        static let REASON = "reason"
        static let REQUEST_EVENT_ID = "requestEventId"
        static let ATTRIBUTES = "attributes"
        static let UNKNOWN_REASON = "unknown"
        static let REASON_UNCHANGED = "unchanged"
        static let REASON_IDENTITY_RESET = "identityReset"
        static let REASON_MISSING_APP_IDENTIFIER = "missingAppIdentifier"

        // iOS only: Live Activity tokens and the Messaging clear Live Activities event.
        static let LIVE_ACTIVITY_START = "liveActivityStart"
        static let ATTRIBUTE_TYPE = "attributeType"
        static let VALUE = "value"
        static let CLEAR_LIVE_ACTIVITIES = "isClearLiveActivitiesEvent"

        // iOS only: the APNs platform is derived from the Messaging `messaging.useSandbox` setting.
        static let MESSAGING_USE_SANDBOX = "messaging.useSandbox"
        static let PLATFORM_APNS = "apns"
        static let PLATFORM_APNS_SANDBOX = "apnsSandbox"
    }

    enum EventNames {
        static let CONSENT_UPDATE_REQUEST_AD_ID = "Consent Update Request for Ad ID"
        static let REQUEST_IDENTITY_ECID = "Edge Identity Request ECID"
        static let REQUEST_IDENTITY_URL_VARIABLES = "Edge Identity Request URL Variables"
        static let REQUEST_IDENTITIES = "Edge Identity Request Identities"
        static let UPDATE_IDENTITIES = "Edge Identity Update Identities"
        static let REMOVE_IDENTITIES = "Edge Identity Remove Identities"
        static let IDENTITY_RESPONSE_URL_VARIABLES = "Edge Identity Response URL Variables"
        static let IDENTITY_RESPONSE_CONTENT_ONE_TIME = "Edge Identity Response Content One Time"
        static let RESET_IDENTITIES_COMPLETE = "Edge Identity Reset Identities Complete"
        static let UPDATE_PROFILE_ATTRIBUTES = "Update Profile Attributes"
        static let UPDATE_DEVICE_ATTRIBUTES = "Update Device Attributes"
        static let DEVICE_ATTRIBUTES_TO_RULES_ENGINE = "Device attributes for rules engine"
        static let DEVICE_ATTRIBUTES_EDGE_REQUEST = "Edge bypass request"
        static let DEVICE_ATTRIBUTES_SYNC_RESULT = "Device Attributes Sync Result"
        static let DEVICE_ATTRIBUTES_CONFIRMED = "Device attributes confirmed"
    }

    enum EventDataKeys {
        static let ADVERTISING_IDENTIFIER = "advertisingidentifier"
        static let STATE_OWNER = "stateowner"
        static let URL_VARIABLES = "urlvariables"
    }

    enum DataStoreKeys {
        static let IDENTITY_PROPERTIES = "identity.properties"
        static let DEVICE_ATTRIBUTES_DATASTORE_NAME = "com.adobe.mobilecore.deviceAttributes"
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
        static let PROFILE_ATTRIBUTES = "com.adobe.mobilecore.profileAttributes"

        enum Consent {
            static let CONSENTS = "consents"
            static let COLLECT = "collect"
            static let ID_TYPE = "idType"
            static let AD_ID = "adID"
            static let VAL = "val"
            static let YES = "y"
            static let NO = "n"
        }
    }

    enum ConfigurationKeys {
        static let EXPERIENCE_CLOUD_ORGID = "experienceCloud.org"
    }

    enum URLKeys {
        static let TIMESTAMP = "TS"
        static let EXPERIENCE_CLOUD_ORG_ID = "MCORGID"
        static let EXPERIENCE_CLOUD_ID = "MCMID"
        static let PAYLOAD = "adobe_mc"
    }

}
