//
//  SQLDataTypeDateTests.swift
//  FreeTDSKit
//
//  Created by David Oliver on 2/10/25.
//
// Copyright (c) 2025 oli/wonders & David Oliver
//
//  Licensed under the MIT License.
//
//  The full text of the license can be found in the file named LICENSE.

import CFreeTDS
import Testing
import XCTest

@testable import FreeTDSKit

@Suite("Date/Time SQLDataType Tests") struct SQLDataTypeDateTests {

    
    @Test
    func tDSTime() {
        let time = TDSTime(hour: 12, minute: 30, second: 45)
        #expect(time.hour == 12)
        #expect(time.minute == 30)
        #expect(time.second == 45)
        #expect(time.debugDescription == "12:30:45")
    }
    
    @Test("TDSNullTime Test")
    func tDSTimeNullInitialization() {
        let time: TDSTime? = nil
        #expect(time == nil)
    }

    
    @Test
    func tDSDateInitialization() {
        let date = TDSDate(day: 28, month: 12, year: 2024)
        #expect(date.day == 28)
        #expect(date.month == 12)
        #expect(date.year == 2024)
        #expect(date.debugDescription == "12 28, 2024")
    }

    @Test
    func dateEdgeCases() {
        // Test year boundaries
        let dates = [
            "1753-01-01",  // SQL Server minimum date
            "9999-12-31",  // SQL Server maximum date
            "2000-02-29",  // Leap year
            "2100-02-28",  // Non-leap century year
        ]

        for dateStr in dates {
            let cString = dateStr.cString(using: .utf8)!
            let sqlType = determineSQLType(cString, columnType: 40)
            guard case let .date(value) = sqlType else {
                Issue.record("Failed to parse date: \(dateStr)")
                continue
            }

            let parts = dateStr.split(separator: "-").map { Int($0)! }
            #expect(value.year == parts[0])
            #expect(value.month == parts[1])
            #expect(value.day == parts[2])
        }
    }
    
    
    @Test
    func tDSTimestampInitialization() {
        let date = TDSDate(day: 28, month: 12, year: 2024)
        let timestamp = TDSDateTime(
            date: date, hour: 14, minute: 45, second: 30, fractionalSecond: 123)
        #expect(timestamp.date == date)
        #expect(timestamp.hour == 14)
        #expect(timestamp.minute == 45)
        #expect(timestamp.second == 30)
        #expect(timestamp.fractionalSecond == 123)
        #expect(timestamp.debugDescription == "12 28, 2024, 14:45:30.123")
    }

    @Test
    func determineSmallDateTime() {
        let cString: [CChar] = "2024-12-28 14:45".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 58)  // SmallDateTime type
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
    func determineDateTime() {
        let cString: [CChar] = "2024-12-28 14:45:30".cString(using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 61)  // DateTime type

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
    func determineDateTime2() {
        let cString: [CChar] = "2024-12-28 14:45:30.123456".cString(
            using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 42)  // DateTime2 type

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
    func determineDateTimeOffset() {
        let cString: [CChar] = "2024-12-28 14:45:30 +05:00".cString(
            using: .utf8)!
        let sqlType = determineSQLType(cString, columnType: 43)  // DateTimeOffset type

        if case let .datetimeoffset(value) = sqlType {
            #expect(value.date.year == 2024)
            #expect(value.date.month == 12)
            #expect(value.date.day == 28)
            #expect(value.time.hour == 14)
            #expect(value.time.minute == 45)
            #expect(value.time.second == 30)

            // Validate offset
            #expect(value.offset == 300)  // 300 minutes for +05:00

            let hours = value.offset / 60
            let minutes = abs(value.offset % 60)
            let sign = value.offset >= 0 ? "+" : "-"
            let offsetString = String(
                format: "\(sign)%02d:%02d", abs(hours), minutes)
            #expect(offsetString == "+05:00")
        } else {
            Issue.record("Expected SQLDataType.datetimeOffset")
        }
    }

    
}
