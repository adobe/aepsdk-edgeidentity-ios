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
import AEPAssurance
import AEPCore
import AEPEdgeIdentity
import AEPIdentity
import SwiftUI
import AdSupport
import AppTrackingTransparency
import AEPEdgeConsent



class RegisteredExtensions: ObservableObject {
    @Published var isEdgeIdentityRegistered: Bool = true
    @Published var isIdentityDirectRegistered: Bool = false
}

struct ContentView: View {
    @StateObject var registeredExtensions = RegisteredExtensions()

    var body: some View {

        NavigationView {
            VStack(alignment: .center, spacing: 20, content: {

                NavigationLink(
                    destination: AssuranceView(),
                    label: {
                        Text("Assurance")
                    }
                )

                NavigationLink(
                    destination: AdvertisingIdentifierView(),
                    label: {
                        Text("Set Advertising Identifier")
                    })

                NavigationLink(
                    destination: CustomIdentifierView(),
                    label: {
                        Text("Update Custom Identity")
                    })

                NavigationLink(
                    destination: MultipleIdentityView(extensions: registeredExtensions),
                    label: {
                        Text("Test with Multiple Identities")
                    })
            })
        }

        Divider()
        GetIdentitiesView()

    }
}

struct GetIdentitiesView: View {
    @State var ecidEdgeIdentityText: String = ""
    @State var ecidIdentityText: String = ""
    @State var identityMapText: String = ""

    var body: some View {
        VStack {
            Button(action: {
                self.ecidEdgeIdentityText = ""
                self.ecidIdentityText = ""

                AEPEdgeIdentity.Identity.getExperienceCloudId { ecid, _ in
                    self.ecidEdgeIdentityText = ecid ?? "no ECID value found"
                }

                AEPIdentity.Identity.getExperienceCloudId { ecid, _ in
                    self.ecidIdentityText = ecid ?? ""
                }
            }) {
                Text("Get ECID")
            }

            Text("edge : \(ecidEdgeIdentityText)" + (ecidIdentityText.isEmpty ? "" : "\ndirect: \(ecidIdentityText)"))
                .font(.system(size: 12))
                .padding()

            HStack {
                Button(action: {
                    self.identityMapText = ""
                    AEPEdgeIdentity.Identity.getIdentities { identityMap, _ in
                        if let identityMap = identityMap {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            guard let data = try? encoder.encode(identityMap) else {
                                self.identityMapText = "failed to encode IdentityMap"
                                return
                            }
                            self.identityMapText = String(data: data, encoding: .utf8) ?? "failed to encode JSON to string"
                        } else {
                            self.identityMapText = "IdentityMap was nil"
                        }
                    }
                }) {
                    Text("Get Identities")
                }.padding()

                Button(action: {
                    MobileCore.resetIdentities()
                }) {
                    Text("Reset Identities")
                }.padding()
            }
            ScrollView {
                Text(identityMapText)
                    .font(.system(size: 12))
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineWidth: 1))
            }
        }

    }
}

struct AdvertisingIdentifierView: View {
    @State var adIdText: String = ""
    @State var adID: UUID? = nil
    @State var resultText: String = ""
    
    /// Updates user consent preference by calling Edge Consent extension
    func updateConsent(consentGiven: Bool) {
        let collectConsent = ["collect": ["val": consentGiven ? "y" : "n"]]
        let currentConsents = ["consents": collectConsent]
        Consent.update(with: currentConsents)
    }
    
    /// Provides the advertisingIdentifier for the given environment, assuming tracking authorization is provided
    ///
    /// Simulators will never provide a valid UUID, regardless of authorization; in the case of successful authorization on simulator, a random placeholder UUID will be generated
    func getAdvertisingIdentifierForEnvironment() -> UUID {
        #if targetEnvironment(simulator)
        print("Simulator environment detected")
        print("Simulator cannot retrieve valid advertising identifier; random UUID value generated as example value instead.")
        return UUID()
        #else
        print("Non-simulator environment detected")
        print(ASIdentifierManager.shared().advertisingIdentifier)
        return ASIdentifierManager.shared().advertisingIdentifier
        #endif
    }
    
