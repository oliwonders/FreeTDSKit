// Copyright (c) 2025 oli/wonders & David Oliver
//
//  Licensed under the MIT License.
//
//  The full text of the license can be found in the file named LICENSE.

import XCTest
import CFreeTDS
@testable import FreeTDSKit
import Testing

@Suite("SQLDataType Tests") struct SQLDataTypeTests {

    @Test("Test uniqueidentifier")
    func testTDSUniqueIdentifierInitialization() {
        let cString: [CChar] = "354E427F-F042-445B-A9F0-E19540E036B9".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 36) // SmallMoney type
        if case let .uniqueidentifier(value) = sqlType {
            #expect(value == UUID(uuidString: "354E427F-F042-445B-A9F0-E19540E036B9"))
        } else {
            Issue.record("Expected SQLDataType.uniqueidentifier")
        }
    }
    
    @Test("TDS Time Test")
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
    func testDetermineSQLTypeWithMoney() {
        let cString: [CChar] = "12345.67".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 60) // Money type
        if case let .money(value) = sqlType {
            #expect(value == Decimal(12345.67))
        } else {
            Issue.record("Expected SQLDataType.money")
        }
    }

    @Test
    func testDetermineSQLTypeWithSmallMoney() {
        let cString: [CChar] = "1234.56".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBMONEY) // SmallMoney type
        if case let .money(value) = sqlType {
            #expect(value == Decimal(1234.56).rounded(scale: 2))
        } else {
            Issue.record("Expected SQLDataType.smallMoney")
        }
    }

    @Test
    func testDetermineSQLTypeWithNChar() {
        let cString: [CChar] = "TestChar".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 239) // NChar type
        if case let .nchar(value) = sqlType {
            #expect(value == "TestChar")
        } else {
            Issue.record("Expected SQLDataType.nchar")
        }
    }

    @Test
    func testDetermineSQLTypeWithNVarChar() {
        let cString: [CChar] = "TestVariableChar".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBNVARCHAR) // NVarChar type
        if case let .nvarchar(value) = sqlType {
            #expect(value == "TestVariableChar")
        } else {
            Issue.record("Expected SQLDataType.nvarchar")
        }
    }

    @Test
    func testDetermineSQLTypeWithId() {
        let cString: [CChar] = "42".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: SYBINT4) // Integer type for Id
        if case let .integer(value) = sqlType {
            #expect(value == 42)
        } else {
            Issue.record("Expected SQLDataType.integer for Id")
        }
    }
    @Test
    func testDetermineSQLTypeWithSmallDateTime() {
        let cString: [CChar] = "2024-12-28 14:45".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 58) // SmallDateTime type
        if case let .smalldatetime(value) = sqlType {
            #expect(value.date.year == 2024)
            #expect(value.date.month == 12)
            #expect(value.date.day == 28)
            #expect(value.hour == 14)
            #expect(value.minute == 45)
        } else {
            Issue.record("Expected SQLDataType.smalldatetime")
        }
    }
    
    @Test
    func testDetermineSQLTypeWithDateTime() {
        let cString: [CChar] = "2024-12-28 14:45:30".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 61) // DateTime type

        if case let .datetime(value) = sqlType {
            #expect(value.date.year == 2024)
            #expect(value.date.month == 12)
            #expect(value.date.day == 28)
            #expect(value.hour == 14)
            #expect(value.minute == 45)
            #expect(value.second == 30)
        } else {
            Issue.record("Expected SQLDataType.datetime")
        }
    }
    
    @Test
    func testDetermineSQLTypeWithDateTime2() {
        let cString: [CChar] = "2024-12-28 14:45:30.123456".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 42) // DateTime2 type

        if case let .datetime2(value) = sqlType {
            #expect(value.date.year == 2024)
            #expect(value.date.month == 12)
            #expect(value.date.day == 28)
            #expect(value.hour == 14)
            #expect(value.minute == 45)
            #expect(value.second == 30)
            #expect(value.fractionalSecond == 123456)
        } else {
            Issue.record("Expected SQLDataType.datetime2")
        }
    }

    
    @Test
    func testDetermineSQLTypeWithDateTimeOffset() {
        let cString: [CChar] = "2024-12-28 14:45:30 +05:00".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 43) // DateTimeOffset type

        if case let .datetimeoffset(value) = sqlType {
            #expect(value.date.year == 2024)
            #expect(value.date.month == 12)
            #expect(value.date.day == 28)
            #expect(value.time.hour == 14)
            #expect(value.time.minute == 45)
            #expect(value.time.second == 30)
            
            // Validate offset
            #expect(value.offset == 300) // 300 minutes for +05:00
            
            let hours = value.offset / 60
            let minutes = abs(value.offset % 60)
            let sign = value.offset >= 0 ? "+" : "-"
            let offsetString = String(format: "\(sign)%02d:%02d", abs(hours), minutes)
            #expect(offsetString == "+05:00")
        } else {
            Issue.record("Expected SQLDataType.datetimeOffset")
        }
    }}
