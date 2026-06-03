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
import AdSupport
import AEPCore
import AEPEdgeConsent
import AEPEdgeIdentity
import AEPIdentity
import AppTrackingTransparency
import SwiftUI

#if os(iOS)
import AEPAssurance
#endif

class RegisteredExtensions: ObservableObject {
    @Published var isEdgeIdentityRegistered: Bool = true
    @Published var isIdentityDirectRegistered: Bool = false
}

struct ContentView: View {
    @ObservedObject var registeredExtensions = RegisteredExtensions()

    var body: some View {

        NavigationView {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .center, spacing: 20) {
                    #if os(iOS)
                    NavigationLink(
                        destination: AssuranceView(),
                        label: {
                            Text("Assurance")
                        }
                    )
                    #endif
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
                }
            }
        }
        Divider()
        GetIdentitiesView()
    }
}

struct GetIdentitiesView: View {
    @State var ecidEdgeIdentityText: String = ""
    @State var ecidIdentityText: String = ""
    @State var identityMapText: String = ""
    @State var urlVariablesText: String = ""
    @State var timezoneInput: String = ""
    @State var lastTimezoneStatus: String = ""

    private let presetZones = ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Kolkata", "Pacific/Auckland"]

    private func sendTimezone(_ identifier: String) {
        // TODO: revert once MobileCore.updateProfileAttributes is available in the published AEPCore pod.
        // MobileCore.updateProfileAttributes().setTimezone(TimeZone(identifier: identifier)!)
        lastTimezoneStatus = "Pending (API not yet in pod): \(identifier)"
    }