    /// Requests tracking authorization from the user; prompt will only be shown once per app install, as per Apple rules
    ///
    /// It is possible to change tracking permissions at the Settings app level. Change in permissions will terminate the app
    /// It is also possible for system-wide tracking to be off but individual permissions granted
    /// If Allow Apps to Request to Track was on and is turned off, a system prompt appears asking if previously provided individual tracking permissions should be kept or all turned off
    func requestTrackingAuthorization() {
        /// Based on Apple documentation for `ASIdentifierManager.shared().advertisingIdentifier`, iOS 14.5+ is the cutoff for required permissions request to use IDFA
        /// however, based on testing with iOS 14.0.1 simulator, `isAdvertisingTrackingEnabled` is false on fresh app install, even if device has device level tracking enabled; prompt is never given and app does not show up in Privacy -> Tracking app list
        // Requires Xcode 12 and AppTrackingTransparency framework
        if #available(iOS 14, *) {
            print("Using requestTrackingAuthorization")
            // TODO: should Core be notified in every case?
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                // Tracking authorization dialog was shown and authorization given
                case .authorized:
                    print("Authorized")
                    resultText = "Authorized"
                    // IDFA now accessible
                    self.adID = getAdvertisingIdentifierForEnvironment()
                    // Update consent
                    updateConsent(consentGiven: true)
                    // Set IDFA in Core
                    MobileCore.setAdvertisingIdentifier(self.adID?.uuidString)
                    
                // Tracking authorization dialog was shown and permission is denied
                case .denied:
                    print("Denied")
                    resultText = "Denied"
                    
                    updateConsent(consentGiven: false)
                    MobileCore.setAdvertisingIdentifier("")
                // Tracking authorization dialog has not been shown
                case .notDetermined:
                    print("Not Determined")
                    resultText = "Not Determined"
                // Tracking authorization dialog is not allowed to be shown
                case .restricted:
                    print("Restricted")
                    resultText = "Restricted"
                @unknown default:
                    print("Unknown")
                    resultText = "Unknown"
                }
            }
        } else {
            // ATTrackingManager only available in iOS 14+
            print("ASIdentifierManager.shared().isAdvertisingTrackingEnabled: \(ASIdentifierManager.shared().isAdvertisingTrackingEnabled)")
            print("Advertising identifier: \(ASIdentifierManager.shared().advertisingIdentifier)")
            print("Getting IDFA directly")
            if ASIdentifierManager.shared().isAdvertisingTrackingEnabled {
                self.adID = getAdvertisingIdentifierForEnvironment()
                resultText = "Tracking enabled"
                
                updateConsent(consentGiven: true)
                MobileCore.setAdvertisingIdentifier(self.adID?.uuidString)
                
            } else {
                resultText = "Tracking disabled"
                
                updateConsent(consentGiven: false)
                MobileCore.setAdvertisingIdentifier("")
            }
        }
    }

    var body: some View {
        VStack {
            VStack {
                Button("Request Permission for IDFA", action: {
                    requestTrackingAuthorization()
                })
                Text(resultText)
                Text("\(adID?.uuidString ?? "")")
            }
            
            HStack {
                Button(action: {
                    MobileCore.setAdvertisingIdentifier(adIdText)
                }) {
                    Text("Set AdId")
                }.padding()
                TextField("Enter Ad ID", text: $adIdText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .fixedSize()
                    .autocapitalization(.none)
            }
            HStack {
                Button(action: {
                    MobileCore.setAdvertisingIdentifier(nil)
                }) {
                    Text("Set AdId as nil")
                }.padding()
                Button(action: {
                    MobileCore.setAdvertisingIdentifier("00000000-0000-0000-0000-000000000000")
                }) {
                    Text("Set AdId as zeros")
                }.padding()
            }
        }
    }
}

struct CustomIdentifierView: View {
    @State var identityItemText: String = ""
    @State var identityNamespaceText: String = ""
    @State var selectedAuthenticatedState: AuthenticatedState = .ambiguous
    @State var isPrimaryChecked: Bool = false

