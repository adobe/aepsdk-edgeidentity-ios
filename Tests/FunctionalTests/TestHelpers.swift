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

@testable import AEPCore
import XCTest

extension EventHub {
    static func reset() {
        shared = EventHub()
    }
}

extension UserDefaults {
    public static func clear() {
        for _ in 0 ... 5 {
            for key in UserDefaults.standard.dictionaryRepresentation().keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
extension FileManager {

    func clearCache() {

        let cacheUrls: [String: Bool] = [
            "Library/Caches/com.adobe.module.signal": false,
            "Library/Caches/com.adobe.module.identity": false,
            "Library/Caches/com.adobe.mobile.diskcache": true
        ]

        if self.urls(for: .cachesDirectory, in: .userDomainMask).first != nil {

            for (url, isDirectory) in cacheUrls {
                do {
                    try self.removeItem(at: URL(fileURLWithPath: url, isDirectory: isDirectory))
                } catch {
                    print("ERROR DESCRIPTION: \(error)")
                }
            }
        }

    }

}
