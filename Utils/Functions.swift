/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

public func optFilter<T>(a: [T?]) -> [T] {
    return a.filter { $0 != nil }.map { $0! }
}