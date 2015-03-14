/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class StorageClientTests: XCTestCase {

    // Trivial test for struct semantics that we might want to pay attention to if they change.
    func testStructSemantics() {
        let x: StorageResponse<JSON> = StorageResponse<JSON>(value: JSON.parse("{\"a:\": 2}"), lastModified: 5)

        func doTesting(y: StorageResponse<JSON>) {

            XCTAssertTrue(y.lastModified == x.lastModified, "lastModified is the same.")
            XCTAssertTrue(y.lastModified == 5, "lastModified is 5.")

            // Make sure that reference fields in a struct are copies of the same reference,
            // not references to a copy.
            XCTAssertTrue(x.value === y.value)
        }

        doTesting(x)
    }
}