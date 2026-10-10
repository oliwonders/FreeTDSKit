//
//  TDSConnection.swift
//
//
//  Created by David Oliver on 12/28/24.
//

import CFreeTDS
import Foundation

/// A message reported by SQL Server while running an operation.
///
/// A single failure usually produces more than one: the server sends the
/// specific cause first and a generic summary afterwards. `messages.first` is
/// therefore normally the one that explains what actually went wrong.
public struct TDSMessage: Sendable, Hashable, CustomStringConvertible {
    /// Server error number (e.g. 208 for "Invalid object name").
    public let number: Int
    /// Severity level; 11 and above is an error.
    public let severity: Int
    /// Server-defined state for the error number.
    public let state: Int
    /// Line of the batch or procedure that raised the message.
    public let line: Int
    /// Human-readable message text.
    public let text: String
    /// Name of the server that sent the message, when it supplied one.
    public let server: String
    /// Name of the procedure that raised the message, when it came from one.
    public let procedure: String

    public var description: String {
        "Msg \(number), Level \(severity), State \(state), Line \(line): \(text)"
    }
}

/// Messages recorded by the C layer for the most recent operation on `dbproc`,
/// oldest first. A nil `dbproc` reads the messages from a failed connect, which
/// are kept per thread: read them on the thread that tried to connect.
func collectTdsMessages(_ dbproc: OpaquePointer?) -> [TDSMessage] {
    (0..<Int(tdsMessageCount(dbproc))).map { index in
        let i = Int32(index)
        return TDSMessage(
            number: Int(tdsMessageNumber(dbproc, i)),
            severity: Int(tdsMessageSeverity(dbproc, i)),
            state: Int(tdsMessageState(dbproc, i)),
            line: Int(tdsMessageLine(dbproc, i)),
            text: String(cString: tdsMessageText(dbproc, i)),
            server: String(cString: tdsMessageServer(dbproc, i)),
            procedure: String(cString: tdsMessageProcedure(dbproc, i))
        )
    }
}

/// The text of the last failure on `dbproc` (nil: a failed connect on this
/// thread), falling back to `fallback` when nothing was recorded.
func lastTdsFailureReason(_ dbproc: OpaquePointer?, fallback: String) -> String {
    guard let raw = tdsLastErrorMessage(dbproc) else { return fallback }
    let reason = String(cString: raw)
    return reason.isEmpty ? fallback : reason
}

/// A failed query on `dbproc`, with whatever the server and DB-Library said.
private func queryFailure(_ dbproc: OpaquePointer) -> TDSConnectionError {
    .queryExecutionFailed(
        reason: lastTdsFailureReason(dbproc, fallback: "Query failed"),
        messages: collectTdsMessages(dbproc)
    )
}

/// Column names, taken from the first row.
private func columnNames(_ rows: UnsafeMutablePointer<RowData>, count: Int32) -> [String] {
    guard count > 0 else { return [] }
    let row = rows[0]
    return (0..<Int(row.columnCount)).compactMap { j in
        row.columnNames?[j].map { String(cString: $0) }
    }
}

/// One row as a dictionary of typed values.
private func rowDictionary(_ row: RowData) -> [String: SQLDataType] {
    var dict: [String: SQLDataType] = [:]
    for j in 0..<Int(row.columnCount) {
        guard
            let namePtr = row.columnNames?[j],
            let valPtr = row.columnValues?[j]
        else { continue }
        dict[String(cString: namePtr)] = determineSQLType(
            valPtr,
            length: row.columnLengths.map { Int($0[j]) },
            columnType: Int(row.columnTypes?[j] ?? 0)
        )
    }
    return dict
}

/// Default seconds to wait for a login to complete.
///
/// Fifteen rather than something tighter because a serverless Azure SQL
/// database that has auto-paused is resumed *by* the connection attempt, and
/// the resume takes appreciably longer than a warm login. A short timeout turns
/// that into an opaque "TDS server connection failed" with no server message
/// attached, since the failure happens before login.
public let defaultLoginTimeout = 15

