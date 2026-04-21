//
//  PushManagerTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 21/04/2026.
//

import Testing
import Foundation
@testable import Listener

@Suite("PushManager")
struct PushManagerTests {

    @Test func hexStringConvertsTokenDataCorrectly() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0xFF])
        let hex = deviceTokenHexString(from: data)
        #expect(hex == "deadbeef0001ff")
    }

    @Test func hexStringReturnsEmptyForEmptyData() {
        let hex = deviceTokenHexString(from: Data())
        #expect(hex == "")
    }

    @Test func hexStringProducesLowercaseHex() {
        let data = Data([0xAB, 0xCD, 0xEF])
        let hex = deviceTokenHexString(from: data)
        #expect(hex == "abcdef")
    }
}
