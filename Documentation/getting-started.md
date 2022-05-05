## Getting started

The Adobe Experience Platform Identity for Edge Network extension has the following peer dependency, which must be installed prior to installing the identity extension:
- [Core](https://github.com/adobe/aepsdk-core-ios#readme)

## Add the AEP Identity extension to your app

### Download and import the Identity extension

{% hint style="info" %}
The following instructions are for configuring an application using Adobe Experience Platform Edge mobile extensions. If an application will include both Edge Network and Adobe Solution extensions, both the Identity for Edge Network and Identity for Experience Cloud ID Service extensions are required. Find more details in the [Frequently Asked Questions](https://aep-sdks.gitbook.io/docs/foundation-extensions/identity-for-edge-network/identity-faq) page.


1. Add the Mobile Core and Edge extensions to your project using CocoaPods. Add following pods in your `Podfile`:

  ```ruby
  use_frameworks!
  target 'YourTargetApp' do
     pod 'AEPCore'
     pod 'AEPEdge'
     pod 'AEPEdgeIdentity'
  end
  ```

2. Install cocoapods dependencies. Replace `YOUR_TARGET_NAME` and then, in the `Podfile` directory, type:

  ```bash
  $ pod install
  ```

3. Import the Mobile Core and Edge libraries:

  ```swift
  // AppDelegate.swift
  import AEPCore
  import AEPEdge
  import AEPEdgeIdentity
  ```

4. Register the Identity for Edge Extension with MobileCore:
  ```swift
  // AppDelegate.swift
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    MobileCore.registerExtensions([Identity.self, Edge.self], {
       MobileCore.configureWith(appId: "yourLaunchEnvironmentID")
     })
     ...
  }
  ```