/// Default seconds a query may run: 0, meaning wait indefinitely, which is
/// DB-Library's own default.
public let defaultQueryTimeout = 0

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
    /// Seconds to wait for the login to complete.
    ///
    /// Note that DB-Library stores this process-wide and reads it when the
    /// connection is opened, so connections opened concurrently with different
    /// values race and the last writer wins.
    public var loginTimeout: Int
    /// Seconds a query may run before DB-Library gives up on it. 0 waits
    /// indefinitely. Unlike `loginTimeout`, this is per connection.
    public var queryTimeout: Int
    /// How the connection uses TLS. Defaults to `.mandatory`.
    public var encryption: TDSEncryption = .mandatory
    /// Skip checking the server's certificate, as Microsoft's
    /// `TrustServerCertificate=yes` does. For development servers with
    /// self-signed certificates only: it lets anyone on the network path
    /// impersonate the server. Ignored with `.strict`.
    public var trustServerCertificate = false
    /// PEM file of CA certificates to trust instead of the macOS system roots,
    /// e.g. a company CA or a server's self-signed certificate.
    public var certificateAuthorityFile: URL?
    /// Name the server certificate must match, when it differs from `host`
    /// (connecting by IP address or through a private endpoint, say).
    public var hostNameInCertificate: String?

    @available(*, deprecated, renamed: "loginTimeout")
    public var timeout: Int {
        get { loginTimeout }
        set { loginTimeout = newValue }
    }

    /// Create an empty default configuration.
    public init() {
        self.host = ""
        self.port = 1433
        self.username = ""
        self.password = ""
        self.database = ""
        self.loginTimeout = defaultLoginTimeout
        self.queryTimeout = defaultQueryTimeout
    }

    /// Create a configuration with host, port, credentials, and database name.
    public init(
        host: String,
        port: Int = 1433,
        username: String,
        password: String,
        database: String,
        loginTimeout: Int = defaultLoginTimeout,
        queryTimeout: Int = defaultQueryTimeout,
        encryption: TDSEncryption = .mandatory,
        trustServerCertificate: Bool = false,
        certificateAuthorityFile: URL? = nil,
        hostNameInCertificate: String? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.loginTimeout = loginTimeout
        self.queryTimeout = queryTimeout
        self.encryption = encryption
        self.trustServerCertificate = trustServerCertificate
        self.certificateAuthorityFile = certificateAuthorityFile
        self.hostNameInCertificate = hostNameInCertificate
    }

    @available(
        *, deprecated,
        renamed: "init(host:port:username:password:database:loginTimeout:queryTimeout:)"
    )
    public init(
        host: String,
        port: Int = 1433,
        username: String,
        password: String,
        database: String,
        timeout: Int
    ) {
        self.init(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            loginTimeout: timeout
        )
    }
}

// The password must not reach logs or crash reports through string
// interpolation, print(), dump() or the debugger, which by default show every
// stored property.
extension ConnectionConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ConnectionConfiguration(host: \(host), port: \(port), username: \(username), password: <redacted>, "
            + "database: \(database), encryption: \(encryption), trustServerCertificate: \(trustServerCertificate))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "host": host,
            "port": port,
            "username": username,
            "password": "<redacted>",
            "database": database,
            "loginTimeout": loginTimeout,
            "queryTimeout": queryTimeout,
            "encryption": encryption,
            "trustServerCertificate": trustServerCertificate,
            "certificateAuthorityFile": certificateAuthorityFile as Any,
            "hostNameInCertificate": hostNameInCertificate as Any,
        ], displayStyle: .struct)
    }
}