    var body: some View {
        VStack {
            VStack {
                TextField("Enter Identifier", text: $identityItemText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .fixedSize()
                    .autocapitalization(.none)

                HStack {
                    TextField("namespace", text: $identityNamespaceText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .fixedSize()
                        .autocapitalization(.none)

                    HStack {
                        Image(systemName: isPrimaryChecked ? "checkmark.square" : "square")
                            .onTapGesture {
                                isPrimaryChecked.toggle()
                            }
                        Text("primary")
                    }
                }
            }
            HStack {
                Picker("AuthenticatedState", selection: $selectedAuthenticatedState) {
                    Text("ambiguous").tag(AuthenticatedState.ambiguous)
                    Text("authenticated").tag(AuthenticatedState.authenticated)
                    Text("logged out").tag(AuthenticatedState.loggedOut)
                }.pickerStyle(SegmentedPickerStyle())
            }
            HStack {
                Button(action: {
                    let map = IdentityMap()
                    map.add(item: IdentityItem(id: identityItemText, authenticatedState: selectedAuthenticatedState, primary: isPrimaryChecked),
                            withNamespace: identityNamespaceText)
                    AEPEdgeIdentity.Identity.updateIdentities(with: map)
                }) {
                    Text("Update Identity")
                }.padding()
                Button(action: {
                    AEPEdgeIdentity.Identity.removeIdentity(item: IdentityItem(id: identityItemText, authenticatedState: selectedAuthenticatedState, primary: isPrimaryChecked),
                                                            withNamespace: identityNamespaceText)
                }) {
                    Text("Remove Identity")
                }.padding()
            }

        }
    }
}

struct MultipleIdentityView: View {
    private let edgeIdentityStoredDataKey = "Adobe.com.adobe.edge.identity.identity.properties"
    private let identityStoredDataKey = "Adobe.com.adobe.module.identity.identity.properties"

    @ObservedObject var extensions: RegisteredExtensions
    @State var ecidEdgeIdentityText: String = ""
    @State var ecidIdentityText: String = ""
    @State var identityMapText: String = ""

    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Image(systemName: extensions.isEdgeIdentityRegistered ? "circle.fill" : "circle")
                    .foregroundColor(Color.blue)

                Button(action: {
                    if extensions.isEdgeIdentityRegistered {
                        MobileCore.unregisterExtension(AEPEdgeIdentity.Identity.self)
                    } else {
                        MobileCore.registerExtension(AEPEdgeIdentity.Identity.self)
                    }

                    extensions.isEdgeIdentityRegistered.toggle()

                }) {
                    Text(extensions.isEdgeIdentityRegistered ? "Unregister Edge Identity" : "Register Edge Identity")
                }
            }.padding(.bottom, 5)

            Button(action: {
                UserDefaults.standard.removeObject(forKey: edgeIdentityStoredDataKey)
            }) {
                Text("Clear Persistence")
            }
        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineWidth: 1))

        VStack {
            HStack {
                Image(systemName: extensions.isIdentityDirectRegistered ? "circle.fill" : "circle")
                    .foregroundColor(Color.blue)

                Button(action: {
                    if extensions.isIdentityDirectRegistered {
                        MobileCore.unregisterExtension(AEPIdentity.Identity.self)
                    } else {
                        MobileCore.registerExtension(AEPIdentity.Identity.self)
                    }

                    extensions.isIdentityDirectRegistered.toggle()

                }) {
                    Text(extensions.isIdentityDirectRegistered ? "Unregister Identity Direct" : "Register Identity Direct")
                }
            }.padding(.bottom, 5)

            Button(action: {
                MobileCore.setAdvertisingIdentifier(String(Int.random(in: 1...32)))
            }) {
                Text("Trigger State Change")
            }.padding(.bottom, 5)

            Button(action: {
                UserDefaults.standard.removeObject(forKey: identityStoredDataKey)
            }) {
                Text("Clear Persistence")
            }.padding(.bottom, 5)

            HStack {
                Button(action: {
                    MobileCore.setPrivacyStatus(.optedIn)
                }) {
                    Text("Privacy OptIn")
                }
                Button(action: {
                    MobileCore.setPrivacyStatus(.optedOut)
                }) {
                    Text("Privacy OptOut")
                }
            }

        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineWidth: 1))
    }
}

struct AssuranceView: View {
    @State private var assuranceSessionUrl: String = ""

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            TextField("Copy Assurance Session URL to here", text: $assuranceSessionUrl)
            HStack {
                Button(action: {
                    // step-assurance-start
                    // replace the url with the valid one generated on Assurance UI
                    if let url = URL(string: self.assuranceSessionUrl) {
                        Assurance.startSession(url: url)
                    }
                    // step-assurance-end
                }) {
                    Text("Connect")
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .font(.caption)
                }.cornerRadius(5)
            }
        }.padding().onAppear {
            MobileCore.track(state: "AssuranceView", data: nil)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
