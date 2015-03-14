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

    func testLive() {
        let expectation = expectationWithDescription("Waiting on value.")
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

        // TODO: why does this take 20 seconds to time out, when the 'else' block fulfills?
        waitForExpectationsWithTimeout(20) { (error) in
            XCTAssertNil(error, "\(error)")
        }
    }
}