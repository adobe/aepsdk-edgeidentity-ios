//
// Copyright 2022 Adobe. All rights reserved.
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

class URLUtilsTests: XCTestCase {

    func test_generateURLVariablesPayload_validStringValuesPassed_returnsStringWith_TS_ECID_ORGID() {
        let payload = URLUtils.generateURLVariablesPayload(timestamp: "TEST-TS", ecid: "TEST_ECID", orgId: "TEST_ORGID")

        XCTAssertEqual("adobe_mc=TS%3DTEST-TS%7CMCMID%3DTEST_ECID%7CMCORGID%3DTEST_ORGID", payload)
    }

    func test_generateURLVariablesPayload_emptyValuesPassed_returnsStringWithURLPrefixOnly() {
        let payload = URLUtils.generateURLVariablesPayload(timestamp: "", ecid: "", orgId: "")

        XCTAssertEqual("adobe_mc=", payload)
    }
}
