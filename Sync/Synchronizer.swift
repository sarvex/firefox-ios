/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

// TODO: return values?
public protocol Synchronizer {
    init(info: InfoCollections)
    func synchronize()
}

public class ClientsSynchronizer: Synchronizer {
    private let info: InfoCollections
    private let prefs: ProfilePrefs

    required public init(info: InfoCollections, prefs: ProfilePrefs) {
        self.info = info
        self.prefs = prefs
    }

    public func synchronize() {
    }
}