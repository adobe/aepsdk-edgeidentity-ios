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
import AEPIdentity
import AEPIdentityEdge
import SwiftUI

class RegisteredExtensions: ObservableObject {
    @Published var isIdentityEdgeRegistered: Bool = true
    @Published var isIdentityDirectRegistered: Bool = false
}

struct ContentView: View {
    @StateObject var registeredExtensions = RegisteredExtensions()

    var body: some View {

        NavigationView {
            VStack(alignment: .center, spacing: 20, content: {

                NavigationLink(
                    destination: AdvertisingIdentifierView(),
                    label: {
                        Text("Set Advertising Identifier")
                    })

                NavigationLink(
                    destination: CustomIdentiferView(),
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
    @State var ecidIdentityEdgeText: String = ""
    @State var ecidIdentityText: String = ""
    @State var identityMapText: String = ""

    var body: some View {
        VStack {
            Button(action: {
                self.ecidIdentityEdgeText = ""
                self.ecidIdentityText = ""

                IdentityEdge.getExperienceCloudId { ecid, _ in
                    if let ecid = ecid {
                        self.ecidIdentityEdgeText = ecid
                    } else {
                        self.ecidIdentityEdgeText = "ecid is nil"
                    }
                }

                Identity.getExperienceCloudId { ecid, _ in
                    if let ecid = ecid {
                        self.ecidIdentityText = ecid
                    } else {
                        self.ecidIdentityText = ""
                    }
                }
            }) {
                Text("Get ECID")
            }

            Text("edge : \(ecidIdentityEdgeText)" + (ecidIdentityText.isEmpty ? "" : "\ndirect: \(ecidIdentityText)"))
                .font(.system(size: 12))
                .padding()

            HStack {
                Button(action: {
                    self.identityMapText = ""
                    IdentityEdge.getIdentities { identityMap, _ in
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
                    IdentityEdge.resetIdentities()
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

    var body: some View {
        VStack {
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

struct CustomIdentiferView: View {
    @State var identityItemText: String = ""
    @State var identityNamespaceText: String = ""
    @State var selectedAuthenticationState: AuthenticationState = .ambiguous
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
                Picker("AuthenticationState", selection: $selectedAuthenticationState) {
                    Text("ambiguous").tag(AuthenticationState.ambiguous)
                    Text("authenticated").tag(AuthenticationState.authenticated)
                    Text("logged out").tag(AuthenticationState.loggedOut)
                }.pickerStyle(SegmentedPickerStyle())
            }
            HStack {
                Button(action: {
                    let map = IdentityMap()
                    map.add(item: IdentityItem(id: identityItemText, authenticationState: selectedAuthenticationState, primary: isPrimaryChecked),
                            withNamespace: identityNamespaceText)
                    IdentityEdge.updateIdentities(with: map)
                }) {
                    Text("Update Identity")
                }.padding()
                Button(action: {
                    IdentityEdge.removeIdentity(item: IdentityItem(id: identityItemText, authenticationState: selectedAuthenticationState, primary: isPrimaryChecked),
                                                withNamespace: identityNamespaceText)
                }) {
                    Text("Remove Identity")
                }.padding()
            }

        }
    }
}

struct MultipleIdentityView: View {
    @ObservedObject var extensions: RegisteredExtensions
    @State var ecidIdentityEdgeText: String = ""
    @State var ecidIdentityText: String = ""
    @State var identityMapText: String = ""

    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Image(systemName: extensions.isIdentityEdgeRegistered ? "circle.fill" : "circle")
                    .foregroundColor(Color.blue)

                Button(action: {
                    if extensions.isIdentityEdgeRegistered {
                        MobileCore.unregisterExtension(IdentityEdge.self)
                    } else {
                        MobileCore.registerExtension(IdentityEdge.self)
                    }

                    extensions.isIdentityEdgeRegistered.toggle()

                }) {
                    Text(extensions.isIdentityEdgeRegistered ? "Unregister Identity Edge" : "Register Identity Edge")
                }
            }.padding(.bottom, 5)

            Button(action: {
                UserDefaults.standard.removeObject(forKey: "Adobe.com.adobe.identityedge.identity.properties")
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
                        MobileCore.unregisterExtension(Identity.self)
                    } else {
                        MobileCore.registerExtension(Identity.self)
                    }

                    extensions.isIdentityDirectRegistered.toggle()

                }) {
                    Text(extensions.isIdentityDirectRegistered ? "Unregister Identity Direct" : "Register Identity Direct")
                }
            }.padding(.bottom, 5)

            Button(action: {
                UserDefaults.standard.removeObject(forKey: "Adobe.com.adobe.module.identity.identity.properties")
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
