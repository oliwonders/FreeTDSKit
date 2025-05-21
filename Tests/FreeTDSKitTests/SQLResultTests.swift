//
//  Test.swift
//  FreeTDSKit
//
//  Created by David Oliver on 1/27/25.
//
import Foundation
import CFreeTDS
@testable import FreeTDSKit
import Testing

@Suite("SQLResult Tests") struct SQLResultTests {

    @Test func afectedRowsIsPopulated() async throws {
        let result = SQLResult(
            columns: ["Id", "Name", "Value"],
            rows: [
                ["Id": .integer(1), "Name": .varchar("Test 1"), "Value": .money(123.45)],
                ["Id": .integer(2), "Name": .varchar("Test 2"), "Value": .money(678.90)]
            ],
            affectedRows: 2
        )
        #expect(result.affectedRows == 2)
    }
    
    @Test
    func columnsIsPopulated() async throws {
        let result = SQLResult(
            columns: ["Id", "Name", "Value"],
            rows: [
                ["Id": .integer(1), "Name": .varchar("Test 1"), "Value": .money(123.45)],
                ["Id": .integer(2), "Name": .varchar("Test 2"), "Value": .money(678.90)]
            ],
            affectedRows: 2
        )

        #expect(result.columns.count == 3)
        // Validate first row
        #expect(result[0, "Id"]?.int == 1)
        #expect(result[0, "Name"]?.string == "Test 1")
        #expect(result[0, "Value"]?.decimal == Decimal(123.45))

        // Validate second row
        #expect(result[1, "Id"]?.int == 2)
        #expect(result[1, "Name"]?.string == "Test 2")
        #expect(result[1, "Value"]?.decimal == Decimal(678.90))
    }
    
    @Test
    func complexDataIsPopulated() async throws {
        let result = SQLResult(
            columns: ["UniqueIdentifierColumn",
                "CharColumn", "VarCharColumn", "IntColumn", "SmallIntColumn", "BigIntColumn",
                "DecimalColumn", "FloatColumn", "RealColumn", "BitColumn", "DateColumn",
                "TimeColumn", "DateTimeColumn", "SmallDateTimeColumn", "DateTime2Column",
                "DateTimeOffsetColumn", "MoneyColumn", "SmallMoneyColumn", "NCharColumn",
                "NVarCharColumn", "BinaryColumn", "VarBinaryColumn", "SpatialColumn"
            ],
            rows: [
                [
                    "UniqueIdentifierColumn": .uniqueidentifier(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!),
                    "CharColumn": .char("FixedChar"),
                    "VarCharColumn": .varchar("VariableChar"),
                    "IntColumn": .integer(42),
                    "SmallIntColumn": .smallInt(123),
                    "BigIntColumn": .bigInt(9223372036854775807),
                    "DecimalColumn": .decimal(Decimal(12345.67)),
                    "FloatColumn": .float(3.141592653589793),
                    "RealColumn": .real(1.23),
                    "BitColumn": .bit(true),
                    "DateColumn": .date(TDSDate(day: 28, month: 12, year: 2024)),
                    "TimeColumn": .time(TDSTime(hour: 12, minute: 34, second: 56)),
                    "DateTimeColumn": .datetime(TDSDateTime(date: TDSDate(day: 28, month: 12, year: 2024),
                                                              hour: 12, minute: 34, second: 56, fractionalSecond: 0)),
                    "SmallDateTimeColumn": .smalldatetime(TDSDateTime(date: TDSDate(day: 28, month: 12, year: 2024),
                                                                        hour: 12, minute: 34, second: 0, fractionalSecond: 0)),
                    "DateTime2Column": .datetime2(TDSDateTime(date: TDSDate(day: 28, month: 12, year: 2024),
                                                                hour: 12, minute: 34, second: 56, fractionalSecond: 1234567)),
                    "DateTimeOffsetColumn": .datetimeoffset(TDSDateTimeOffset(date: TDSDate(day: 28, month: 12, year: 2024),
                                                                               time: TDSTime(hour: 12, minute: 34, second: 56),
                                                                               fractionalSecond: 1234567, offset: 0)),
                    "MoneyColumn": .money(Decimal(1000000.99)),
                    "SmallMoneyColumn": .money(Decimal(500.50)),
                    "NCharColumn": .nchar("UnicodeFix"),
                    "NVarCharColumn": .nvarchar("UnicodeVar"),
                    "BinaryColumn": .binary(Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])),
                    "VarBinaryColumn": .varbinary(Data([0x01, 0x02, 0x03])),
                    "SpatialColumn": .spatial(SQLDataType.WKTString(value: "POINT(-122.335167 47.608013)"))
                ]
            ],
            affectedRows: 1
        )

        #expect(result.columns.count == 23)
        #expect(result[0, "UniqueIdentifierColumn"]?.uuid == UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(result[0, "CharColumn"]?.string == "FixedChar")
        #expect(result[0, "RealColumn"]?.float == 1.23)
        #expect(result[0, "SmallMoneyColumn"]?.decimal == Decimal(500.50))
        #expect(result[0, "DateColumn"]?.date == TDSDate(day: 28, month: 12, year: 2024))
        #expect(result[0, "TimeColumn"]?.time == TDSTime(hour: 12, minute: 34, second: 56))
        #expect(result[0, "SmallDateTimeColumn"]?.dateTime == TDSDateTime(date: TDSDate(day: 28, month: 12, year: 2024),
                                                                           hour: 12, minute: 34, second: 0, fractionalSecond: 0))
        #expect(result[0, "DateTime2Column"]?.dateTime == TDSDateTime(date: TDSDate(day: 28, month: 12, year: 2024),
                                                                       hour: 12, minute: 34, second: 56, fractionalSecond: 1234567))
        #expect(result[0, "DateTimeOffsetColumn"]?.dateTimeOffset == TDSDateTimeOffset(date: TDSDate(day: 28, month: 12, year: 2024),
                                                                                      time: TDSTime(hour: 12, minute: 34, second: 56),
                                                                                      fractionalSecond: 1234567, offset: 0))
        #expect(result[0, "BinaryColumn"]?.binary == Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]))
        #expect(result[0, "VarBinaryColumn"]?.binary == Data([0x01, 0x02, 0x03]))
        #expect(result[0, "SpatialColumn"]?.spatial == SQLDataType.WKTString(value: "POINT(-122.335167 47.608013)").value)
    }
}
