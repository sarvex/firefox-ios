/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import FxA

class TwoKeys {
    let KeyLength = 32

    let kA: NSData
    let wrapkB: NSData

    init?(kA: NSData, wrapkB: NSData) {
        self.kA = kA
        self.wrapkB = wrapkB
        // Swift is bonkers: it's not legal to return nil before assigning the members.
        // See the discussion at http://stackoverflow.com/q/26495586
        if kA.length != KeyLength {
            return nil
        }
        if wrapkB.length != KeyLength {
            return nil
        }
    }

    func unwrapkBWith(unwrapkB: NSData) -> NSData? {
        if unwrapkB.length != KeyLength {
            return nil
        }
        var kB = [UInt8](count: KeyLength, repeatedValue: 0)
        let wrapkBBytes = UnsafePointer<UInt8>(wrapkB.bytes)
        let unwrapkBBytes = UnsafePointer<UInt8>(unwrapkB.bytes)
        for i in 0..<KeyLength {
            kB[i] = unwrapkBBytes[i] ^ wrapkBBytes[i]
        }
        return NSData(bytes: kB, length: KeyLength)
    }
}

struct CertificateAndExpiration {
    let certificate: String
    let expiresAt: Int64

    init(certificate: String, expiresAt: Int64) {
        self.certificate = certificate
        self.expiresAt = expiresAt
    }
}

struct KeyPairResult {
    let keyPair: KeyPair
    let expiresAt: Int64

    init(keyPair: KeyPair, expiresAt: Int64) {
        self.keyPair = keyPair
        self.expiresAt = expiresAt
    }
}

protocol FxALoginClient {
    func fetchSyncKeysWithKeyFetchToken(keyFetchToken: NSData, callback: (NSError?, TwoKeys!) -> Void) -> Void
    func generateKeyPairAt(now: Int64, callback: (NSError?, KeyPairResult!) -> Void) -> Void
    func signPublicKey(publicKey: PublicKey, withSessionToken: NSData, at now: Int64, callback: (NSError?, CertificateAndExpiration!) -> Void) -> Void
}

class FxALoginClient10: FxALoginClient {
    let client: FxAClient10

    init(client: FxAClient10) {
        self.client = client
    }

    func generateKeyPairAt(now: Int64, callback: (NSError?, KeyPairResult!) -> Void) -> Void {
        let result = KeyPairResult(keyPair: RSAKeyPair.generateKeyPairWithModulusSize(1024), expiresAt: now + OneMonthInMilliseconds)
        callback(nil, result)
    }

    func fetchSyncKeysWithKeyFetchToken(keyFetchToken: NSData, callback: (NSError?, TwoKeys!) -> Void) -> Void {
        client.keys(keyFetchToken).upon { keysResult in
            if let keysResponse = keysResult.successValue {
                callback(nil, TwoKeys(kA: keysResponse.kA, wrapkB: keysResponse.wrapkB)!)
            } else {
                callback(keysResult.failureValue as? NSError, nil)
            }
        }
    }

    func signPublicKey(publicKey: PublicKey, withSessionToken sessionToken: NSData, at now: Int64, callback: (NSError?, CertificateAndExpiration!) -> Void) -> Void {
        client.sign(sessionToken, publicKey: publicKey).upon { signResult in
            if let signResponse = signResult.successValue {
                callback(nil, CertificateAndExpiration(certificate: signResponse.certificate, expiresAt: now + OneDayInMilliseconds))
            } else {
                callback(signResult.failureValue as? NSError, nil)
            }
        }
    }
}

class MockFxAClient10: FxALoginClient {
    // Fixed per mock client, for testing.
    let kA = NSData.randomOfLength(32)!
    let wrapkB = NSData.randomOfLength(32)!

    func fetchSyncKeysWithKeyFetchToken(keyFetchToken: NSData, callback: (NSError?, TwoKeys!) -> Void) -> Void {
        if let twoKeys = TwoKeys(kA: kA, wrapkB: wrapkB) {
            callback(nil, twoKeys)
        } else {
            callback(NSError(domain: "org.mozilla", code: 1, userInfo: nil), nil)
        }
    }

    func generateKeyPairAt(now: Int64, callback: (NSError?, KeyPairResult!) -> Void) -> Void {
        let result = KeyPairResult(keyPair: RSAKeyPair.generateKeyPairWithModulusSize(512), expiresAt: now + OneMonthInMilliseconds)
        callback(nil, result)
    }