    var body: some View {
        VStack {
            Button {
                self.ecidEdgeIdentityText = ""
                self.ecidIdentityText = ""

                AEPEdgeIdentity.Identity.getExperienceCloudId { ecid, _ in
                    self.ecidEdgeIdentityText = ecid ?? "no ECID value found"
                }

                AEPIdentity.Identity.getExperienceCloudId { ecid, _ in
                    self.ecidIdentityText = ecid ?? ""
                }
            } label: {
                Text("Get ECID")
            }

            Button {
                self.urlVariablesText = ""

                AEPEdgeIdentity.Identity.getUrlVariables { urlVariablesString, _ in
                    self.urlVariablesText = urlVariablesString ?? "URLVariables not generated"
                }
            } label: {
                Text("Get URLVariables")
            }

            Text("edge : \(ecidEdgeIdentityText)" + (ecidIdentityText.isEmpty ? "" : "\ndirect: \(ecidIdentityText)"))
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
                .padding(5)

            Text("urlString : \(urlVariablesText)")
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
                .padding(5)

            VStack {
                Button {
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
                } label: {
                    Text("Get Identities")
                }
                .padding()

                Button {
                    MobileCore.resetIdentities()
                } label: {
                    Text("Reset Identities")
                }
                .padding()

                Divider().padding(.vertical, 4)

                // MARK: - Timezone
                Text("Profile Attributes — Timezone")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("IANA timezone (e.g. Asia/Kolkata)", text: $timezoneInput)
                        #if os(iOS)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        #endif
                    Button("Send") {
                        sendTimezone(timezoneInput.trimmingCharacters(in: .whitespaces))
                    }
                }
                .padding(.horizontal)

                // Preset zone chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetZones, id: \.self) { zone in
                            Button(zone) {
                                timezoneInput = zone
                                sendTimezone(zone)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    let id = timezoneInput.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, TimeZone(identifier: id) != nil else {
                        lastTimezoneStatus = "Invalid timezone for spam test"
                        return
                    }
                    for _ in 1...5 { sendTimezone(id) }
                    lastTimezoneStatus = "Spammed x5: \(id)"
                } label: {
                    Text("Spam Send (x5)")
                }
                .padding(.top, 4)

                if !lastTimezoneStatus.isEmpty {
                    Text(lastTimezoneStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                Divider().padding(.vertical, 4)

                // MARK: - Consent simulation
                Text("Consent Simulation")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button {
                        let event = Event(name: "Test Consent Response",
                                          type: EventType.edgeConsent,
                                          source: EventSource.responseContent,
                                          data: ["consents": ["collect": ["val": "y"]]])
                        MobileCore.dispatch(event: event)
                    } label: {
                        Text("Consent → Yes")
                    }
                    .padding()

                    Button {
                        let event = Event(name: "Test Consent Response",
                                          type: EventType.edgeConsent,
                                          source: EventSource.responseContent,
                                          data: ["consents": ["collect": ["val": "n"]]])
                        MobileCore.dispatch(event: event)
                    } label: {
                        Text("Consent → No")
                    }
                    .padding()
                }
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
    @State var adID: UUID?
    @State var adIdText: String = ""
    @State var trackingAuthorizationResultText: String = ""

    func getConsents() {
        Consent.getConsents { consents, error in
            if let consents = consents {
                print(consents)
            } else if let error = error {
                print("Error getting consents: \(error)")
            }
        }
    }

    /// Updates view for ad ID related elements
    func setDeviceAdvertisingIdentifier() {
        let isTrackingAuthorized = AdIdUtils.isTrackingAuthorized()
        print("isTrackingAuthorized: \(isTrackingAuthorized)")
        trackingAuthorizationResultText = isTrackingAuthorized ? "Tracking allowed" : "Tracking not allowed"

        if isTrackingAuthorized {
            self.adID = AdIdUtils.getAdvertisingIdentifierForEnvironment()
            print("Advertising identifier fetched: \(String(describing: adID))")
            MobileCore.setAdvertisingIdentifier(self.adID?.uuidString)
        } else {
            print("Ad tracking not authorized; setting ad ID to the empty string")
            MobileCore.setAdvertisingIdentifier("")
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                VStack {
                    Button("Request Tracking Authorization", action: {
                        AdIdUtils.requestTrackingAuthorization {
                            self.setDeviceAdvertisingIdentifier()
                        }
                    })
                    Text(trackingAuthorizationResultText)
                    Text("\(adID?.uuidString ?? "")")
                }

                HStack(spacing: 10) {
                    Button {
                        MobileCore.setAdvertisingIdentifier(adIdText)
                    } label: {
                        Text("Set ad ID")
                    }
                    TextField("Enter ad ID", text: $adIdText)
                        #if os(iOS)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #endif
                        .autocapitalization(.none)
                }
                .padding()
                HStack {
                    Button {
                        MobileCore.setAdvertisingIdentifier(nil)
                    } label: {
                        Text("Set ad ID as nil")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    Button {
                        MobileCore.setAdvertisingIdentifier("00000000-0000-0000-0000-000000000000")
                    } label: {
                        Text("Set ad ID as all-zeros")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    Button {
                        MobileCore.setAdvertisingIdentifier("")
                    } label: {
                        Text("Set ad ID as empty string")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                }
                Button("Get current consents", action: {
                    getConsents()
                })
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
                    .fixedSize()
                    .autocapitalization(.none)

                HStack {
                    TextField("Enter Namespace", text: $identityNamespaceText)
                        .fixedSize()
                        .autocapitalization(.none)
                        .padding(.horizontal)

                    VStack {
                        Toggle(isOn: $isPrimaryChecked) {
                            Text("primary")
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            HStack {
                Picker("AuthenticatedState", selection: $selectedAuthenticatedState) {
                    Text("ambiguous").tag(AuthenticatedState.ambiguous)
                    Text("authenticated").tag(AuthenticatedState.authenticated)
                    Text("logged out").tag(AuthenticatedState.loggedOut)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            HStack {
                Button {
                    let map = IdentityMap()
                    map.add(item: IdentityItem(id: identityItemText, authenticatedState: selectedAuthenticatedState, primary: isPrimaryChecked),
                            withNamespace: identityNamespaceText)
                    AEPEdgeIdentity.Identity.updateIdentities(with: map)
                } label: {
                    Text("Update Identity")
                }
                .padding()
                Button {
                    AEPEdgeIdentity.Identity.removeIdentity(item: IdentityItem(id: identityItemText, authenticatedState: selectedAuthenticatedState, primary: isPrimaryChecked),
                                                            withNamespace: identityNamespaceText)
                } label: {
                    Text("Remove Identity")
                }
                .padding()
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

                Button {
                    if extensions.isEdgeIdentityRegistered {
                        MobileCore.unregisterExtension(AEPEdgeIdentity.Identity.self)
                    } else {
                        MobileCore.registerExtension(AEPEdgeIdentity.Identity.self)
                    }

                    extensions.isEdgeIdentityRegistered.toggle()

                } label: {
                    Text(extensions.isEdgeIdentityRegistered ? "Unregister Edge Identity" : "Register Edge Identity")
                }
            }
            .padding(.bottom, 5)

            Button {
                UserDefaults.standard.removeObject(forKey: edgeIdentityStoredDataKey)
            } label: {
                Text("Clear Persistence")
            }
        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineWidth: 1))

        VStack {
            HStack {
                Image(systemName: extensions.isIdentityDirectRegistered ? "circle.fill" : "circle")
                    .foregroundColor(Color.blue)

                Button {
                    if extensions.isIdentityDirectRegistered {
                        MobileCore.unregisterExtension(AEPIdentity.Identity.self)
                    } else {
                        MobileCore.registerExtension(AEPIdentity.Identity.self)
                    }

                    extensions.isIdentityDirectRegistered.toggle()

                } label: {
                    Text(extensions.isIdentityDirectRegistered ? "Unregister Identity Direct" : "Register Identity Direct")
                }
            }
            .padding(.bottom, 5)

            Button {
                MobileCore.setAdvertisingIdentifier(String(Int.random(in: 1...32)))
            } label: {
                Text("Trigger State Change")
            }
            .padding(.bottom, 5)

            Button {
                UserDefaults.standard.removeObject(forKey: identityStoredDataKey)
            } label: {
                Text("Clear Persistence")
            }
            .padding(.bottom, 5)

            HStack {
                Button {
                    MobileCore.setPrivacyStatus(.optedIn)
                } label: {
                    Text("Privacy OptIn")
                }
                Button {
                    MobileCore.setPrivacyStatus(.optedOut)
                } label: {
                    Text("Privacy OptOut")
                }
            }

        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineWidth: 1))
    }
}
// MARK: TODO remove this once Assurance has tvOS support.
#if os(iOS)
struct AssuranceView: View {
    @State private var assuranceSessionUrl: String = "edgetutorialapp://?adb_validation_sessionid=aa46e49e-0efa-49f8-82b1-703473301ff3"

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            TextField("Copy Assurance Session URL to here", text: $assuranceSessionUrl)
            HStack {
                Button {
                    // step-assurance-start
                    // replace the url with the valid one generated on Assurance UI
                    if let url = URL(string: self.assuranceSessionUrl) {
                        Assurance.startSession(url: url)
                    }
                    // step-assurance-end
                } label: {
                    Text("Connect")
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .cornerRadius(5)
            }
        }
        .padding()
        .onAppear {
            MobileCore.track(state: "AssuranceView", data: nil)
        }
    }
}
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
