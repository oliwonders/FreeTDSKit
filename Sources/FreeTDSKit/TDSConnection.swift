//
//  TDSConnection.swift
//
//
//  Created by David Oliver on 12/28/24.
//

import Foundation
import CFreeTDS

public actor TDSConnection {
    private var connection: OpaquePointer?

    /// Actor-isolated raw pointer bit-pattern for send across tasks.
    private var rawConnection: Int? {
        guard let conn = connection else { return nil }
        return Int(bitPattern: conn)
    }

    /// Configuration for connecting to a TDS database.
    public struct Configuration {
        public let host: String
        public let port: Int
        public let username: String
        public let password: String
        public let database: String

        /// Create a configuration with host, port, credentials, and database name.
        public init(host: String,
                    port: Int = 1433,
                    username: String,
                    password: String,
                    database: String) {
            self.host = host
            self.port = port
            self.username = username
            self.password = password
            self.database = database
        }
    }

    /// Initialize a connection using a Configuration.
    public init(configuration: Configuration) throws {
        try self.init(
            server: "\(configuration.host):\(configuration.port)",
            username: configuration.username,
            password: configuration.password,
            database: configuration.database
        )
    }

    /// Initialize a connection using raw parameters.
    public init(server: String,
                username: String,
                password: String,
                database: String) throws {
        let dbInit = initializeDBLibrary()
        if dbInit != 0 {
            throw TDSConnectionError.connectionFailed
        }
        self.connection = connectToDatabase(server, username, password, database)
        if self.connection == nil {
            throw TDSConnectionError.connectionFailed
        }
    }


    public func execute(query: String) async throws -> SQLResult {
        guard let connection = connection else {
            throw TDSConnectionError.notConnected
        }

        let connRaw = Int(bitPattern: connection)

        return try await Task.detached(priority: .userInitiated) {
            let conn = OpaquePointer(bitPattern: connRaw)!
            let success = executeQuery(conn, query)
            if success != 0 {
                throw TDSConnectionError.queryExecutionFailed
            }

            var rowCount: Int32 = 0
            guard let cRows = fetchResultsWithType(conn, &rowCount) else {
                throw TDSConnectionError.queryExecutionFailed
            }
            defer { freeFetchedResults(cRows, rowCount) }

            var results: [[String: SQLDataType]] = []
            var columnNames: [String] = []

            if rowCount > 0 {
                let firstRow = cRows[0]
                for j in 0..<Int(firstRow.columnCount) {
                    if let colName = firstRow.columnNames?[j] {
                        columnNames.append(String(cString: colName))
                    }
                }
            }

            for i in 0..<Int(rowCount) {
                let row = cRows[i]
                if columnNames.isEmpty {
                    for j in 0..<Int(row.columnCount) {
                        if let cName = row.columnNames?[j] {
                            columnNames.append(String(cString: cName))
                        }
                    }
                }

                var dict: [String: SQLDataType] = [:]
                for j in 0..<Int(row.columnCount) {
                    guard
                        let namePtr = row.columnNames?[j],
                        let valPtr = row.columnValues?[j]
                    else { continue }

                    let key = String(cString: namePtr)
                    let value = determineSQLType(valPtr, columnType: Int(row.columnTypes?[j] ?? 0))
                    dict[key] = value
                }
                results.append(dict)
            }

            let affectedRows = Int(dbcount(conn))
            return SQLResult(columns: columnNames,
                             rows: results,
                             affectedRows: affectedRows)
        }.value
    }

    @available(*, deprecated, renamed: "close()")
    public func disconnect() {
        close()
    }

    /// Close the database connection.
    public func close() {
        if let connection = connection {
            closeConnection(connection)
            self.connection = nil
        }
    }

    /// Execute the given SQL query and return an async sequence of row dictionaries.
    /// Rows are yielded one by one as they are mapped, and the sequence finishes
    /// when all rows have been produced or if an error occurs. Cancellation is supported.
    public nonisolated func rows(query: String) -> AsyncThrowingStream<[String: SQLDataType], Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }

                let maybeRaw = await self.rawConnection
                guard let connRaw = maybeRaw else {
                    continuation.finish(throwing: TDSConnectionError.notConnected)
                    return
                }
                let conn = OpaquePointer(bitPattern: connRaw)!
                guard executeQuery(conn, query) == 0 else {
                    continuation.finish(throwing: TDSConnectionError.queryExecutionFailed)
                    return
                }

                var rowCount: Int32 = 0
                guard let cRows = fetchResultsWithType(conn, &rowCount) else {
                    continuation.finish(throwing: TDSConnectionError.queryExecutionFailed)
                    return
                }
                defer { freeFetchedResults(cRows, rowCount) }

                var columnNames: [String] = []
                if rowCount > 0 {
                    let firstRow = cRows[0]
                    for j in 0..<Int(firstRow.columnCount) {
                        if let cName = firstRow.columnNames?[j] {
                            columnNames.append(String(cString: cName))
                        }
                    }
                }

                for i in 0..<Int(rowCount) {
                    if Task.isCancelled { break }
                    let row = cRows[i]
                    if columnNames.isEmpty {
                        for j in 0..<Int(row.columnCount) {
                            if let cName = row.columnNames?[j] {
                                columnNames.append(String(cString: cName))
                            }
                        }
                    }

                    var dict: [String: SQLDataType] = [:]
                    for j in 0..<Int(row.columnCount) {
                        guard
                            let namePtr = row.columnNames?[j],
                            let valPtr = row.columnValues?[j]
                        else { continue }

                        let key = String(cString: namePtr)
                        let value = determineSQLType(valPtr, columnType: Int(row.columnTypes?[j] ?? 0))
                        dict[key] = value
                    }
                    continuation.yield(dict)
                }
            }
        }
    }

    /// Alias for `rows(query:)` to emphasize streaming semantics.
    public nonisolated func streamRows(query: String) -> AsyncThrowingStream<[String: SQLDataType], Error> {
        rows(query: query)
    }

    /// Stream rows through a mapping closure that transforms each raw row dictionary into `T`.
    public nonisolated func rows<T>(query: String,
                        map: @Sendable @escaping ([String: SQLDataType]) throws -> T)
        -> AsyncThrowingStream<T, Error> {
        let base = rows(query: query)
        return AsyncThrowingStream<T, Error> { continuation in
            Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                do {
                    for try await row in base {
                        if Task.isCancelled { break }
                        let mapped = try map(row)
                        continuation.yield(mapped)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Stream rows directly into `Decodable` models. Column names must match model properties.
    public nonisolated func rows<T: Decodable>(query: String,
                                   as type: T.Type)
        -> AsyncThrowingStream<T, Error> {
        let base = rows(query: query)
        return AsyncThrowingStream<T, Error> { continuation in
            Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                let decoder = JSONDecoder()
                for try await row in base {
                    if Task.isCancelled { break }
                    do {
                        let jsonDict = row.reduce(into: [String: Any]()) { acc, kv in
                            acc[kv.key] = kv.value.jsonValue
                        }
                        let data = try JSONSerialization.data(
                            withJSONObject: jsonDict,
                            options: []
                        )
                        let model = try decoder.decode(T.self, from: data)
                        continuation.yield(model)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
        }
    }
}

public enum TDSConnectionError: Error {
    case connectionFailed
    case notConnected
    case queryExecutionFailed
}

// MARK: - Sendable Conformance
extension TDSConnection.Configuration: Sendable {}