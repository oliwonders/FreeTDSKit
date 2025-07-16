//
//  TDSConnection.swift
//
//
//  Created by David Oliver on 12/28/24.
//

import CFreeTDS
import Foundation

@_silgen_name("getLastTdsErrorMessage")
private func getLastTdsErrorMessage() -> UnsafePointer<CChar>?

/// Configuration for connecting to a TDS database.
public struct ConnectionConfiguration: Sendable {
    /// Server hostname or IP address.
    public var host: String
    /// Server port.
    public var port: Int
    /// Username for authentication.
    public var username: String
    /// Password for authentication.
    public var password: String
    /// Database name.
    public var database: String
    /// Connection timeout in seconds.
    public var timeout: Int

    /// Create an empty default configuration.
    public init() {
        self.host = ""
        self.port = 1433
        self.username = ""
        self.password = ""
        self.database = ""
        self.timeout = 5
    }

    /// Create a configuration with host, port, credentials, and database name.
    public init(
        host: String,
        port: Int = 1433,
        username: String,
        password: String,
        database: String,
        timeout: Int = 5
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.timeout = timeout
    }
}

public actor TDSConnection {
    private var connection: OpaquePointer?

    /// Actor-isolated raw pointer bit-pattern for send across tasks.
    private var rawConnection: Int? {
        guard let conn = connection else { return nil }
        return Int(bitPattern: conn)
    }

    /// Initialize a connection using a Configuration.
    public init(configuration: ConnectionConfiguration) throws {
        try self.init(
            server: "\(configuration.host):\(configuration.port)",
            username: configuration.username,
            password: configuration.password,
            database: configuration.database,
            timeout: configuration.timeout
        )
    }

    /// Initialize a connection using raw parameters.
    public init(
        server: String,
        username: String,
        password: String,
        database: String,
        timeout: Int = 5
    ) throws {
        let dbInit = initializeDBLibrary()
        if dbInit != 0 {
            let msg =
                getLastTdsErrorMessage().map { String(cString: $0) }
                ?? "DB init failed"
            throw TDSConnectionError.connectionFailed(reason: msg)
        }
        self.connection = connectToDatabase(
            server,
            username,
            password,
            database,
            Int32(timeout)
        )
        if self.connection == nil {
            let msg =
                getLastTdsErrorMessage().map { String(cString: $0) }
                ?? "Connection failed"
            throw TDSConnectionError.connectionFailed(reason: msg)
        }
    }

    public func execute(queryString: String) async throws -> SQLResult {
        guard let connection = connection else {
            throw TDSConnectionError.notConnected
        }

        let connRaw = Int(bitPattern: connection)

        return try await Task.detached(priority: .userInitiated) {
            let conn = OpaquePointer(bitPattern: connRaw)!
            let success = executeQuery(conn, queryString)
            if success != 0 {
                throw TDSConnectionError.queryExecutionFailed(
                    reason: getLastTdsErrorMessage().map { String(cString: $0) }
                        ?? ""
                )
            }

            var rowCount: Int32 = 0
            guard let cRows = fetchResultsWithType(conn, &rowCount) else {
                throw TDSConnectionError.queryExecutionFailed(
                    reason: getLastTdsErrorMessage().map { String(cString: $0) }
                        ?? ""
                )
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
                    let value = determineSQLType(
                        valPtr,
                        columnType: Int(row.columnTypes?[j] ?? 0)
                    )
                    dict[key] = value
                }
                results.append(dict)
            }

            let affectedRows = Int(dbcount(conn))
            return SQLResult(
                columns: columnNames,
                rows: results,
                affectedRows: affectedRows
            )
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
    public nonisolated func query(query: String) -> AsyncThrowingStream<
        [String: SQLDataType], Error
    > {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }

                let maybeRaw = await self.rawConnection
                guard let connRaw = maybeRaw else {
                    continuation.finish(
                        throwing: TDSConnectionError.notConnected
                    )
                    return
                }
                let conn = OpaquePointer(bitPattern: connRaw)!
                guard executeQuery(conn, query) == 0 else {
                    let msg =
                        getLastTdsErrorMessage().map { String(cString: $0) }
                        ?? "Query failed"
                    continuation.finish(
                        throwing: TDSConnectionError.queryExecutionFailed(
                            reason: msg
                        )
                    )
                    return
                }

                var rowCount: Int32 = 0
                guard let cRows = fetchResultsWithType(conn, &rowCount) else {
                    let msg =
                        getLastTdsErrorMessage().map { String(cString: $0) }
                        ?? "Query failed"
                    continuation.finish(
                        throwing: TDSConnectionError.queryExecutionFailed(
                            reason: msg
                        )
                    )
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
                        let value = determineSQLType(
                            valPtr,
                            columnType: Int(row.columnTypes?[j] ?? 0)
                        )
                        dict[key] = value
                    }
                    continuation.yield(dict)
                }
            }
        }
    }

    /// Alias for `query(query:)` to emphasize streaming semantics.
    public nonisolated func streamingQuery(queryString: String) -> AsyncThrowingStream<
        [String: SQLDataType], Error
    > {
        query(query: queryString)
    }

    /// Stream rows through a mapping closure that transforms each raw row dictionary into `T`.
    public nonisolated func query<T: Sendable>(
        queryString: String,
        map: @Sendable @escaping ([String: SQLDataType]) throws -> T
    )
        -> AsyncThrowingStream<T, Error>
    {
        let base = query(query: queryString)
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
    public nonisolated func query<T: Decodable & Sendable>(
        queryString: String,
        as type: T.Type
    )
        -> AsyncThrowingStream<T, Error>
    {
        let base = query(query: queryString)
        return AsyncThrowingStream<T, Error> { continuation in
            Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                let decoder = JSONDecoder()
                for try await row in base {
                    if Task.isCancelled { break }
                    do {
                        let jsonDict = row.reduce(into: [String: Any]()) {
                            acc,
                            kv in
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

public enum TDSConnectionError: Error, CustomStringConvertible {
    case connectionFailed(reason: String)
    case notConnected
    case queryExecutionFailed(reason: String)

    public var description: String {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .notConnected: return "Not connected to the database."
        case .queryExecutionFailed(let reason):
            return "Query execution failed: \(reason)"
        }
    }
}
