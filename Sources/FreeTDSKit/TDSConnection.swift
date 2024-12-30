//
//  TDSConnection.swift
//
//
//  Created by David Oliver on 12/28/24.
//

import Foundation
import CFreeTDS
import Logging

public class TDSConnection {
    private var connection: OpaquePointer?

    public init(server: String, username: String, password: String, database: String) throws {
        
        let dbInit = initializeDBLibrary()
        if (dbInit != 0) {
            throw TDSConnectionError.connectionFailed
        }
        // Initialize the connection pointer
        self.connection = connectToDatabase(server, username, password, database)
    
        // Check if the connection was successful
        if self.connection == nil {
            throw TDSConnectionError.connectionFailed
        }
    }

    deinit {
        // Ensure the connection is closed when the object is deallocated
        if connection != nil {
            closeConnection(connection)
        }
    }

 
    public func execute(query: String) throws -> [SQLResult] {
         guard let connection = connection else {
             throw TDSConnectionError.notConnected
         }

         let success = executeQuery(connection, query)
         if success != 0 {
             throw TDSConnectionError.queryExecutionFailed
         }

         var rowCount: Int32 = 0
         guard let cRows = fetchResults(connection, &rowCount) else {
             throw TDSConnectionError.queryExecutionFailed
         }

         var results: [SQLResult] = []
         for i in 0..<Int(rowCount) {
             let row = cRows[i]
             var columns: [String: String] = [:]

             for j in 0..<Int(row.columnCount) {
                 if let colName = row.columnNames?[j], let colValue = row.columnValues?[j] {
                     let columnName = String(cString: colName)
                     let columnValue = String(cString: colValue)
                     columns[columnName] = columnValue
                 }
             }
             results.append(SQLResult(columns: columns))
         }

         freeFetchedResults(cRows, rowCount)
         return results
     }

    public func disconnect() {
        if let connection = connection {
            closeConnection(connection)
            self.connection = nil
        }
    }
}

public enum TDSConnectionError: Error {
    case loginInitializationFailed
    case connectionFailed
    case notConnected
    case queryExecutionFailed
}
