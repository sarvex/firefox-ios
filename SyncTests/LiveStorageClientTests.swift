/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import FxA
import Shared
import XCTest

class LiveStorageClientTests : LiveAccountTest {
    // This is so complicated because all of the withFoo test functions take completion handlers
    // rather than returning a Deferred.
    func getToken() -> Deferred<Result<TokenServerToken>> {
        let deferred = Deferred<Result<TokenServerToken>>()

        let audience = TokenServerClient.getAudienceForURL(ProductionSync15Configuration().tokenServerEndpointURL)
        withCertificate { expectation, emailUTF8, keyPair, certificate in
            let assertion = JSONWebTokenUtils.createAssertionWithPrivateKeyToSignWith(keyPair.privateKey,
                certificate: certificate, audience: audience)

            let client = TokenServerClient()

            client.token(assertion).upon({
                result in
                println("Assertion \(assertion), got \(result)")
                deferred.fill(result)
            })
        }

        return deferred
    }

    func getToken(state: FirefoxAccountState) -> Deferred<Result<TokenServerToken>> {
        if let married = state as? FirefoxAccountState.Married {
            let audience = TokenServerClient.getAudienceForURL(ProductionSync15Configuration().tokenServerEndpointURL)
            let clientState = FxAClient10.computeClientState(married.kB)
            let client = TokenServerClient()
            return client.token(married.generateAssertionForAudience(audience), clientState: clientState)
        } else {
            return Deferred(value: Result(failure: NSError(domain: "foo", code: 0, userInfo: nil)))
        }
    }

    func getKeys(married: FirefoxAccountState.Married, token: TokenServerToken) -> Deferred<Result<Record<KeysPayload>>> {
        let endpoint = token.api_endpoint
        XCTAssertTrue(endpoint.rangeOfString("services.mozilla.com") != nil, "We got a Sync server.")

        let cryptoURI = NSURL(string: endpoint + "/storage/crypto/")
        let authorizer: Authorizer = {
            (r: NSMutableURLRequest) -> NSMutableURLRequest in
            let helper = HawkHelper(id: token.id, key: token.key.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
            r.addValue(helper.getAuthorizationValueFor(r), forHTTPHeaderField: "Authorization")
            return r
        }

        let keyBundle: KeyBundle = KeyBundle.fromKB(married.kB)
        let keysFactory: (String) -> KeysPayload? = Keys(defaultBundle: keyBundle).factory("keys")

        let workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        let resultQueue = dispatch_get_main_queue()
        let keysFetch = Sync15StorageClient(serverURI: cryptoURI!, authorizer: authorizer, factory: keysFactory, workQueue: workQueue, resultQueue: resultQueue)

        let response = keysFetch.get("keys")
        return response.map({
            res in
            if let r = res.successValue {
                return Result(success: r.value)
            }
            return Result(failure: NSError(domain: "foo", code: 0, userInfo: nil))
        })
    }

    func testLive() {
        let expectation = expectationWithDescription("Waiting on value.")

        // client: mgWl22CIzHiE
        let user = "holygoat+permatest@gmail.com"
        let state = withState(user, password: user)

        let token = state.bind {
            (stateResult: Result<FirefoxAccountState>) -> Deferred<Result<TokenServerToken>> in
            if let s = stateResult.successValue {
                return self.getToken(s)
            }
            return Deferred(value: Result(failure: stateResult.failureValue!))
        }

        if let married = state.value.successValue as? FirefoxAccountState.Married {
            let keys: Deferred<Result<Record<KeysPayload>>> = token.bind {
                tokenResult in
                if let token = tokenResult.successValue {
                    return self.getKeys(married, token: token)
                }
                return Deferred(value: Result(failure: NSError(domain: "foo", code: 0, userInfo: nil)))
            }
            keys.upon({
                res in
                if let rec = res.successValue {
                    XCTAssert(rec.id == "keys", "GUID is correct.")
                    XCTAssert(rec.modified > 1000, "modified is sane.")
                    println("Body: \(rec.payload)")
                } else {
                    XCTFail("No key record.")
                }
                expectation.fulfill()
            })
        } else {
            XCTFail("Not in state Married.")
            return
        }
        /*
        token.upon( {
            tokenResult in
            if let token = tokenResult.successValue {
                let endpoint = token.api_endpoint
                XCTAssertTrue(endpoint.rangeOfString("services.mozilla.com") != nil, "We got a Sync server.")
                let cryptoURI = NSURL(string: endpoint + "/storage/crypto/")
                let authorizer: Authorizer = {
                    (r: NSMutableURLRequest) -> NSMutableURLRequest in
                    let helper = HawkHelper(id: token.id, key: token.key.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
                    r.addValue(helper.getAuthorizationValueFor(r), forHTTPHeaderField: "Authorization")
                    return r
                }

                if let married = state.value.successValue as? FirefoxAccountState.Married {
                let keyBundle: KeyBundle = KeyBundle.fromKB(married.kB)
                let keysFactory: (String) -> KeysPayload? = Keys(defaultBundle: keyBundle).factory("keys")

                let workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                let resultQueue = dispatch_get_main_queue()
                let keysFetch = Sync15StorageClient(serverURI: cryptoURI!, authorizer: authorizer, factory: keysFactory, workQueue: workQueue, resultQueue: resultQueue)

                    // client: mgWl22CIzHiE
                let deferred = keysFetch.get("keys")
                deferred.upon({ result in
                    println("Here: \(result)")
                    expectation.fulfill()
                })
                } else {
                    XCTFail("Not Married.")
                    expectation.fulfill()
                }
            } else {
                XCTAssertNil(tokenResult.failureValue as? NSError)
                expectation.fulfill()
            }

        })
*/
    // TODO: why does this take 20 seconds to time out, when the 'else' block fulfills?
    waitForExpectationsWithTimeout(20) { (error) in
    XCTAssertNil(error, "\(error)")
    }
        /*
        getToken().upon({
            result in
            if let token = result.successValue {
                let authorizer: Authorizer = {
                    (r: NSMutableURLRequest) -> NSMutableURLRequest in
                    r.addValue(token.key, forHTTPHeaderField: "Authorization")
                    return r
                }

                let factory: (String) -> CleartextPayloadJSON? = {
                    (s: String) -> CleartextPayloadJSON? in
                    return CleartextPayloadJSON(s)
                }

                let prodURI = NSURL(string: token.api_endpoint)

                println("URI is \(prodURI)")
                // TODO: storage URL

                let workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                let resultQueue = dispatch_get_main_queue()
                let meta = Sync15StorageClient(serverURI: prodURI!, authorizer: authorizer, factory: factory, workQueue: workQueue, resultQueue: resultQueue)

                let deferred = meta.get("global")
                deferred.upon({ result in
                    println("Here: \(result)")
                    //expectation.fulfill()
                })
            } else {
                println("No token.")
                expectation.fulfill()
            }
            })
*/
    }
}