public actor TDSConnection {
    /// The open connection. Every DB-Library call on it goes through the
    /// handle's serial queue; see `ConnectionHandle`.
    private let handle: ConnectionHandle

    /// Initialize a connection using a Configuration.
    public init(configuration: ConnectionConfiguration) throws {
        try self.init(
            server: "\(configuration.host):\(configuration.port)",
            username: configuration.username,
            password: configuration.password,
            database: configuration.database,
            loginTimeout: configuration.loginTimeout,
            queryTimeout: configuration.queryTimeout,
            encryption: configuration.encryption,
            trustServerCertificate: configuration.trustServerCertificate,
            certificateAuthorityFile: configuration.certificateAuthorityFile,
            hostNameInCertificate: configuration.hostNameInCertificate
        )
    }

    @available(
        *, deprecated,
        renamed: "init(server:username:password:database:loginTimeout:queryTimeout:)"
    )
    public init(
        server: String,
        username: String,
        password: String,
        database: String,
        timeout: Int
    ) throws {
        try self.init(
            server: server,
            username: username,
            password: password,
            database: database,
            loginTimeout: timeout
        )
    }

    /// Initialize a connection using raw parameters.
    ///
    /// - Parameters:
    ///   - loginTimeout: seconds to wait for the login. DB-Library keeps this
    ///     process-wide and reads it when the connection opens, so concurrent
    ///     opens with different values race.
    ///   - queryTimeout: seconds a query on this connection may run; 0 waits
    ///     indefinitely.
    ///   - encryption: how the connection uses TLS; see ``TDSEncryption``.
    ///   - trustServerCertificate: skip checking the server certificate. For
    ///     development servers only; ignored with `.strict`.
    ///   - certificateAuthorityFile: PEM file of CAs to trust instead of the
    ///     macOS system roots.
    ///   - hostNameInCertificate: name the certificate must match, when it
    ///     differs from the host in `server`.
    public init(
        server: String,
        username: String,
        password: String,
        database: String,
        loginTimeout: Int = defaultLoginTimeout,
        queryTimeout: Int = defaultQueryTimeout,
        encryption: TDSEncryption = .mandatory,
        trustServerCertificate: Bool = false,
        certificateAuthorityFile: URL? = nil,
        hostNameInCertificate: String? = nil
    ) throws {
        let caFile: String?
        do {
            caFile = try TrustedRoots.caFile(
                encryption: encryption,
                trustServerCertificate: trustServerCertificate,
                certificateAuthorityFile: certificateAuthorityFile
            )
        } catch {
            throw TDSConnectionError.connectionFailed(reason: error.reason)
        }

        // Synchronous, so the messages from a failed login are read on the
        // same thread that recorded them.
        guard let dbproc = connectToDatabase(
            server,
            username,
            password,
            database,
            Int32(loginTimeout),
            encryption.freeTDSValue,
            caFile,
            hostNameInCertificate
        ) else {
            throw TDSConnectionError.connectionFailed(
                reason: lastTdsFailureReason(nil, fallback: "Connection failed"),
                messages: collectTdsMessages(nil)
            )
        }
        if setQueryTimeout(dbproc, Int32(queryTimeout)) != 0 {
            let error = TDSConnectionError.connectionFailed(
                reason: lastTdsFailureReason(
                    dbproc, fallback: "Could not set a query timeout of \(queryTimeout)s"
                ),
                messages: collectTdsMessages(dbproc)
            )
            closeConnection(dbproc)
            throw error
        }
        self.handle = ConnectionHandle(dbproc, label: server)
    }

    public func execute(queryString: String) async throws -> SQLResult {
        try await handle.run { conn throws(TDSConnectionError) in
            guard executeQuery(conn, queryString) == 0 else {
                throw queryFailure(conn)
            }

            var rowCount: Int32 = 0
            guard let cRows = fetchResultsWithType(conn, &rowCount) else {
                throw queryFailure(conn)
            }
            defer { freeFetchedResults(cRows, rowCount) }

            let rows = (0..<Int(rowCount)).map { rowDictionary(cRows[$0]) }
            return SQLResult(
                columns: columnNames(cRows, count: rowCount),
                rows: rows,
                affectedRows: Int(dbcount(conn))
            )
        }
    }

    @available(*, deprecated, renamed: "close()")
    public func disconnect() async {
        await close()
    }

    /// Close the database connection, after any query already running on it
    /// finishes. Queries started afterwards fail with `.notConnected`.
    ///
    /// A connection that is never closed is closed when the `TDSConnection` is
    /// released, but closing explicitly ends the server session promptly.
    public func close() async {
        await handle.close()
    }

    /// Execute the given SQL query and return an async sequence of row dictionaries.
    /// Rows are yielded one by one as they are mapped, and the sequence finishes
    /// when all rows have been produced or if an error occurs. Cancellation is supported.
    public nonisolated func query(query: String) -> AsyncThrowingStream<
        [String: SQLDataType], Error
    > {
        let handle = self.handle
        return AsyncThrowingStream { continuation in
            let cancellation = CancellationFlag()
            continuation.onTermination = { _ in cancellation.cancel() }

            handle.enqueue { conn in
                guard let conn else {
                    continuation.finish(throwing: TDSConnectionError.notConnected)
                    return
                }
                guard executeQuery(conn, query) == 0 else {
                    continuation.finish(throwing: queryFailure(conn))
                    return
                }

                var rowCount: Int32 = 0
                guard let cRows = fetchResultsWithType(conn, &rowCount) else {
                    continuation.finish(throwing: queryFailure(conn))
                    return
                }
                defer { freeFetchedResults(cRows, rowCount) }

                for i in 0..<Int(rowCount) {
                    if cancellation.isCancelled { break }
                    continuation.yield(rowDictionary(cRows[i]))
                }
                continuation.finish()
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
                do {
                    for try await row in base {
                        if Task.isCancelled { break }
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
                    }
                } catch {
                    // Covers both decoding failures and errors surfaced by the
                    // underlying row stream; without this the query error would
                    // be swallowed and the sequence would end looking empty.
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public enum TDSConnectionError: Error, CustomStringConvertible, LocalizedError {
    case connectionFailed(reason: String, messages: [TDSMessage] = [])
    case notConnected
    case queryExecutionFailed(reason: String, messages: [TDSMessage] = [])

    /// Every message the server reported for the failure, oldest first.
    /// The first entry is normally the specific cause; later ones are the
    /// generic summaries the server appends after it.
    public var messages: [TDSMessage] {
        switch self {
        case .connectionFailed(_, let messages): return messages
        case .queryExecutionFailed(_, let messages): return messages
        case .notConnected: return []
        }
    }

    /// The most specific message the server reported, when there was one.
    public var primaryMessage: TDSMessage? { messages.first }

    public var description: String {
        switch self {
        case .connectionFailed(let reason, _):
            return "Connection failed: \(reason)"
        case .notConnected: return "Not connected to the database."
        case .queryExecutionFailed(let reason, _):
            return "Query execution failed: \(reason)"
        }
    }

    public var errorDescription: String? { description }
}
