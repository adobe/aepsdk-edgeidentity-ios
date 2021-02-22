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

@testable import AEPIdentityEdge
import XCTest

class IdentityEdgeMapTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        continueAfterFailure = false // fail so nil checks stop execution
    }

    // MARK: getItemsWith tests

    func testGetItemsWith() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")

        let spaceItems = identityEdgeMap.getItems(withNamespace: "space")
        XCTAssertNotNil(spaceItems)
        XCTAssertEqual(1, spaceItems?.count)
        XCTAssertEqual("id", spaceItems?[0].id)
        XCTAssertEqual("ambiguous", spaceItems?[0].authenticationState.rawValue)
        XCTAssertFalse(spaceItems?[0].primary ?? true)

        let unknown = identityEdgeMap.getItems(withNamespace: "unknown")
        XCTAssertNil(unknown)
    }

    func testAddItems() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")
        identityEdgeMap.add(item: IdentityItem(id: "example@adobe.com"), withNamespace: "email")
        identityEdgeMap.add(item: IdentityItem(id: "custom", authenticationState: AuthenticationState.ambiguous, primary: true), withNamespace: "space")

        guard let spaceItems = identityEdgeMap.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(2, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual(AuthenticationState.ambiguous, spaceItems[0].authenticationState)
        XCTAssertFalse(spaceItems[0].primary)
        XCTAssertEqual("custom", spaceItems[1].id)
        XCTAssertEqual(AuthenticationState.ambiguous, spaceItems[1].authenticationState)
        XCTAssertTrue(spaceItems[1].primary)

        guard let emailItems = identityEdgeMap.getItems(withNamespace: "email") else {
            XCTFail("Namespace 'email' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, emailItems.count)
        XCTAssertEqual("example@adobe.com", emailItems[0].id)
    }

    func testAddItems_overwrite() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.authenticated), withNamespace: "space")

        guard let spaceItems = identityEdgeMap.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual(AuthenticationState.authenticated, spaceItems[0].authenticationState)
        XCTAssertFalse(spaceItems[0].primary)
    }

    func testAddItems_withEmptyIdNotAllowed() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")
        identityEdgeMap.add(item: IdentityItem(id: "", authenticationState: AuthenticationState.authenticated), withNamespace: "space")

        XCTAssertNil(identityEdgeMap.getItems(withNamespace: "space"))
    }

    func testAddItems_withEmptyNamespaceNotAllowed() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "")

        XCTAssertNil(identityEdgeMap.getItems(withNamespace: ""))
    }

    // MARK: encoder tests

    func testEncode_oneItem() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")

        guard let actualResult: [String: Any] = identityEdgeMap.asDictionary() else {
            XCTFail("IdentityEdgeMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
            ["space": [ ["id": "id", "authenticationState": "ambiguous", "primary": false] ]]

        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_twoItems() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")
        identityEdgeMap.add(item: IdentityItem(id: "123"), withNamespace: "A")

        guard let actualResult: [String: Any] = identityEdgeMap.asDictionary() else {
            XCTFail("IdentityEdgeMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
            [
                "A": [ ["id": "123", "authenticationState": "ambiguous", "primary": false] ],
                "space": [ ["id": "id", "authenticationState": "ambiguous", "primary": false] ]
            ]

        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_twoItemsSameNamespace() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")
        identityEdgeMap.add(item: IdentityItem(id: "123"), withNamespace: "space")

        guard let actualResult: [String: Any] = identityEdgeMap.asDictionary() else {
            XCTFail("IdentityEdgeMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
            [
                "space": [
                    ["id": "id", "authenticationState": "ambiguous", "primary": false],
                    ["id": "123", "authenticationState": "ambiguous", "primary": false]
                ]
            ]
        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_itemWithEmptyIdNotAllowed() {
        let identityEdgeMap = IdentityEdgeMap()
        identityEdgeMap.add(item: IdentityItem(id: "", authenticationState: AuthenticationState.ambiguous, primary: false), withNamespace: "space")

        XCTAssertEqual(true, identityEdgeMap.asDictionary()?.isEmpty)
    }

    // MARK: decoder tests

    func testDecode_oneItem() {
        guard let data = """
            {
              "space" : [
                {
                  "authenticationState" : "ambiguous",
                  "id" : "id",
                  "primary" : false
                }
              ]
            }
        """.data(using: .utf8) else {
            XCTFail("Failed to convert json string to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)
        guard let items = identityEdgeMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, items.count)
        XCTAssertEqual("id", items[0].id)
        XCTAssertEqual("ambiguous", items[0].authenticationState.rawValue)
        XCTAssertFalse(items[0].primary)
    }

    func testDecode_twoItems() {
        guard let data = """
             {
               "A" : [
                 {
                   "id" : "123"
                 }
               ],
               "space" : [
                 {
                   "authenticationState" : "loggedOut",
                   "id" : "id",
                   "primary" : true
                 }
               ]
             }
         """.data(using: .utf8) else {
            XCTFail("Failed to convert json string to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)
        guard let spaceItems = identityEdgeMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("loggedOut", spaceItems[0].authenticationState.rawValue)
        XCTAssertTrue(spaceItems[0].primary)

        guard let aItems = identityEdgeMap?.getItems(withNamespace: "A") else {
            XCTFail("Namespace 'A' is nil but expected not nil.")
            return
        }

        XCTAssertEqual("123", aItems[0].id)
        XCTAssertEqual("ambiguous", aItems[0].authenticationState.rawValue)
        XCTAssertFalse(aItems[0].primary)
    }

    func testDecode_twoItemsSameNamespace() {
        guard let data = """
             {
               "space" : [
                 {
                   "authenticationState" : "loggedOut",
                   "id" : "id",
                   "primary" : true
                 },
                 {
                   "id" : "123"
                 }
               ]
             }
         """.data(using: .utf8) else {
            XCTFail("Failed to convert json to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)

        guard let spaceItems = identityEdgeMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(2, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("loggedOut", spaceItems[0].authenticationState.rawValue)
        XCTAssertTrue(spaceItems[0].primary)

        XCTAssertEqual("123", spaceItems[1].id)
        XCTAssertEqual("ambiguous", spaceItems[1].authenticationState.rawValue)
        XCTAssertFalse(spaceItems[1].primary)

    }

    func testDecode_unknownParamsInIdentityItem() {
        guard let data = """
              {
                "space" : [
                  {
                    "authenticationState" : "ambiguous",
                    "id" : "id",
                    "unknown" : true,
                    "primary" : false
                  }
                ]
              }
          """.data(using: .utf8) else {
            XCTFail("Failed to convert json to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)

        guard let spaceItems = identityEdgeMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("ambiguous", spaceItems[0].authenticationState.rawValue)
        XCTAssertFalse(spaceItems[0].primary)
    }

    func testDecode_itemWithEmptyId() {
        guard let data = """
            {
              "space" : [
                {
                  "id" : ""
                }
              ]
            }
        """.data(using: .utf8) else {
            XCTFail("Failed to convert json string to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)
        XCTAssertNil(identityEdgeMap?.getItems(withNamespace: "space"))
    }

    func testDecode_itemWithEmptyNamespace() {
        guard let data = """
            {
              "" : [
                {
                  "id" : "id"
                }
              ]
            }
        """.data(using: .utf8) else {
            XCTFail("Failed to convert json string to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)
        XCTAssertNil(identityEdgeMap?.getItems(withNamespace: ""))
    }

    func testDecode_emptyJson() {
        guard let data = "{ }".data(using: .utf8)  else {
            XCTFail("Failed to convert json to data")
            return
        }
        let decoder = JSONDecoder()

        let identityEdgeMap = try? decoder.decode(IdentityEdgeMap.self, from: data)
        XCTAssertNotNil(identityEdgeMap)
    }
}
