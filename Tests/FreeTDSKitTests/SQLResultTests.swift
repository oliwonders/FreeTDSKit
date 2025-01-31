//
//  Test.swift
//  FreeTDSKit
//
//  Created by David Oliver on 1/27/25.
//

import CFreeTDS
@testable import FreeTDSKit
import Testing

@Suite("SQLResult Tests") struct SQLResultTests {

    @Test func AffectedRowsIsPopulated() async throws {
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
    
    @Test("")
    func ColumnsIsPopulated() async throws {
        let result = SQLResult(
            columns: ["Id", "Name", "Value"],
            rows: [
                ["Id": .integer(1), "Name": .varchar("Test 1"), "Value": .money(123.45)],
                ["Id": .integer(2), "Name": .varchar("Test 2"), "Value": .money(678.90)]
            ],
            affectedRows: 2
        )
        
        print ("Id: \(result.value(for: "Id", inRow: 0))")
        
        // Retrieve a specific value by column and row
//        if let idValue = result.value(for: "Id", inRow: 0) {
//            if case let .integer(idValue) = idValue {
//                #expect(id == 1)
//            } else {
//                Issue.record("Id value is not an integer.")
//            }
//        } else {
//            Issue.record( "Id value is missing.")
//        }
//        
//        // Retrieve a specific value by column and row
//        if let nameValue = result.value(for: "Name", inRow: 0) {
//            if case let .varchar(name) = nameValue {
//                #expect(name == "Test 1")
//            } else {
//                Issue.record( "Name value is not a string.")
//            }
//        } else {
//            Issue.record( "Name value is missing.")
//        }
//
//        // Retrieve all values for a specific column
//        let allNames = result.allValues(for: "Name")
//        allNames.forEach { value in
//            if case let .varchar(name) = value {
//                print(name)
//            } else {
//                Issue.record( "Unexpected value type in Name column.")
//            }
//        }
        // Expected Output:
        // Test 1
        // Test 2
    }
}
