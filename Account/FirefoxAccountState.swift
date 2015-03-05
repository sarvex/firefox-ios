/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import FxA

public enum FirefoxAccountStateLabel: String {
    case Engaged = "engaged"
    case CohabitingWithoutKeyPair = "cohabitingWithoutKeyPair"
    case Cohabiting = "cohabiting"
    case Married = "married"
    case Separated = "separated"
    case Doghouse = "doghouse"
}

public enum FirefoxAccountActionNeeded {
    case None
    case NeedsVerification
    case NeedsPassword
    case NeedsUpgrade
}

public class FirefoxAccountState {
    let version = 1

    let label: FirefoxAccountStateLabel
    let verified: Bool

    init(label: FirefoxAccountStateLabel, verified: Bool) {
        self.label = label
        self.verified = verified
    }

    func asDictionary() -> [String: AnyObject] {
        var dict: [String: AnyObject] = [:]
        dict["version"] = version
        dict["label"] = self.label.rawValue
        return dict
    }

    func getActionNeeded() -> FirefoxAccountActionNeeded {
        return .NeedsUpgrade
    }

    public class Separated: FirefoxAccountState {
        public init() {
            super.init(label: .Separated, verified: false)
        }

        override func getActionNeeded() -> FirefoxAccountActionNeeded {
            return .NeedsPassword
        }
    }

    public class Engaged: FirefoxAccountState {
        let sessionToken: NSData
        let keyFetchToken: NSData
        let unwrapkB: NSData

        public init(verified: Bool, sessionToken: NSData, keyFetchToken: NSData, unwrapkB: NSData) {
            self.sessionToken = sessionToken
            self.keyFetchToken = keyFetchToken
            self.unwrapkB = unwrapkB
            super.init(label: .Engaged, verified: verified)
        }

        override func asDictionary() -> [String: AnyObject] {
            var d = super.asDictionary()
            d["verified"] = self.verified
            d["sessionToken"] = sessionToken.base16EncodedStringWithOptions(NSDataBase16EncodingOptions.LowerCase)
            d["keyFetchToken"] = keyFetchToken.base16EncodedStringWithOptions(NSDataBase16EncodingOptions.LowerCase)
            d["unwrapkB"] = unwrapkB.base16EncodedStringWithOptions(NSDataBase16EncodingOptions.LowerCase)
            return d
        }

        override func getActionNeeded() -> FirefoxAccountActionNeeded {
            if verified {
                return .None
            } else {
                return .NeedsVerification
            }
        }
    }

    public class TokenAndKeys: FirefoxAccountState {
        let sessionToken: NSData
        let kA: NSData
        let kB: NSData

        init(label: FirefoxAccountStateLabel, sessionToken: NSData, kA: NSData, kB: NSData) {
            self.sessionToken = sessionToken
            self.kA = kA
            self.kB = kB
            super.init(label: label, verified: true)
        }

        override func asDictionary() -> [String: AnyObject] {
            var d = super.asDictionary()
            d["kA"] = kA.base16EncodedStringWithOptions(NSDataBase16EncodingOptions.LowerCase)
            d["kB"] = kB.base16EncodedStringWithOptions(NSDataBase16EncodingOptions.LowerCase)
            return d
        }

        override func getActionNeeded() -> FirefoxAccountActionNeeded {
            return .None
        }
    }


    public class TokenKeysAndKeyPair: TokenAndKeys {
        let keyPair: KeyPair
        // Timestamp, in milliseconds after the epoch, when keyPair expires.  After this time, generate a new keyPair.
        let keyPairExpiresAt: Int64

        init(label: FirefoxAccountStateLabel, sessionToken: NSData, kA: NSData, kB: NSData, keyPair: KeyPair, keyPairExpiresAt: Int64) {
            self.keyPair = keyPair
            self.keyPairExpiresAt = keyPairExpiresAt
            super.init(label: label, sessionToken: sessionToken, kA: kA, kB: kB)
        }

        override func asDictionary() -> [String: AnyObject] {
            var d = super.asDictionary()
            d["keyPairExpiresAt"] = NSNumber(longLong: keyPairExpiresAt)
            d["keyPair"] = keyPair.JSONRepresentation()
            return d
        }

        func isKeyPairExpired(now: Int64) -> Bool {
            return keyPairExpiresAt < now
        }
    }



    public class CohabitingWithoutKeyPair: TokenAndKeys {
        init(sessionToken: NSData, kA: NSData, kB: NSData) {
            super.init(label: .CohabitingWithoutKeyPair, sessionToken: sessionToken, kA: kA, kB: kB)
        }
    }

    public class Cohabiting: TokenKeysAndKeyPair {
        init(sessionToken: NSData, kA: NSData, kB: NSData, keyPair: KeyPair, keyPairExpiresAt: Int64) {
            super.init(label: .Cohabiting, sessionToken: sessionToken, kA: kA, kB: kB, keyPair: keyPair, keyPairExpiresAt: keyPairExpiresAt)
        }
    }

