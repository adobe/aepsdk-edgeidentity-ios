# Adobe Experience Platform Identity for Edge Network Extension - iOS

## Prerequisites

Refer to the [Getting Started Guide](getting-started.md)

## API reference

| APIs                                                  |
| ----------------------------------------------------- |
| [extensionVersion](#extensionVersion)                 |
| [getExperienceCloudId](#getExperienceCloudId)         |
| [getIdentities](#getIdentities)                       |
| [getUrlVariables](#getUrlVariables)                   |
| [registerExtension](#registerExtension)               |
| [removeIdentity](#removeIdentity)                     |
| [resetIdentities](#resetIdentities)                   |
| [setAdvertisingIdentifier](#setAdvertisingIdentifier) |
| [updateIdentities](#updateIdentities)                 |

------

### extensionVersion

The extensionVersion() API returns the version of the Identity for Edge Network extension.

#### Swift

##### Syntax
```swift
static var extensionVersion: String
```

##### Example
```swift
let extensionVersion = EdgeIdentity.extensionVersion
```

#### Objective-C

##### Syntax
```objectivec
+ (nonnull NSString*) extensionVersion;
```

##### Example
```objectivec
NSString *extensionVersion = [AEPMobileEdgeIdentity extensionVersion];
```
------

### getExperienceCloudId

This API retrieves the Experience Cloud ID (ECID) that was generated when the app was initially launched. This ID is preserved between app upgrades, is saved and restored during the standard application backup process, and is removed at uninstall.

#### Swift

##### Syntax
```swift
static func getExperienceCloudId(completion: @escaping (String?, Error?) -> Void)
```

* _completion_ is invoked after the ECID is available.  The default timeout is 1000ms.

##### Example
```swift
Identity.getExperienceCloudId { (ecid, error) in
  if let error = error {
    // handle error here
  } else {
    // handle the retrieved ID here
  }
}
```
#### Objective-C

##### Syntax
```objectivec
+ (void) getExperienceCloudId:^(NSString * _Nullable ecid, NSError * _Nullable error)completion
```

##### Example
```objectivec
[AEPMobileEdgeIdentity getExperienceCloudId:^(NSString *ecid, NSError *error) {   
    // handle the error and the retrieved ID here    
}];
```
------

### getIdentities

Get all the identities in the Identity for Edge Network extension, including customer identifiers which were previously added.

#### Swift

##### Syntax
```swift
static func getIdentities(completion: @escaping (IdentityMap?, Error?) -> Void)
```
* _completion_ is invoked after the identities are available. The default timeout is 1000ms. The return format is an instance of [IdentityMap](#identitymap).

##### Example
```swift
Identity.getIdentities { (identityMap, error) in
  if let error = error {
    // handle error here
  } else {
    // handle the retrieved identities here
  }
}
```

#### Objective-C

##### Syntax
```objectivec
+ (void) getIdentities:^(AEPIdentityMap * _Nullable map, NSError * _Nullable error)completion
```

##### Example
```objectivec
[AEPMobileEdgeIdentity getIdentities:^(AEPIdentityMap *map, NSError *error) {   
    // handle the error and the retrieved  identities here
}];
```

------

### getUrlVariables
> **Note**
> This method was added in Edge Identity version 1.1.0.

This API returns the identifiers in URL query parameter format for consumption in **hybrid mobile applications**. There is no leading & or ? punctuation as the caller is responsible for placing the variables in their resulting URL in the correct locations. If an error occurs while retrieving the URL variables, the completion handler is called with a nil value and AEPError instance. Otherwise, the encoded string is returned, for example: `"adobe_mc=TS%3DTIMESTAMP_VALUE%7CMCMID%3DYOUR_ECID%7CMCORGID%3D9YOUR_EXPERIENCE_CLOUD_ID"`

* The `adobe_mc` attribute is an URL encoded list that contains:
  * `MCMID` - Experience Cloud ID \(ECID\)
  * `MCORGID` - Experience Cloud Org ID
  * `TS` - A timestamp taken when this request was made

#### Swift

##### Syntax
```swift
static func getUrlVariables(completion: @escaping (String?, Error?) -> Void)
```
* _completion_ is invoked with _urlVariables_ containing the visitor identifiers as a query string, or _error_ if an unexpected error occurs or the request times out. The returned `Error` contains the [AEPError](https://aep-sdks.gitbook.io/docs/foundation-extensions/mobile-core/mobile-core-api-reference#aeperror) code of the specific error. The default timeout is 1000ms.

##### Example
```swift
Identity.getUrlVariables { (urlVariables, error) in
  if let error = error {
    // handle error here
  } else {
    var urlStringWithVisitorData: String = "https://example.com"
    if let urlVariables: String = urlVariables {
      urlStringWithVisitorData.append("?" + urlVariables)
    }

    guard let urlWithVisitorData: URL = URL(string: urlStringWithVisitorData) else {
      // handle error, unable to construct URL
      return
    }

    // handle the retrieved urlVariables encoded string here
    // APIs which update the UI must be called from main thread
    DispatchQueue.main.async {
    self.webView.load(URLRequest(url: urlWithVisitorData))
    }
  }
}
```

#### Objective-C

##### Syntax
```objectivec
+ (void) getUrlVariables:^(NSString * _Nullable urlVariables, NSError * _Nullable error)completion
```

##### Example
```objectivec
[AEPMobileEdgeIdentity getUrlVariables:^(NSString *urlVariables, NSError *error){
  if (error) {
  // handle error here
  } else {
    // handle the URL query parameter string here
    NSString* urlString = @"https://example.com";
    NSString* urlStringWithVisitorData = [NSString stringWithFormat:@"%@?%@", urlString, urlVariables];
    NSURL* urlWithVisitorData = [NSURL URLWithString:urlStringWithVisitorData];

    // APIs which update the UI must be called from main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      [[self webView] loadRequest:[NSURLRequest requestWithURL:urlWithVisitorData]];
    }
  }
}];
```

------

### registerExtension

Registers the Identity for Edge Network extension with the Mobile Core extension.

> **Note**
> If your use-case covers both Edge Network and Adobe Experience Cloud Solutions extensions, you need to register Identity for Edge Network and Identity for Experience Cloud Identity Service from Mobile Core extensions. For more details, see the [frequently asked questions](https://aep-sdks.gitbook.io/docs/foundation-extensions/identity-for-edge-network/identity-faq#q-i-am-using-aep-edge-and-adobe-solutions-extensions-which-identity-extension-should-i-install-and-register).

The extension registration occurs by passing Identity for Edge Network extension to the [MobileCore.registerExtensions API](https://aep-sdks.gitbook.io/docs/foundation-extensions/mobile-core/mobile-core-api-reference#registerextension-s).

#### Swift

##### Syntax
```swift
static func registerExtensions(_ extensions: [NSObject.Type],
                               _ completion: (() -> Void)? = nil)
```

##### Example
```swift
import AEPEdgeIdentity

...
MobileCore.registerExtensions([Identity.self])

##### Syntax
```objectivec
+ (void) registerExtensions: (NSArray<Class*>* _Nonnull) extensions
                 completion: (void (^ _Nullable)(void)) completion;

##### Example
```objectivec
@import AEPEdgeIdentity;

...
[AEPMobileCore registerExtensions:@[AEPMobileEdgeIdentity.class] completion:nil];
```

------

### removeIdentity

Remove the identity from the stored client-side [IdentityMap](#identitymap). The Identity extension will stop sending the identifier to the Edge Network. Using this API does not remove the identifier from the server-side User Profile Graph or Identity Graph.

Identities with an empty _id_ or _namespace_ are not allowed and are ignored.

Removing identities using a reserved namespace is not allowed using this API. The reserved namespaces are:

* ECID
* IDFA
* GAID

#### Swift

##### Syntax
```swift
Identity.removeIdentity(item: IdentityItem(id: "user@example.com"), withNamespace: "Email")
```

##### Example
```swift
static func removeIdentity(item: IdentityItem, withNamespace: String)
```

#### Objective-C


##### Syntax
```objectivec
+ (void) removeIdentityItem:(AEPIdentityItem * _Nonnull) item
                             withNamespace: (NSString * _Nonnull) namespace
```

##### Example
```objectivec
AEPIdentityItem *item = [[AEPIdentityItem alloc] initWithId:@"user@example.com" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];
[AEPMobileEdgeIdentity removeIdentityItem:item withNamespace:@"Email"];
```

------

### resetIdentities

Clears all identities stored in the Identity extension and generates a new Experience Cloud ID (ECID). Using this API does not remove the identifiers from the server-side User Profile Graph or Identity Graph.

This is a destructive action, since once an ECID is removed it cannot be reused. The new ECID generated by this API can increase metrics like unique visitors when a new user profile is created.

Some example use cases for this API are:
* During debugging, to see how new ECIDs (and other identifiers paired with it) behave with existing rules and metrics.
* A last-resort reset for when an ECID should no longer be used.

This API is not recommended for:
* Resetting a user's consent and privacy settings; see [Privacy and GDPR](https://aep-sdks.gitbook.io/docs/resources/privacy-and-gdpr).
* Removing existing custom identifiers; use the [`removeIdentity`](#removeidentity) API instead.
* Removing a previously synced advertising identifier after the advertising tracking settings were changed by the user; use the [`setAdvertisingIdentifier`](https://aep-sdks.gitbook.io/docs/foundation-extensions/mobile-core/identity/identity-api-reference#setadvertisingidentifier) API instead.

> **Warning**
> The Identity for Edge Network extension does not read the Mobile SDK's privacy status, and therefore setting the SDK's privacy status to opt-out will not automatically clear the identities from the Identity for Edge Network extension. See [`MobileCore.resetIdentities`](https://aep-sdks.gitbook.io/docs/foundation-extensions/mobile-core/mobile-core-api-reference#resetidentities) for more details.

------

### setAdvertisingIdentifier

When this API is called with a valid advertising identifier, the Identity for Edge Network extension includes the advertising identifier in the XDM Identity Map using the _IDFA_ namespace. If the API is called with empty, nil or all-zeroes value, the IDFA is removed from the XDM Identity Map (if previously set).

The IDFA is preserved between app upgrades, is saved and restored during the standard application backup process, and is removed at uninstall.

> **Warning**
> In order to enable the collection of current advertising tracking user's selection based on the provided advertising identifier, you need to install and register the [AEPEdgeConsent](https://aep-sdks.gitbook.io/docs/foundation-extensions/consent-for-edge-network) extension and update the [AEPEdge](https://aep-sdks.gitbook.io/docs/foundation-extensions/experience-platform-extension) dependency to minimum 1.4.1.

> **Warning**
> Starting iOS 14+, applications must use the [App Tracking Transparency](https://developer.apple.com/documentation/apptrackingtransparency) framework to request user authorization before using the Identifier for Advertising (IDFA). To access IDFA and handle it correctly in your mobile application, see the [Apple developer documentation about IDFA](https://developer.apple.com/documentation/adsupport/asidentifiermanager).

#### Swift

##### Syntax
```swift
@objc(setAdvertisingIdentifier:)
public static func setAdvertisingIdentifier(_ identifier: String?)
```
- _identifier_ is a string that provides developers with a simple, standard system to continue to track the Ads through their apps.
##### Example
```swift
import AdSupport
import AppTrackingTransparency
...

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    ...
    if #available(iOS 14, *) {
       setAdvertisingIdentifierUsingTrackingManager()
    } else {
       // Fallback on earlier versions
       setAdvertisingIdentifierUsingIdentifierManager()
    }

}

func setAdvertisingIdentifierUsingIdentifierManager() {
    var idfa:String = "";
        if (ASIdentifierManager.shared().isAdvertisingTrackingEnabled) {
            idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString;
        } else {
            Log.debug(label: "AppDelegateExample",
                      "Advertising Tracking is disabled by the user, cannot process the advertising identifier.");
        }
        MobileCore.setAdvertisingIdentifier(idfa);
}

@available(iOS 14, *)
func setAdvertisingIdentifierUsingTrackingManager() {
    ATTrackingManager.requestTrackingAuthorization { (status) in
        var idfa: String = "";

        switch (status) {
        case .authorized:
            idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        case .denied:
            Log.debug(label: "AppDelegateExample",
                      "Advertising Tracking is denied by the user, cannot process the advertising identifier.")
        case .notDetermined:
            Log.debug(label: "AppDelegateExample",
                      "Advertising Tracking is not determined, cannot process the advertising identifier.")
        case .restricted:
            Log.debug(label: "AppDelegateExample",
                      "Advertising Tracking is restricted by the user, cannot process the advertising identifier.")
        }

        MobileCore.setAdvertisingIdentifier(idfa)
    }
}
```

#### Objective-C

##### Syntax
```objectivec
+ (void) setAdvertisingIdentifier: (NSString * _Nullable identifier);
```

##### Example
```objectivec
#import <AdSupport/ASIdentifierManager.h>
#import <AppTrackingTransparency/ATTrackingManager.h>
...

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
-   ...
-   
    if (@available(iOS 14, *)) {
        [self setAdvertisingIdentifierUsingTrackingManager];
    } else {
        // fallback to earlier versions
        [self setAdvertisingIdentifierUsingIdentifierManager];
    }

}

- (void) setAdvertisingIdentifierUsingIdentifierManager {
    // setup the advertising identifier
    NSString *idfa = nil;
    if ([[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        idfa = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    } else {
        [AEPLog debugWithLabel:@"AppDelegateExample"
                       message:@"Advertising Tracking is disabled by the user, cannot process the advertising identifier"];
    }
    [AEPMobileCore setAdvertisingIdentifier:idfa];

}

- (void) setAdvertisingIdentifierUsingTrackingManager API_AVAILABLE(ios(14)) {
    [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:
    ^(ATTrackingManagerAuthorizationStatus status){
        NSString *idfa = nil;
        switch(status) {
            case ATTrackingManagerAuthorizationStatusAuthorized:
                idfa = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
                break;
            case ATTrackingManagerAuthorizationStatusDenied:
                [AEPLog debugWithLabel:@"AppDelegateExample"
                               message:@"Advertising Tracking is denied by the user, cannot process the advertising identifier"];
                break;
            case ATTrackingManagerAuthorizationStatusNotDetermined:
                [AEPLog debugWithLabel:@"AppDelegateExample"
                               message:@"Advertising Tracking is not determined, cannot process the advertising identifier"];
                break;
            case ATTrackingManagerAuthorizationStatusRestricted:
                [AEPLog debugWithLabel:@"AppDelegateExample"
                               message:@"Advertising Tracking is restricted by the user, cannot process the advertising identifier"];
                break;
        }

        [AEPMobileCore setAdvertisingIdentifier:idfa];
    }];
}
```
------

### updateIdentities

Update the currently known identities within the SDK. The Identity extension will merge the received identifiers with the previously saved ones in an additive manner, no identities are removed from this API.

Identities with an empty _id_ or _namespace_ are not allowed and are ignored.

Updating identities using a reserved namespace is not allowed using this API. The reserved namespaces are:

* ECID
* IDFA
* GAID

#### Swift

##### Syntax
```swift
static func updateIdentities(with map: IdentityMap)
```

##### Example
```swift
let identityMap = IdentityMap()
map.addItem(item: IdentityItem(id: "user@example.com"), withNamespace: "Email")
Identity.updateIdentities(with: identityMap)
```

#### Objective-C

##### Syntax
```objectivec
+ (void) updateIdentities:(AEPIdentityMap * _Nonnull)map
```

##### Example
```objectivec
AEPIdentityItem *item = [[AEPIdentityItem alloc] initWithId:@"user@example.com" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];
AEPIdentityMap *map = [[AEPIdentityMap alloc] init];
[map addItem:item withNamespace:@"Email"];
[AEPMobileEdgeIdentity updateIdentities:map];
```

------

## Public Classes

### IdentityMap

Defines a map containing a set of end user identities, keyed on either namespace integration code or the namespace ID of the identity. The values of the map are an array of [IdentityItem](#identityitem)s, meaning that more than one identity of each namespace may be carried. Each IdentityItem should have a valid, non-null and non-empty identifier, otherwise it will be ignored.

The format of the IdentityMap class is defined by the [XDM Identity Map Schema](https://github.com/adobe/xdm/blob/master/docs/reference/mixins/shared/identitymap.schema.md).

For more information, please read an overview of the [AEP Identity Service](https://experienceleague.adobe.com/docs/experience-platform/identity/home.html).

```text
"identityMap" : {
    "Email" : [
      {
        "id" : "user@example.com",
        "authenticatedState" : "authenticated",
        "primary" : false
      }
    ],
    "Phone" : [
      {
        "id" : "1234567890",
        "authenticatedState" : "ambiguous",
        "primary" : false
      },
      {
        "id" : "5557891234",
        "authenticatedState" : "ambiguous",
        "primary" : false
      }
    ],
    "ECID" : [
      {
        "id" : "44809014977647551167356491107014304096",
        "authenticatedState" : "ambiguous",
        "primary" : true
      }
    ]
  }
```

#### Swift

##### Example
```swift
// Initialize
let identityMap: IdentityMap = IdentityMap()

// Add an item
identityMap.add(item: IdentityItem(id: "user@example.com"), withNamespace: "Email")

// Remove an item
identityMap.remove(item: IdentityItem(id: "user@example.com", withNamespace: "Email"))

// Get a list of items for a given namespace
let items: [IdentityItem] = identityMap.getItems(withNamespace: "Email")

// Get a list of all namespaces used in current IdentityMap
let namespaces: [String] = identityMap.namespaces

// Check if IdentityMap has no identities
let hasNoIdentities: Bool = identityMap.isEmpty
```

#### Objective-C

##### Example
```objectivec
// Initialize
AEPIdentityMap* identityMap = [[AEPIdentityMap alloc] init];

// Add an item
AEPIdentityItem* item = [[AEPIdentityItem alloc] initWithId:@"user@example.com" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];
[identityMap addItem:item withNamespace:@"Email"];

// Remove an item
AEPIdentityItem* item = [[AEPIdentityItem alloc] initWithId:@"user@example.com" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];
[identityMap removeItem:item withNamespace:@"Email"];

// Get a list of items for a given namespace
NSArray<AEPIdentityItem*>* items = [identityMap getItemsWithNamespace:@"Email"];

// Get a list of all namespaces used in current IdentityMap
NSArray<NSString*>* namespaces = identityMap.namespaces;

// Check if IdentityMap has no identities
bool hasNoIdentities = identityMap.isEmpty;
```

------

### IdentityItem

Defines an identity to be included in an [IdentityMap](#identitymap). IdentityItems may not have null or empty identifiers and are ignored when adding to an [IdentityMap](#identitymap) instance.

The format of the IdentityItem class is defined by the [XDM Identity Item Schema](https://github.com/adobe/xdm/blob/master/docs/reference/datatypes/identityitem.schema.md).

#### Swift

##### Example
```swift
// Initialize
let item = IdentityItem(id: "identifier")

let item = IdentityItem(id: "identifier", authenticatedState: .authenticated, primary: false)

// Getters
let id: String = item.id

let state: AuthenticatedState = item.authenticatedState

let primary: Bool = item.primary
```

#### Objective-C

##### Example
```objectivec
// Initialize
AEPIdentityItem* item = [[AEPIdentityItem alloc] initWithId:@"identity" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];

// Getters
NSString* id = primaryEmail.id;

long state = primaryEmail.authenticatedState;

bool primary = primaryEmail.primary;
```
------

### AuthenticatedState

Defines the state for which an [Identity Item](api-reference.md#identityitem) is authenticated.

The possible authenticated states are:

* Ambiguous - the state is ambiguous or not defined
* Authenticated - the user is identified by a login or similar action
* LoggedOut - the user was identified by a login action at a previous time, but is not logged in now

##### Syntax

```swift
@objc(AEPAuthenticatedState)
public enum AuthenticatedState: Int, RawRepresentable, Codable {
    case ambiguous = 0
    case authenticated = 1
    case loggedOut = 2
}
```
