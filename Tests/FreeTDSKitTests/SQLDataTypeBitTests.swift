//
//  SQLDataTypeBitTests.swift
//  FreeTDSKit
//
//  Created by David Oliver on 2/10/25.
//


import CFreeTDS
import Testing

@testable import FreeTDSKit

@Suite("SQLDataType Bit Tests") struct SQLDataTypeBitTests {
    
    @Test("Test bit true value as 1")
    func testBitTrueAsOne() {
        let cString: [CChar] = "1".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBBIT)
        if case let .bit(value) = sqlType {
            #expect(value == true)
        } else {
            Issue.record("Expected SQLDataType.bit with true value")
        }
    }
    
    @Test("Test bit false value as 0")
    func testBitFalseAsZero() {
        let cString: [CChar] = "0".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBBIT)
        if case let .bit(value) = sqlType {
            #expect(value == false)
        } else {
            Issue.record("Expected SQLDataType.bit with false value")
        }
    }
    
    @Test("Test bit true as string")
    func testBitTrueAsString() {
        let cString: [CChar] = "true".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBBIT)
        if case let .bit(value) = sqlType {
            #expect(value == true)
        } else {
            Issue.record("Expected SQLDataType.bit with true value")
        }
    }
    
    @Test("Test bit false as string")
    func testBitFalseAsString() {
        let cString: [CChar] = "false".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBBIT)
        if case let .bit(value) = sqlType {
            #expect(value == false)
        } else {
            Issue.record("Expected SQLDataType.bit with false value")
        }
    }
    
    @Test("Test bit invalid value")
    func testBitInvalidValue() {
        let cString: [CChar] = "invalid".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBBIT)
        if case .null = sqlType {
            // Success - invalid value should return null
        } else {
            Issue.record("Expected SQLDataType.null for invalid bit value")
        }
    }
    
    @Test("Test bit value access through SQLResult")
    func testBitValueAccess() {
        let result = SQLResult(
            columns: ["Flag"],
            rows: [
                ["Flag": .bit(true)],
                ["Flag": .bit(false)],
                ["Flag": .null]
            ],
            affectedRows: 3
        )
        
        #expect(result[0, "Flag"]?.bool == true)
        #expect(result[1, "Flag"]?.bool == false)
        #expect(result[2, "Flag"]?.bool == nil)
    }
    
    @Test("Test bit description formatting")
    func testBitDescription() {
        let result = SQLResult(
            columns: ["Flag"],
            rows: [["Flag": .bit(true)]],
            affectedRows: 1
        )
        
        #expect(result[0, "Flag"]?.description == "true")
    }
}
