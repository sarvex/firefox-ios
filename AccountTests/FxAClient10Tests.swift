/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import FxA
import UIKit
import XCTest

class FxAClient10Tests: LiveAccountTest {
    func testUnwrapKey() {
        let stretchedPW = "e4e8889bd8bd61ad6de6b95c059d56e7b50dacdaf62bd84644af7e2add84345d".hexDecodedData
        let unwrapKey = FxAClient10.computeUnwrapKey(stretchedPW)
        XCTAssertEqual(unwrapKey.hexEncodedString, "de6a2648b78284fcb9ffa81ba95803309cfba7af583c01a8a1a63e567234dd28")
    }

    func testClientState() {
        let kB = "fd5c747806c07ce0b9d69dcfea144663e630b65ec4963596a22f24910d7dd15d".hexDecodedData
        let clientState = FxAClient10.computeClientState(kB)!
        XCTAssertEqual(clientState, "6ae94683571c7a7c54dab4700aa3995f")
    }

    func testLoginSuccess() {
        withVerifiedAccount { emailUTF8, quickStretchedPW in
            let e = self.expectationWithDescription("")

            let client = FxAClient10()
            let result = client.login(emailUTF8, quickStretchedPW: quickStretchedPW, getKeys: true)
            result.upon { result in
                if let response = result.successValue {
                    XCTAssertNotNil(response.uid)
                    XCTAssertEqual(response.verified, true)
                    XCTAssertNotNil(response.sessionToken)
                    XCTAssertNotNil(response.keyFetchToken)
                } else {
                    let error = result.failureValue as NSError
                    XCTAssertNil(error)
                }
                e.fulfill()
            }
        }
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testLoginFailure() {
        withVerifiedAccount { emailUTF8, _ in
            let e = self.expectationWithDescription("")

            let badPassword = FxAClient10.quickStretchPW(emailUTF8, password: "BAD PASSWORD".utf8EncodedData!)

            let client = FxAClient10()
            let result = client.login(emailUTF8, quickStretchedPW: badPassword, getKeys: true)
            result.upon { result in
                if let response = result.successValue {
                    XCTFail("Got response: \(response)")
                } else {
                    let error = result.failureValue as NSError
                    XCTAssertEqual(error.code, 103) // Incorrect password.
                }
                e.fulfill()
            }
        }
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testKeysSuccess() {
        withVerifiedAccount { emailUTF8, quickStretchedPW in
            let e = self.expectationWithDescription("")

            let client = FxAClient10()
            let login: Deferred<Result<FxALoginResponse>> = client.login(emailUTF8, quickStretchedPW: quickStretchedPW, getKeys: true)
            let keys: Deferred<Result<FxAKeysResponse>> = login.bind { (result: Result<FxALoginResponse>) in
                switch result {
                case let .Failure(error):
                    return Deferred(value: .Failure(error))
                case let .Success(loginResponse):
                    return client.keys(loginResponse.value.keyFetchToken)
                }
            }
            keys.upon { result in
                if let response = result.successValue {
                    XCTAssertEqual(32, response.kA.length)
                    XCTAssertEqual(32, response.wrapkB.length)
                } else {
                    let error = result.failureValue as NSError
                    XCTAssertNil(error)
                }
                e.fulfill()
            }
        }
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testSignSuccess() {
        withVerifiedAccount { emailUTF8, quickStretchedPW in
            let e = self.expectationWithDescription("")

            let client = FxAClient10()
            let login: Deferred<Result<FxALoginResponse>> = client.login(emailUTF8, quickStretchedPW: quickStretchedPW, getKeys: true)
            let sign: Deferred<Result<FxASignResponse>> = login.bind { (result: Result<FxALoginResponse>) in
                switch result {
                case let .Failure(error):
                    return Deferred(value: .Failure(error))
                case let .Success(loginResponse):
                    let keyPair = RSAKeyPair.generateKeyPairWithModulusSize(1024)
                    return client.sign(loginResponse.value.sessionToken, publicKey: keyPair.publicKey)
                }
            }
            sign.upon { result in
                if let response = result.successValue {
                    XCTAssertNotNil(response.certificate)
                    // A simple test that we got a reasonable certificate back.
                    XCTAssertEqual(3, response.certificate.componentsSeparatedByString(".").count)
                } else {
                    let error = result.failureValue as NSError
                    XCTAssertNil(error)
                }
                e.fulfill()
            }
        }
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testSync() {
        let e = self.expectationWithDescription("")
        let state = withState("testtesto@mockmyid.com", password: "testtesto@mockmyid.com")
        let token = state.bind { (stateResult: Result<FirefoxAccountState>) -> Deferred<Result<TokenServerToken>> in
            if let state = stateResult.successValue {
                if let married = state as? FirefoxAccountState.Married {
                    let audience = TokenServerClient.getAudienceForURL(ProductionSync15Configuration().tokenServerEndpointURL)
                    let clientState = FxAClient10.computeClientState(married.kB)
                    let client = TokenServerClient()
                    return client.token(married.generateAssertionForAudience(audience), clientState: clientState)
                } else {
                    return Deferred(value: Result(failure: NSError(domain: "foo", code: 0, userInfo: nil)))
                }
            } else {
                return Deferred(value: Result(failure: stateResult.failureValue!))
            }
        }
        token.upon { tokenResult in
            if let token = tokenResult.successValue {
                XCTAssertEqual("", token.api_endpoint)
            } else {
                XCTAssertNil(tokenResult.failureValue as? NSError)
            }
            e.fulfill()
        }
        self.waitForExpectationsWithTimeout(10, handler: nil)
    }
}
