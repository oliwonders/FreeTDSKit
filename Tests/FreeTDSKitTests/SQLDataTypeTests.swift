//
//  SQLDataTypeTests.swift
//  FreeTDSKit
//
//  Created by David Oliver on 1/17/25.
//


import XCTest
import CFreeTDS
@testable import FreeTDSKit
import Testing


@Test
func testTDSTimeInitialization() {
    let time = TDSTime(hour: 12, minute: 30, second: 45)
    #expect(time.hour == 12)
    #expect(time.minute == 30)
    #expect(time.second == 45)
    #expect(time.debugDescription == "12:30:45")
}

@Test
func testTDSDateInitialization() {
    let date = TDSDate(day: 28, month: 12, year: 2024)
    #expect(date.day == 28)
    #expect(date.month == 12)
    #expect(date.year == 2024)
    #expect(date.debugDescription == "12 28, 2024")
}

@Test
func testTDSTimestampInitialization() {
    let date = TDSDate(day: 28, month: 12, year: 2024)
    let timestamp = TDSTimestamp(date: date, hour: 14, minute: 45, second: 30, fractionalSecond: 123)
    #expect(timestamp.date == date)
    #expect(timestamp.hour == 14)
    #expect(timestamp.minute == 45)
    #expect(timestamp.second == 30)
    #expect(timestamp.fractionalSecond == 123)
    #expect(timestamp.debugDescription == "12 28, 2024, 14:45:30.123")
}

@Test
func testSQLDataTypeChar() {
    let sqlType = SQLDataType.char("Test String")
    if case let .char(value) = sqlType {
        #expect(value == "Test String")
    } else {
        Issue.record("Expected SQLDataType.char")
    }
}

// Test for SQLDataType.numeric
@Test
func testSQLDataTypeNumeric() {
    let sqlType = SQLDataType.numeric(Decimal(1234.56))
    if case let .numeric(value) = sqlType {
        #expect(value == Decimal(1234.56))
    } else {
        Issue.record("Expected SQLDataType.numeric")
    }
}

// Test for determineSQLType
@Test
func testDetermineSQLTypeWithChar() {
    let cString: [CChar] = "Test Value".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBCHAR)
    if case let .char(value) = sqlType {
        #expect(value == "Test Value")
    } else {
        Issue.record("Expected SQLDataType.char")
    }
}

@Test
func testDetermineSQLTypeWithDate() {
    let cString: [CChar] = "2024-12-28".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: 40)
    if case let .date(date) = sqlType {
        #expect(date.day == 28)
        #expect(date.month == 12)
        #expect(date.year == 2024)
    } else {
        Issue.record("Expected SQLDataType.date")
    }
}

@Test
func testDetermineSQLTypeWithSpatial() {
    let cString: [CChar] = "POINT(-122.335167 47.608013)".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBGEOGRAPHY)
    if case let .spatial(wkt) = sqlType {
        #expect(wkt.value == "POINT(-122.335167 47.608013)")
    } else {
        Issue.record("Expected SQLDataType.spatial")
    }
}

@Test
func testDetermineSQLTypeWithTinyInt() {
    let cString: [CChar] = "255".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBINT1)
    if case let .tinyInt(value) = sqlType {
        #expect(value == 255)
    } else {
        Issue.record("Expected SQLDataType.tinyInt")
    }
}

@Test
func testDetermineSQLTypeWithSmallInt() {
    let cString: [CChar] = "32767".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBINT2)
    if case let .smallInt(value) = sqlType {
        #expect(value == 32767)
    } else {
        Issue.record("Expected SQLDataType.smallInt")
    }
}

@Test
func testDetermineSQLTypeWithInteger() {
    let cString: [CChar] = "12345".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBINT4)
    if case let .integer(value) = sqlType {
        #expect(value == 12345)
    } else {
        Issue.record("Expected SQLDataType.integer")
    }
}

@Test
func testDetermineSQLTypeWithBigInt() {
    let cString: [CChar] = "9223372036854775807".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBINT8)
    if case let .bigInt(value) = sqlType {
        #expect(value == 9223372036854775807)
    } else {
        Issue.record("Expected SQLDataType.bigInt")
    }
}

@Test
func testDetermineSQLTypeWithDecimal() {
    let cString: [CChar] = "12345.67".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: 106) // Decimal type
    if case let .decimal(value) = sqlType {
        #expect(value == Decimal(12345.67))
    } else {
        Issue.record("Expected SQLDataType.decimal")
    }
}

@Test
func testDetermineSQLTypeWithReal() {
    let cString: [CChar] = "3.1415".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBREAL)
    if case let .real(value) = sqlType {
        #expect(value == 3.1415)
    } else {
        Issue.record("Expected SQLDataType.real")
    }
}

@Test
func testDetermineSQLTypeWithDouble() {
    let cString: [CChar] = "2.718281828".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBFLT8)
    if case let .double(value) = sqlType {
        #expect(value == 2.718281828)
    } else {
        Issue.record("Expected SQLDataType.double")
    }
}

@Test
func testDetermineSQLTypeWithBit() {
    let cString: [CChar] = "1".cString(using: .utf8)!
    let sqlType = determineSQLType(cString, columnType: SYBBIT)
    if case let .bit(value) = sqlType {
        #expect(value == true)
    } else {
        Issue.record("Expected SQLDataType.bit")
    }
}

@Test
func testDetermineSQLTypeWithBinary() {
    let binaryData = Data([0x01, 0x02, 0x03, 0x04])
    let binaryCString = binaryData.withUnsafeBytes { buffer in
        buffer.baseAddress!.bindMemory(to: CChar.self, capacity: binaryData.count)
    }
    let sqlType = determineSQLType(binaryCString, columnType: SYBBINARY)
    if case let .binary(value) = sqlType {
        #expect(value == binaryData)
    } else {
        Issue.record("Expected SQLDataType.binary")
    }
}
