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
import AEPEdgeIdentity
import AEPIdentity
import SwiftUI

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
                    AEPEdgeIdentity.Identity.resetIdentities()
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

struct CustomIdentiferView: View {
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
