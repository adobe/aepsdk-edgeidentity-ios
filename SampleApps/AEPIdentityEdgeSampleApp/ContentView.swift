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
import AEPIdentityEdge
import SwiftUI

struct ContentView: View {
    @State var ecidText: String
    @State var adIdText: String
    @State var identityMapText: String
    @State var identityItemText: String = ""
    @State var identityNamespaceText: String = ""
    @State var selectedAuthenticationState: AuthenticationState = .ambiguous
    @State var isPrimaryChecked: Bool = false

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

        VStack {
            Button(action: {
                self.ecidText = ""
                IdentityEdge.getExperienceCloudId { ecid, _ in
                    if let ecid = ecid {
                        self.ecidText = ecid
                    } else {
                        self.ecidText = "ecid is nil"
                    }
                }
            }) {
                Text("Get ECID")
            }.padding()

            Text(ecidText)
                .font(.system(size: 12))
                .padding()
        }.padding()

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

        VStack {
            Button(action: {
                IdentityEdge.resetIdentities()
            }) {
                Text("Reset Identities")
            }
        }

        VStack {
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

            ScrollView {
                Text(identityMapText)
                    .font(.system(size: 12))
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineWidth: 1))
            }
        }

    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ecidText: "", adIdText: "", identityMapText: "")
    }
}
