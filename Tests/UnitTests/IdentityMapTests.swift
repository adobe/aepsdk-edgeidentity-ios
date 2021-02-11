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

class IdentityMapTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        continueAfterFailure = false // fail so nil checks stop execution
    }

    // MARK: getItemsFor tests

    func testGetItemsFor() {
        let identityMap = IdentityMap()
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false))

        let spaceItems = identityMap.getItemsFor(namespace: "space")
        XCTAssertNotNil(spaceItems)
        XCTAssertEqual(1, spaceItems?.count)
        XCTAssertEqual("id", spaceItems?[0].id)
        XCTAssertEqual("ambiguous", spaceItems?[0].authenticationState.rawValue)
        XCTAssertFalse(spaceItems?[0].primary ?? true)

        let unknown = identityMap.getItemsFor(namespace: "unknown")
        XCTAssertNil(unknown)
    }

    func testAddItems() {
        let identityMap = IdentityMap()
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false))
        identityMap.addItem(namespace: "email", item: IdentityItem(id: "example@adobe.com"))
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "custom", authenticationState: AuthenticationState.ambiguous, primary: true))

        guard let spaceItems = identityMap.getItemsFor(namespace: "space") else {
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

        guard let emailItems = identityMap.getItemsFor(namespace: "email") else {
            XCTFail("Namespace 'email' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, emailItems.count)
        XCTAssertEqual("example@adobe.com", emailItems[0].id)
    }

    func testAddItems_overwrite() {
        let identityMap = IdentityMap()
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false))
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.authenticated))

        guard let spaceItems = identityMap.getItemsFor(namespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual(AuthenticationState.authenticated, spaceItems[0].authenticationState)
        XCTAssertFalse(spaceItems[0].primary)
    }

    // MARK: encoder tests

    func testEncode_oneItem() {
        let identityMap = IdentityMap()
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false))

        guard let actualResult: [String: Any] = identityMap.asDictionary() else {
            XCTFail("IdentityMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
            ["space": [ ["id": "id", "authenticationState": "ambiguous", "primary": false] ]]

        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_twoItems() {
        let identityMap = IdentityMap()
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false))
        identityMap.addItem(namespace: "A", item: IdentityItem(id: "123"))

        guard let actualResult: [String: Any] = identityMap.asDictionary() else {
            XCTFail("IdentityMap.asDictionary returned nil!")
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
        let identityMap = IdentityMap()
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "id", authenticationState: AuthenticationState.ambiguous, primary: false))
        identityMap.addItem(namespace: "space", item: IdentityItem(id: "123"))

        guard let actualResult: [String: Any] = identityMap.asDictionary() else {
            XCTFail("IdentityMap.asDictionary returned nil!")
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

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)
        guard let items = identityMap?.getItemsFor(namespace: "space") else {
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

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)
        guard let spaceItems = identityMap?.getItemsFor(namespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("loggedOut", spaceItems[0].authenticationState.rawValue)
        XCTAssertTrue(spaceItems[0].primary)

        guard let aItems = identityMap?.getItemsFor(namespace: "A") else {
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

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)

        guard let spaceItems = identityMap?.getItemsFor(namespace: "space") else {
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

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)

        guard let spaceItems = identityMap?.getItemsFor(namespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("ambiguous", spaceItems[0].authenticationState.rawValue)
        XCTAssertFalse(spaceItems[0].primary)
    }

    func testDecode_emptyJson() {
        guard let data = "{ }".data(using: .utf8)  else {
            XCTFail("Failed to convert json to data")
            return
        }
        let decoder = JSONDecoder()

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)
    }
}
