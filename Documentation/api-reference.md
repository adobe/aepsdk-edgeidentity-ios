# Adobe Experience Platform Identity for Edge Network Extension - iOS

## Prerequisites

Refer our [Getting Started Guide](getting-started.md)

## API reference

| APIs                                           |
| ---------------------------------------------- |
| [extensionVersion](#extensionVersion)          |
| [getExperienceCloudId](#getExperienceCloudId)  |
| [getIdentities](#getIdentities)                |
| [getUrlVariables](#getUrlVariables)            |
| [registerExtension](#registerExtension)        |
| [removeIdentity](#removeIdentity)              |
| [resetIdentities](#resetIdentities)            |
| [updateIdentities](#updateIdentities)          |


### extensionVersion

The extensionVersion() API returns the version of the Identity for Edge Network extension.

<table>
<tr>
<th> Platform </th>
<th> Syntax & Sample </th>
</tr>

<tr>
<td><b>Swift</b></td>
<td>
Syntax: &emsp;<pre>static var extensionVersion: String</pre>
Sample: &emsp;<pre>let extensionVersion = EdgeIdentity.extensionVersion</pre>
</td>
</tr>

<tr>
<td><b>Objective-C</b></td>
<td>
Syntax: &emsp;<pre>+ (nonnull NSString*) extensionVersion; </pre>
Sample: &emsp;<pre> NSString *extensionVersion = [AEPMobileEdgeIdentity extensionVersion];</pre>

</td>
</tr>
</table>

#### Swift
| Label    | Code  |
| -----    | ----- |
| Syntax   | ```swift static var extensionVersion: String``` |
| Sample   | ```swift let extensionVersion = EdgeIdentity.extensionVersion``` |

#### Objective-C
|          |       |
| -----    | ----- |
| Syntax   | ```objectivec + (nonnull NSString*) extensionVersion;`` |
| Sample   | ```objectivec NSString *extensionVersion = [AEPMobileEdgeIdentity extensionVersion];``` |

### getExperienceCloudId

This API retrieves the Experience Cloud ID (ECID) that was generated when the app was initially launched. This ID is preserved between app upgrades, is saved and restored during the standard application backup process, and is removed at uninstall.

**Syntax**

```swift
static func getExperienceCloudId(completion: @escaping (String?, Error?) -> Void)
```

* _completion_ is invoked after the ECID is available.  The default timeout is 1000ms.

**Examples**

```swift
Identity.getExperienceCloudId { (ecid, error) in
  if let error = error {
    // handle error here
  } else {
    // handle the retrieved ID here
  }
}
```

### getIdentities

Get all the identities in the Identity for Edge Network extension, including customer identifiers which were previously added.

**Syntax**

```swift
static func getIdentities(completion: @escaping (IdentityMap?, Error?) -> Void)
```

* _completion_ is invoked after the identities are available.  The default timeout is 1000ms. The return format is an instance of [IdentityMap](#identitymap).

**Examples**

```swift
Identity.getIdentities { (identityMap, error) in
  if let error = error {
    // handle error here
  } else {
    // handle the retrieved identities here
  }
}
```

### getUrlVariables
{% hint style="info" %}
This method was added in Edge Identity version 2.0.0.
{% endhint %}


This API returns the identifiers in URL query parameter format for consumption in **hybrid mobile applications**. There is no leading & or ? punctuation as the caller is responsible for placing the variables in their resulting URL in the correct locations. If an error occurs while retrieving the URL variables, the completion handler is called with a nil value and AEPError instance. Otherwise, the encoded string is returned, for example: `"adobe_mc=TS%3DTIMESTAMP_VALUE%7CMCMID%3DYOUR_ECID%7CMCORGID%3D9YOUR_EXPERIENCE_CLOUD_ID"`

* The `adobe_mc` attribute is an URL encoded list that contains:
  * `MCMID` - Experience Cloud ID \(ECID\)
  * `MCORGID` - Experience Cloud Org ID
  * `TS` - A timestamp taken when this request was made

**Syntax**

```swift
static func getUrlVariables(completion: @escaping (String?, Error?) -> Void)
```
* _completion_ is invoked after the url variables string is available. The default timeout is 1000ms.

**Examples**

```swift
Identity.getUrlVariables { (urlVariables, error) in
  if let error = error {
    // handle error here
  } else {
    // handle the retrieved urlVariables encoded string here
  }
}
```


### registerExtension

Registers the Identity for Edge Network extension with the Mobile Core extension.

{% hint style="info" %}
If your use-case covers both Edge Network and Adobe Experience Cloud Solutions extensions, you need to register Identity for Edge Network and Identity for Experience Cloud Identity Service from Mobile Core extensions. For more details, see the [frequently asked questions](https://aep-sdks.gitbook.io/docs/foundation-extensions/identity-for-edge-network/identity-faq#q-i-am-using-aep-edge-and-adobe-solutions-extensions-which-identity-extension-should-i-install-and-register).
{% endhint %}

The extension registration occurs by passing Identity for Edge Network extension to the [MobileCore.registerExtensions API](https://aep-sdks.gitbook.io/docs/foundation-extensions/mobile-core/mobile-core-api-reference#registerextension-s).

**Syntax**

```swift
static func registerExtensions(_ extensions: [NSObject.Type],
                               _ completion: (() -> Void)? = nil)
```

**Examples**

```swift
import AEPEdgeIdentity

...
MobileCore.registerExtensions([Identity.self])
```

### removeIdentity

Remove the identity from the stored client-side [IdentityMap](#identitymap). The Identity extension will stop sending the identifier to the Edge Network. Using this API does not remove the identifier from the server-side User Profile Graph or Identity Graph.

Identities with an empty _id_ or _namespace_ are not allowed and are ignored.

Removing identities using a reserved namespace is not allowed using this API. The reserved namespaces are:

* ECID
* IDFA
* GAID

**Syntax**

```swift
static func removeIdentity(item: IdentityItem, withNamespace: String)
```

**Examples**

```swift
Identity.removeIdentity(item: IdentityItem(id: "user@example.com"), withNamespace: "Email")
```

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


{% hint style="warning" %}
The Identity for Edge Network extension does not read the Mobile SDK's privacy status, and therefore setting the SDK's privacy status to opt-out will not automatically clear the identities from the Identity for Edge Network extension.
{% endhint %}

See [`MobileCore.resetIdentities`](https://aep-sdks.gitbook.io/docs/foundation-extensions/mobile-core/mobile-core-api-reference#resetidentities) for more details.


### updateIdentities

Update the currently known identities within the SDK. The Identity extension will merge the received identifiers with the previously saved ones in an additive manner, no identities are removed from this API.

Identities with an empty _id_ or _namespace_ are not allowed and are ignored.

Updating identities using a reserved namespace is not allowed using this API. The reserved namespaces are:

* ECID
* IDFA
* GAID

**Syntax**

```swift
static func updateIdentities(with map: IdentityMap)
```

**Examples**

```swift
let identityMap = IdentityMap()
map.addItem(item: IdentityItem(id: "user@example.com"), withNamespace: "Email")
Identity.updateIdentities(with: identityMap)
```

## Public Classes

### IdentityMap

Defines a map containing a set of end user identities, keyed on either namespace integration code or the namespace ID of the identity. The values of the map are an array, meaning that more than one identity of each namespace may be carried.

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

**Example**

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

### IdentityItem

Defines an identity to be included in an [IdentityMap](#identitymap).

The format of the IdentityItem class is defined by the [XDM Identity Item Schema](https://github.com/adobe/xdm/blob/master/docs/reference/datatypes/identityitem.schema.md).

**Example**

```swift
// Initialize
let item = IdentityItem(id: "identifier")

let item = IdentityItem(id: "identifier", authenticatedState: .authenticated, primary: false)

// Getters
let id: String = item.id

let state: AuthenticatedState = item.authenticatedState

let primary: Bool = item.primary
```


### AuthenticatedState

Defines the state an [Identity Item](api-reference.md#identityitem) is authenticated for.

The possible authenticated states are:

* Ambiguous - the state is ambiguous or not defined
* Authenticated - the user is identified by a login or similar action
* LoggedOut - the user was identified by a login action at a previous time, but is not logged in now

**Syntax**

```swift
@objc(AEPAuthenticatedState)
public enum AuthenticatedState: Int, RawRepresentable, Codable {
    case ambiguous = 0
    case authenticated = 1
    case loggedOut = 2
}
```
