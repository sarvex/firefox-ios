/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

public protocol ProfilePrefs {
    func setLong(value: Int64, forKey defaultName: String)
    func setObject(value: AnyObject?, forKey defaultName: String)
    func stringForKey(defaultName: String) -> String?
    func boolForKey(defaultName: String) -> Bool?
    func longForKey(defaultName: String) -> Int64?
    func stringArrayForKey(defaultName: String) -> [String]?
    func arrayForKey(defaultName: String) -> [AnyObject]?
    func dictionaryForKey(defaultName: String) -> [String : AnyObject]?
    func removeObjectForKey(defaultName: String)
    func clearAll()
}

public class MockProfilePrefs : ProfilePrefs {
    var things: NSMutableDictionary = NSMutableDictionary()

    public func setLong(value: Int64, forKey defaultName: String) {
        setObject(NSNumber(longLong: value), forKey: defaultName)
    }

    public func setObject(value: AnyObject?, forKey defaultName: String) {
        things[defaultName] = value
    }

    public func stringForKey(defaultName: String) -> String? {
        return things[defaultName] as? String
    }

    public func boolForKey(defaultName: String) -> Bool? {
        return things[defaultName] as? Bool
    }

    public func longForKey(defaultName: String) -> Int64? {
        let num: NSNumber? = things[defaultName] as? NSNumber
        if let num = num {
            return num.longLongValue
        }
        return nil
    }

    public func stringArrayForKey(defaultName: String) -> [String]? {
        return self.arrayForKey(defaultName) as [String]?
    }

    public func arrayForKey(defaultName: String) -> [AnyObject]? {
        let r: AnyObject? = things.objectForKey(defaultName)
        if (r == nil) {
            return nil
        }
        if let arr = r as? [AnyObject] {
            return arr
        }
        return nil
    }

    public func dictionaryForKey(defaultName: String) -> [String : AnyObject]? {
        return things.objectForKey(defaultName) as? [String: AnyObject]
    }

    public func removeObjectForKey(defaultName: String) {
        self.things[defaultName] = nil
    }

    public func clearAll() {
        self.things.removeAllObjects()
    }
}

public class NSUserDefaultsProfilePrefs : ProfilePrefs {
    private let profile: Profile
    private let prefix: String
    private let userDefaults: NSUserDefaults

    init(profile: Profile) {
        self.profile = profile
        self.prefix = profile.localName() + "."
        self.userDefaults = NSUserDefaults(suiteName: ExtensionUtils.sharedContainerIdentifier())!
    }

    // Preferences are qualified by the profile's local name.
    // Connecting a profile to a Firefox Account, or changing to another, won't alter this.
    private func qualifyKey(key: String) -> String {
        return self.prefix + key
    }

    public func setLong(value: Int64, forKey defaultName: String) {
        setObject(NSNumber(longLong: value), forKey: defaultName)
    }

    public func setObject(value: AnyObject?, forKey defaultName: String) {
        userDefaults.setObject(value, forKey: qualifyKey(defaultName))
    }

    public func stringForKey(defaultName: String) -> String? {
        // stringForKey converts numbers to strings, which is almost always a bug.
        return userDefaults.objectForKey(qualifyKey(defaultName)) as? String
    }

    public func boolForKey(defaultName: String) -> Bool? {
        // boolForKey just returns false if the key doesn't exist. We need to
        // distinguish between false and non-existent keys, so use objectForKey
        // and cast the result instead.
        return userDefaults.objectForKey(qualifyKey(defaultName)) as? Bool
    }

    public func longForKey(defaultName: String) -> Int64? {
        let num: NSNumber? = userDefaults.objectForKey(qualifyKey(defaultName)) as? NSNumber
        if let num = num {
            return num.longLongValue
        }
        return nil
    }
    public func stringArrayForKey(defaultName: String) -> [String]? {
        return userDefaults.stringArrayForKey(qualifyKey(defaultName)) as [String]?
    }

    public func arrayForKey(defaultName: String) -> [AnyObject]? {
        return userDefaults.arrayForKey(qualifyKey(defaultName))
    }

    public func dictionaryForKey(defaultName: String) -> [String : AnyObject]? {
        return userDefaults.dictionaryForKey(qualifyKey(defaultName)) as? [String:AnyObject]
    }

    public func removeObjectForKey(defaultName: String) {
        userDefaults.removeObjectForKey(qualifyKey(defaultName))
    }

    public func clearAll() {
        // TODO: userDefaults.removePersistentDomainForName() has no effect for app group suites.
        // iOS Bug? Iterate and remove each manually for now.
        for key in userDefaults.dictionaryRepresentation().keys {
            userDefaults.removeObjectForKey(key as NSString)
        }
    }
}
