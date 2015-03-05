/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import FxA
import XCTest

class FxALoginStateMachineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        self.continueAfterFailure = false
    }

    lazy var marriedState: FirefoxAccountState.Married = {
        FirefoxAccountState.Married(sessionToken: NSData.randomOfLength(32)!,
            kA: NSData.randomOfLength(32)!, kB: NSData.randomOfLength(32)!,
            keyPair: RSAKeyPair.generateKeyPairWithModulusSize(512), keyPairExpiresAt: OneMonthInMilliseconds,
            certificate: "", certificateExpiresAt: OneWeekInMilliseconds)
    }()

    func withLoginStateMachine(callback: FxALoginStateMachine -> Void) {
        let client = MockFxAClient10()
        let stateMachine = FxALoginStateMachine(client: client)
        callback(stateMachine)
    }

    func testAdvanceWhenInteractionRequired() {
        // The simple cases are when we get to Separated and Doghouse.  There's nothing to do!
        // We just have to wait for user interaction.
        for state in [FirefoxAccountState.Separated(), FirefoxAccountState.Doghouse()] {
            let e = expectationWithDescription("Wait for login state machine.")
            withLoginStateMachine { stateMachine in
                stateMachine.advanceFromState(state, now: 0) { error, newState in
                    XCTAssertNil(error)
                    XCTAssertEqual(newState.label, state.label)
                    e.fulfill()
                }
            }
        }
        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testAdvanceFromMarried() {
        // Advancing from a healthy Married state is easy.
        let e1 = expectationWithDescription("Wait for login state machine.")
        withLoginStateMachine { stateMachine in
            stateMachine.advanceFromState(self.marriedState, now: 0) { error, newState in
                XCTAssertNil(error)
                XCTAssertEqual(newState.label, FirefoxAccountStateLabel.Married)
                e1.fulfill()
            }
        }

        // Advancing from a Married state with an expired certificate gets back to Married.
        let e2 = expectationWithDescription("Wait for login state machine.")
        var now = OneWeekInMilliseconds + 1
        withLoginStateMachine { stateMachine in
            stateMachine.advanceFromState(self.marriedState, now: now) { error, newState in
                XCTAssertNil(error)
                XCTAssertEqual(newState.label, FirefoxAccountStateLabel.Married)
                let newState = newState as FirefoxAccountState.Married
                // We have a fresh certificate.
                XCTAssertLessThan(self.marriedState.certificateExpiresAt, now)
                XCTAssertGreaterThan(newState.certificateExpiresAt, now)
                e2.fulfill()
            }
        }

        // Advancing from a Married state with an expired keypair gets back to Married too.
        let e3 = expectationWithDescription("Wait for login state machine.")
        now = OneMonthInMilliseconds + 1
        withLoginStateMachine { stateMachine in
            stateMachine.advanceFromState(self.marriedState, now: now) { error, newState in
                XCTAssertNil(error)
                XCTAssertEqual(newState.label, FirefoxAccountStateLabel.Married)
                let newState = newState as FirefoxAccountState.Married
                // We have a fresh key pair (and certificate, but we don't verify that).
                XCTAssertLessThan(self.marriedState.keyPairExpiresAt, now)
                XCTAssertGreaterThan(newState.keyPairExpiresAt, now)
                e3.fulfill()
            }
        }
        waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testAdvanceFromEngaged() {
        // Need the client to peek at kA and wrapkB.
        let client = MockFxAClient10()
        let stateMachine = FxALoginStateMachine(client: client)

        // Advancing from an Engaged state correctly XORs the keys.
        let unwrapkB = client.wrapkB // This way we get all 0s, which is easy to test.
        let engagedState = FirefoxAccountState.Engaged(verified: true,
            sessionToken: NSData.randomOfLength(32)!, keyFetchToken: NSData.randomOfLength(32)!,
            unwrapkB: unwrapkB)

        let e1 = expectationWithDescription("Wait for login state machine.")
        stateMachine.advanceFromState(engagedState, now: 0) { error, newState in
            XCTAssertNil(error)
            XCTAssertEqual(newState.label, FirefoxAccountStateLabel.Married)
            let newState = newState as FirefoxAccountState.Married
            // We get kA from the client directly.
            XCTAssertEqual(newState.kA.hexEncodedString, client.kA.hexEncodedString)
            // We unwrap kB by XORing.  The result is KeyLength (32) 0s.
            XCTAssertEqual(newState.kB.hexEncodedString, "0000000000000000000000000000000000000000000000000000000000000000")
            e1.fulfill()
        }
        waitForExpectationsWithTimeout(10, handler: nil)
    }
}