    func signPublicKey(publicKey: PublicKey, withSessionToken: NSData, at now: Int64, callback: (NSError?, CertificateAndExpiration!) -> Void) -> Void {
        // For testing purposes, generate a bogus certificate.
        let result = CertificateAndExpiration(certificate: "Certificate generated at \(now)", expiresAt: now + OneWeekInMilliseconds)
        callback(nil, result)
    }
}

class FxALoginStateMachine {
    let client: FxALoginClient

    init(client: FxALoginClient) {
        self.client = client
    }

    func advanceFromState(state: FirefoxAccountState, now: Int64, callback: (NSError?, FirefoxAccountState!) -> Void) {
        // keys are used as a set.
        var stateLabelsSeen = [FirefoxAccountStateLabel: Bool]()

        // Recursive anonymous functions are a little funky in Swift.  This may not be the cleanest way to do this, but it works.
        // The state machine is small enough that I'm not worried about recursion depth.
        var innerCallback: ((NSError?, FirefoxAccountState!) -> Void)! = nil
        innerCallback = { (error, nextState) in
            if error != nil {
                callback(error, nil)
                return
            }
            let labelAlreadySeen = stateLabelsSeen.updateValue(true, forKey: nextState.label) != nil
            if labelAlreadySeen {
                callback(nil, nextState)
                return
            }
            self.innerAdvanceFromState(nextState, now: now, callback: innerCallback)
        }

        innerAdvanceFromState(state, now: now, innerCallback)
    }

    private func innerAdvanceFromState(state: FirefoxAccountState, now: Int64, callback: (NSError?, FirefoxAccountState!) -> Void) {
        switch state.label {
        case .Married:
            let state = state as FirefoxAccountState.Married
            if state.isKeyPairExpired(now) {
                // We need a fresh key pair.
                callback(nil, state.withoutKeyPair())
                return
            }
            if state.isCertificateExpired(now) {
                // We need a fresh certificate.
                callback(nil, state.withoutCertificate())
                return
            }
            // Otherwise, roll on!
            callback(nil, state)

        case .Cohabiting:
            let state = state as FirefoxAccountState.Cohabiting
            client.signPublicKey(state.keyPair.publicKey, withSessionToken: state.sessionToken, at: now) { (error, result) in
                // XXX interrogate error to go to Separated state.  Or to get a fresh assertion.
                if error != nil {
                    callback(error, nil)
                    return
                }
                let newState = FirefoxAccountState.Married(sessionToken: state.sessionToken,
                    kA: state.kA, kB: state.kB,
                    keyPair: state.keyPair, keyPairExpiresAt: state.keyPairExpiresAt,
                    certificate: result.certificate, certificateExpiresAt: result.expiresAt)
                callback(nil, newState)
            }

        case .CohabitingWithoutKeyPair:
            let state = state as FirefoxAccountState.CohabitingWithoutKeyPair
            self.client.generateKeyPairAt(now) { (error, result) in
                if error != nil {
                    callback(error, nil)
                    return
                }
                let newState = FirefoxAccountState.Cohabiting(sessionToken: state.sessionToken,
                    kA: state.kA, kB: state.kB,
                    keyPair: result.keyPair, keyPairExpiresAt: result.expiresAt)
                callback(nil, newState)
            }

        case .Unverified, .Engaged:
            let state = state as FirefoxAccountState.ReadyForKeys
            client.fetchSyncKeysWithKeyFetchToken(state.keyFetchToken) { (error, twoKeys) in
                // XXX interrogate error to go to Separated state.
                // Or remain at current state, if Unverified.
                // XXX ensure that keyFetchToken is still valid!
                if error != nil {
                    callback(error, nil)
                    return
                }
                if let kB = twoKeys.unwrapkBWith(state.unwrapkB) {
                    let newState = FirefoxAccountState.CohabitingWithoutKeyPair(sessionToken: state.sessionToken,
                        kA: twoKeys.kA, kB: kB)
                    callback(nil, newState)
                } else {
                    // XXX what to do here?
                    callback(NSError(domain: "org.mozilla", code: 1, userInfo: nil), nil)
                }
            }

        case .Separated, .Doghouse:
            // We can not advance from the separated state (we need user input) or the doghouse (we need a client upgrade).
            callback(nil, state)
        }
    }
}
