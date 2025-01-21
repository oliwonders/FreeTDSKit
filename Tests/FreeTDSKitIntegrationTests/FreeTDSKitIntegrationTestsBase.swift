//
//  FreeTDSKitTests.swift
//  FreeTDSKit
//
//  Created by David Oliver on 1/11/25.
//

import Testing
import FreeTDSKit
import Foundation

struct FreeTDSKitIntegrationTestBase {
    static func setUp() async throws {
        guard checkEnvironment() else {
            throw TestError("Environment not ready. Please check error messages above.")
        }
    }
    
    static func checkEnvironment() -> Bool {
       
        // Check if Territory table exists
        guard doesTerritoryTableExist() else {
            print("❌ Territory table not found in GeoLens database")
            //add create table
            return false
        }
        
        print("✅ Environment checks passed - ready to run tests")
        return true
    }
    
    static func doesTerritoryTableExist() -> Bool {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/opt/mssql-tools/bin/sqlcmd")
        process.arguments = [
            "-S", "localhost",
            "-U", "sa",
            "-P", "yourStrongPassword1",
            "-d", "GeoLens",
            "-Q", """
                IF EXISTS (SELECT 1 
                          FROM sys.tables t 
                          JOIN sys.schemas s ON t.schema_id = s.schema_id 
                          WHERE s.name = 'dbo' AND t.name = 'Territory')
                    SELECT 1
                ELSE
                    SELECT 0
                """
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("1")
            }
            return false
        } catch {
            print("❌ Error checking Territory table: \(error)")
            return false
        }
    }

    
    static func initializeDatabase() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/mssql-tools/bin/sqlcmd")
        process.arguments = [
            "-S", "localhost",
            "-U", "sa",
            "-P", "yourStrongPassword1",
            "-i", "db-setup.sql"
        ]
        try? process.run()
        process.waitUntilExit()
    }
    
    
}

// Custom error type for test failures
struct TestError: Error {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
}
