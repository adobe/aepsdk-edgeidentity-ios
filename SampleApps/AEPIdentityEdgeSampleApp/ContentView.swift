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

    var body: some View {
        HStack {
            Text("Privacy: ")
            Button(action: {
                MobileCore.setPrivacyStatus(PrivacyStatus.optedIn)
            }) {
                Text("in")
            }
            Button(action: {
                MobileCore.setPrivacyStatus(PrivacyStatus.optedOut)
            }) {
                Text("out")
            }
            Button(action: {
                MobileCore.setPrivacyStatus(PrivacyStatus.unknown)
            }) {
                Text("unknown")
            }
        }.padding()

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
                Identity.getExperienceCloudId { ecid, _ in
                    if let ecid = ecid {
                        self.ecidText = ecid
                    } else {
                        self.ecidText = "ecid is null"
                    }
                }
            }) {
                Text("Get ECID")
            }.padding()

            Text(ecidText)
        }

    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ecidText: "", adIdText: "")
    }
}
