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

@testable import AEPEdgeIdentity
import XCTest

class IdentityMapTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        continueAfterFailure = false // fail so nil checks stop execution
    }

    // MARK: getItemsWith tests

    func testGetItemsWith() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")

        let spaceItems = identityMap.getItems(withNamespace: "space")
        XCTAssertNotNil(spaceItems)
        XCTAssertEqual(1, spaceItems?.count)
        XCTAssertEqual("id", spaceItems?[0].id)
        XCTAssertEqual("ambiguous", spaceItems?[0].authenticatedState.rawValue)
        XCTAssertFalse(spaceItems?[0].primary ?? true)

        let unknown = identityMap.getItems(withNamespace: "unknown")
        XCTAssertNil(unknown)
    }

    // MARK: add(item:withNamespace:)

    func testAddItemWithNamespace() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "example@adobe.com"), withNamespace: "email")
        identityMap.add(item: IdentityItem(id: "custom", authenticatedState: AuthenticatedState.ambiguous, primary: true), withNamespace: "space")

        guard let spaceItems = identityMap.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(2, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, spaceItems[0].authenticatedState)
        XCTAssertFalse(spaceItems[0].primary)
        XCTAssertEqual("custom", spaceItems[1].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, spaceItems[1].authenticatedState)
        XCTAssertTrue(spaceItems[1].primary)

        guard let emailItems = identityMap.getItems(withNamespace: "email") else {
            XCTFail("Namespace 'email' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, emailItems.count)
        XCTAssertEqual("example@adobe.com", emailItems[0].id)
    }

    func testAddItemWithNamespace_overwrite() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.authenticated), withNamespace: "space")

        guard let spaceItems = identityMap.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual(AuthenticatedState.authenticated, spaceItems[0].authenticatedState)
        XCTAssertFalse(spaceItems[0].primary)
    }

    func testAddItemWithNamespace_withEmptyIdNotAllowed() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "", authenticatedState: AuthenticatedState.authenticated), withNamespace: "space")

        XCTAssertNil(identityMap.getItems(withNamespace: "space"))
    }

    func testAddItemWithNamespace_withEmptyNamespaceNotAllowed() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "")

        XCTAssertNil(identityMap.getItems(withNamespace: ""))
    }

    // MARK: remove(item:withNamespace:)

    func testRemoveItemWithNamespace() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "id2", authenticatedState: AuthenticatedState.authenticated, primary: true), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "example@adobe.com"), withNamespace: "email")
        identityMap.add(item: IdentityItem(id: "custom", authenticatedState: AuthenticatedState.ambiguous, primary: true), withNamespace: "space")

        identityMap.remove(item: IdentityItem(id: "id"), withNamespace: "space")
        identityMap.remove(item: IdentityItem(id: "id2"), withNamespace: "space")

        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("custom", identityMap.getItems(withNamespace: "space")?[0].id)
        XCTAssertEqual(1, identityMap.getItems(withNamespace: "email")?.count)
        XCTAssertEqual("example@adobe.com", identityMap.getItems(withNamespace: "email")?[0].id)
    }

    func testRemoveItemWithNamespaceNotExist() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")

        identityMap.remove(item: IdentityItem(id: "custom"), withNamespace: "space")

        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("id", identityMap.getItems(withNamespace: "space")?[0].id)
    }

    func testRemoveItemWithNamespaceWrongNamespace() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")

        identityMap.remove(item: IdentityItem(id: "custom"), withNamespace: "galaxy")

        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space")?.count)
        XCTAssertEqual("id", identityMap.getItems(withNamespace: "space")?[0].id)
    }

    // MARK: isEmpty

    func testIsEmpty() {
        let identityMap = IdentityMap()
        XCTAssertTrue(identityMap.isEmpty)

        identityMap.add(item: IdentityItem(id: "id"), withNamespace: "space")
        XCTAssertFalse(identityMap.isEmpty)

        identityMap.remove(item: IdentityItem(id: "id"), withNamespace: "space")
        XCTAssertTrue(identityMap.isEmpty)
    }

    // MARK: encoder tests

    func testEncode_oneItem() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")

        guard let actualResult: [String: Any] = identityMap.asDictionary() else {
            XCTFail("IdentityMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
        ["space": [ ["id": "id", "authenticatedState": "ambiguous", "primary": false]]]

        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_twoItems() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "123"), withNamespace: "A")

        guard let actualResult: [String: Any] = identityMap.asDictionary() else {
            XCTFail("IdentityMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
            [
                "A": [ ["id": "123", "authenticatedState": "ambiguous", "primary": false]],
                "space": [ ["id": "id", "authenticatedState": "ambiguous", "primary": false]]
            ]

        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_twoItemsSameNamespace() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "id", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")
        identityMap.add(item: IdentityItem(id: "123"), withNamespace: "space")

        guard let actualResult: [String: Any] = identityMap.asDictionary() else {
            XCTFail("IdentityMap.asDictionary returned nil!")
            return
        }
        let expectedResult: [String: Any] =
            [
                "space": [
                    ["id": "id", "authenticatedState": "ambiguous", "primary": false],
                    ["id": "123", "authenticatedState": "ambiguous", "primary": false]
                ]
            ]
        XCTAssertEqual(expectedResult as NSObject, actualResult as NSObject)
    }

    func testEncode_itemWithEmptyIdNotAllowed() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "", authenticatedState: AuthenticatedState.ambiguous, primary: false), withNamespace: "space")

        XCTAssertEqual(true, identityMap.asDictionary()?.isEmpty)
    }

    // MARK: decoder tests

    func testDecode_oneItem() {
        guard let data = """
            {
              "space" : [
                {
                  "authenticatedState" : "ambiguous",
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
        guard let items = identityMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, items.count)
        XCTAssertEqual("id", items[0].id)
        XCTAssertEqual("ambiguous", items[0].authenticatedState.rawValue)
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
                   "authenticatedState" : "loggedOut",
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
        guard let spaceItems = identityMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("loggedOut", spaceItems[0].authenticatedState.rawValue)
        XCTAssertTrue(spaceItems[0].primary)

        guard let aItems = identityMap?.getItems(withNamespace: "A") else {
            XCTFail("Namespace 'A' is nil but expected not nil.")
            return
        }

        XCTAssertEqual("123", aItems[0].id)
        XCTAssertEqual("ambiguous", aItems[0].authenticatedState.rawValue)
        XCTAssertFalse(aItems[0].primary)
    }

    func testDecode_twoItemsSameNamespace() {
        guard let data = """
             {
               "space" : [
                 {
                   "authenticatedState" : "loggedOut",
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

        guard let spaceItems = identityMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(2, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("loggedOut", spaceItems[0].authenticatedState.rawValue)
        XCTAssertTrue(spaceItems[0].primary)

        XCTAssertEqual("123", spaceItems[1].id)
        XCTAssertEqual("ambiguous", spaceItems[1].authenticatedState.rawValue)
        XCTAssertFalse(spaceItems[1].primary)

    }

    func testDecode_unknownParamsInIdentityItem() {
        guard let data = """
              {
                "space" : [
                  {
                    "authenticatedState" : "ambiguous",
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

        guard let spaceItems = identityMap?.getItems(withNamespace: "space") else {
            XCTFail("Namespace 'space' is nil but expected not nil.")
            return
        }

        XCTAssertEqual(1, spaceItems.count)
        XCTAssertEqual("id", spaceItems[0].id)
        XCTAssertEqual("ambiguous", spaceItems[0].authenticatedState.rawValue)
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

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)
        XCTAssertNil(identityMap?.getItems(withNamespace: "space"))
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

        let identityMap = try? decoder.decode(IdentityMap.self, from: data)
        XCTAssertNotNil(identityMap)
        XCTAssertNil(identityMap?.getItems(withNamespace: ""))
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

    // MARK: merge(map:)

    func testMerge() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "item1"), withNamespace: "space1")
        identityMap.add(item: IdentityItem(id: "item1", authenticatedState: .loggedOut, primary: false), withNamespace: "space2")
        identityMap.add(item: IdentityItem(id: "item2"), withNamespace: "space2")

        let otherIdentityMap = IdentityMap()
        otherIdentityMap.add(item: IdentityItem(id: "item1", authenticatedState: .authenticated, primary: true), withNamespace: "space2")
        otherIdentityMap.add(item: IdentityItem(id: "item3"), withNamespace: "space2")
        otherIdentityMap.add(item: IdentityItem(id: "item1"), withNamespace: "space3")

        // test
        identityMap.merge(map: otherIdentityMap)

        // verify
        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space1")?.count)
        // namespace: space1, item: 1: same as original
        XCTAssertEqual("item1", identityMap.getItems(withNamespace: "space1")?[0].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space1")?[0].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space1")?[0].primary)

        XCTAssertEqual(3, identityMap.getItems(withNamespace: "space2")?.count)
        // namespace: space2, item: 1: overwritten by other
        XCTAssertEqual("item1", identityMap.getItems(withNamespace: "space2")?[0].id)
        XCTAssertEqual(AuthenticatedState.authenticated, identityMap.getItems(withNamespace: "space2")?[0].authenticatedState)
        XCTAssertEqual(true, identityMap.getItems(withNamespace: "space2")?[0].primary)
        // namespace: space2, item: 2: same as original
        XCTAssertEqual("item2", identityMap.getItems(withNamespace: "space2")?[1].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space2")?[1].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space2")?[1].primary)
        // namespace: space2, item: 3: added by other
        XCTAssertEqual("item3", identityMap.getItems(withNamespace: "space2")?[2].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space2")?[2].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space2")?[2].primary)

        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space3")?.count)
        // namespace: space3, item: 1: added by other
        XCTAssertEqual("item1", identityMap.getItems(withNamespace: "space3")?[0].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space3")?[0].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space3")?[0].primary)
    }

    func testMergeOtherIdentityMapEmpty() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "item1"), withNamespace: "space1")

        // test
        identityMap.merge(map: IdentityMap())

        // verify
        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space1")?.count)
        // namespace: space1, item: 1
        XCTAssertEqual("item1", identityMap.getItems(withNamespace: "space1")?[0].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space1")?[0].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space1")?[0].primary)
    }

    func testMergeIdentityMapEmpty() {
        let identityMap = IdentityMap()

        let otherIdentityMap = IdentityMap()
        otherIdentityMap.add(item: IdentityItem(id: "item1"), withNamespace: "space1")

        // test
        identityMap.merge(map: otherIdentityMap)

        // verify
        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space1")?.count)
        // namespace: space1, item: 1
        XCTAssertEqual("item1", identityMap.getItems(withNamespace: "space1")?[0].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space1")?[0].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space1")?[0].primary)
    }

    // MARK: remove(map:)

    func testRemoveMap() {
        let identityMap = IdentityMap()
        identityMap.add(item: IdentityItem(id: "item1"), withNamespace: "space1")
        identityMap.add(item: IdentityItem(id: "item1", authenticatedState: .loggedOut, primary: false), withNamespace: "space2")
        identityMap.add(item: IdentityItem(id: "item2"), withNamespace: "space2")

        let otherIdentityMap = IdentityMap()
        otherIdentityMap.add(item: IdentityItem(id: "item1", authenticatedState: .authenticated, primary: true), withNamespace: "space1")
        otherIdentityMap.add(item: IdentityItem(id: "item1", authenticatedState: .authenticated, primary: true), withNamespace: "space2")
        otherIdentityMap.add(item: IdentityItem(id: "item3"), withNamespace: "space2")
        otherIdentityMap.add(item: IdentityItem(id: "item1"), withNamespace: "space3")

        identityMap.remove(map: otherIdentityMap)

        XCTAssertNil(identityMap.getItems(withNamespace: "space1"))
        XCTAssertNil(identityMap.getItems(withNamespace: "space3"))
        XCTAssertEqual(1, identityMap.getItems(withNamespace: "space2")?.count)
        XCTAssertEqual("item2", identityMap.getItems(withNamespace: "space2")?[0].id)
        XCTAssertEqual(AuthenticatedState.ambiguous, identityMap.getItems(withNamespace: "space2")?[0].authenticatedState)
        XCTAssertEqual(false, identityMap.getItems(withNamespace: "space2")?[0].primary)

    }

    // MARK: from(...)

    func testFromValidEventData() {
        let data = ["ECID": [["id": "1234"]]]
        let identityMap = IdentityMap.from(eventData: data)
        XCTAssertNotNil(identityMap)
        XCTAssertEqual("1234", identityMap?.getItems(withNamespace: "ECID")?[0].id)
    }

    func testFromWithEmptyDataReturnsEmptyIdentityMap() {
        let identityMap = IdentityMap.from(eventData: [:])
        XCTAssertEqual(true, identityMap?.isEmpty)
    }

    func testFromWithInvalidDataDecode() {
        let bogusStr = String(bytes: [0xD8, 0x00] as [UInt8], encoding: String.Encoding.utf16BigEndian)!
        let data = ["foo": bogusStr]
        let identityMap = IdentityMap.from(eventData: data)
        XCTAssertNil(identityMap)
    }
}