    public class Married: TokenKeysAndKeyPair {
        let certificate: String
        let certificateExpiresAt: Int64

        init(sessionToken: NSData, kA: NSData, kB: NSData, keyPair: KeyPair, keyPairExpiresAt: Int64, certificate: String, certificateExpiresAt: Int64) {
            self.certificate = certificate
            self.certificateExpiresAt = certificateExpiresAt
            super.init(label: .Married, sessionToken: sessionToken, kA: kA, kB: kB, keyPair: keyPair, keyPairExpiresAt: keyPairExpiresAt)
        }

        override func asDictionary() -> [String: AnyObject] {
            var d = super.asDictionary()
            d["certificate"] = certificate
            d["certificateExpiresAt"] = NSNumber(longLong: certificateExpiresAt)
            return d
        }

        func isCertificateExpired(now: Int64) -> Bool {
            return certificateExpiresAt < now
        }

        func withoutKeyPair() -> FirefoxAccountState.CohabitingWithoutKeyPair {
            let newState = FirefoxAccountState.CohabitingWithoutKeyPair(sessionToken: sessionToken,
                kA: kA, kB: kB)
            return newState
        }

        func withoutCertificate() -> FirefoxAccountState.Cohabiting {
            let newState = FirefoxAccountState.Cohabiting(sessionToken: sessionToken,
                kA: kA, kB: kB,
                keyPair: keyPair, keyPairExpiresAt: keyPairExpiresAt)
            return newState
        }
    }

    public class Doghouse: FirefoxAccountState {
        public init() {
            super.init(label: .Doghouse, verified: false)
        }

        override func getActionNeeded() -> FirefoxAccountActionNeeded {
            return .NeedsUpgrade
        }
    }

    class func fromDictionary(dictionary: [String: AnyObject]) -> FirefoxAccountState? {
        if let version = dictionary["version"] as? Int {
            if version == 1 {
                return FirefoxAccountState.fromDictionaryV1(dictionary)
            }
        }
        return nil
    }

    private class func fromDictionaryV1(dictionary: [String: AnyObject]) -> FirefoxAccountState? {
        // Oh, for a proper monad.

        // TODO: throughout, even a semblance of error checking and input validation.
        if let label = dictionary["label"] as? String {
            if let label = FirefoxAccountStateLabel(rawValue: label) {
                switch label {
                case .Separated:
                    return Separated()

                case .Engaged:
                    let verified = dictionary["verified"] as Bool
                    let sessionToken = NSData(base16EncodedString: dictionary["sessionToken"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let keyFetchToken = NSData(base16EncodedString: dictionary["keyFetchToken"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let unwrapkB = NSData(base16EncodedString: dictionary["unwrapkB"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    return Engaged(verified: verified, sessionToken: sessionToken, keyFetchToken: keyFetchToken, unwrapkB: unwrapkB)

                case .CohabitingWithoutKeyPair:
                    let sessionToken = NSData(base16EncodedString: dictionary["sessionToken"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let kA = NSData(base16EncodedString: dictionary["kA"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let kB = NSData(base16EncodedString: dictionary["kB"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    return CohabitingWithoutKeyPair(sessionToken: sessionToken, kA: kA, kB: kB)

                case .Cohabiting:
                    let sessionToken = NSData(base16EncodedString: dictionary["sessionToken"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let kA = NSData(base16EncodedString: dictionary["kA"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let kB = NSData(base16EncodedString: dictionary["kB"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let keyPairExpiresAt = dictionary["keyPairExpiresAt"] as NSNumber
                    let keyPair = RSAKeyPair(JSONRepresentation: dictionary["keyPair"] as [String: AnyObject])
                    return Cohabiting(sessionToken: sessionToken, kA: kA, kB: kB,
                        keyPair: keyPair, keyPairExpiresAt: keyPairExpiresAt.longLongValue)

                case .Married:
                    let sessionToken = NSData(base16EncodedString: dictionary["sessionToken"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let kA = NSData(base16EncodedString: dictionary["kA"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let kB = NSData(base16EncodedString: dictionary["kB"] as String, options: NSDataBase16DecodingOptions.allZeros)
                    let keyPair = RSAKeyPair(JSONRepresentation: dictionary["keyPair"] as [String: AnyObject])
                    let keyPairExpiresAt = dictionary["keyPairExpiresAt"] as NSNumber
                    let certificate = dictionary["certificate"] as String
                    let certificateExpiresAt = dictionary["certificateExpiresAt"] as NSNumber
                    return Married(sessionToken: sessionToken, kA: kA, kB: kB,
                        keyPair: keyPair, keyPairExpiresAt: keyPairExpiresAt.longLongValue,
                        certificate: certificate, certificateExpiresAt: certificateExpiresAt.longLongValue)

                case .Doghouse:
                    return Doghouse()
                }
            }
        }
        return nil
    }
}
