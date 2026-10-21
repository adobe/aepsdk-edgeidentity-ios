// Copyright 2026 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.

import AEPServices
import Foundation

/// A test double for `NamedCollectionProcessing` that — unlike the shared `MockDataStore` — partitions
/// values by `collectionName`, mirroring the real `NamedCollectionDataStore` behavior. Required to test that
/// the profile attributes and operational data stores stay separate.
public class CollectionAwareMockDataStore: NamedCollectionProcessing {
    // Keyed by "collectionName\u{0}key" so collections never collide.
    private let queue = DispatchQueue(label: "com.adobe.collectionawaremockdatastore.syncqueue")
    private var storage: [String: Any] = [:]
    private var appGroup: String?

    public init() {}

    private func composite(_ collectionName: String, _ key: String) -> String {
        return "\(collectionName)\u{0}\(key)"
    }

    // MARK: AppGroup methods
    public func getAppGroup() -> String? {
        return queue.sync { appGroup }
    }

    public func setAppGroup(_ appGroup: String?) {
        queue.sync { self.appGroup = appGroup }
    }

    // MARK: DataStore dictionary methods
    public func set(collectionName: String, key: String, value: Any?) {
        queue.sync {
            if let value = value {
                storage[composite(collectionName, key)] = value
            } else {
                storage.removeValue(forKey: composite(collectionName, key))
            }
        }
    }

    public func get(collectionName: String, key: String) -> Any? {
        return queue.sync { storage[composite(collectionName, key)] }
    }

    public func remove(collectionName: String, key: String) {
        _ = queue.sync { storage.removeValue(forKey: composite(collectionName, key)) }
    }
}
