import XCTest
@testable import FreeTDSKit

#if !INTEGRATION_TESTS

/// Integration tests covering how failures are reported.
///
/// SQL Server answers one failure with several messages -- the specific cause
/// first, a generic summary after -- and these tests pin down that the specific
/// one survives all the way to the caller.
final class FreeTDSKitIntegrationErrorTests: FreeTDSKitIntegrationTestCase {

    func testConnectingToMissingDatabaseReportsTheCause() async throws {
        do {
            let connection = try TDSConnection(
                server: connectionString,
                username: username,
                password: password,
                database: "FreeTDSKitNoSuchDatabase"
            )
            await connection.close()
            XCTFail("Expected the connection to a missing database to fail")
        } catch let error as TDSConnectionError {
            guard case .connectionFailed(let reason, let messages) = error else {
                return XCTFail("Expected connectionFailed, got \(error)")
            }
            // 4060: "Cannot open database ... requested by the login."
            XCTAssertEqual(
                error.primaryMessage?.number, 4060,
                "The specific cause should come first, not the generic login failure"
            )
            XCTAssertTrue(
                reason.contains("FreeTDSKitNoSuchDatabase"),
                "Reason should name the database that could not be opened: \(reason)"
            )
            // The server also sends 18456 "Login failed for user"; both are kept.
            XCTAssertGreaterThanOrEqual(messages.count, 1)
            XCTAssertTrue(messages.allSatisfy { $0.severity >= 11 })
        }
    }

    func testQueryForMissingTableThrowsThroughTheRowStream() async throws {
        let connection = try makeConnection()
        defer { Task { await connection.close() } }

        do {
            for try await _ in connection.query(
                query: "SELECT * FROM dbo.FreeTDSKitNoSuchTable"
            ) {
                XCTFail("Expected no rows from a missing table")
            }
            XCTFail("Expected the query to throw")
        } catch let error as TDSConnectionError {
            // 208: "Invalid object name '...'".
            XCTAssertEqual(error.primaryMessage?.number, 208)
        }
    }

    /// Regression test: the error from the underlying row stream used to be
    /// swallowed by the detached task, leaving the sequence looking empty.
    func testDecodableQueryForMissingTableThrowsRatherThanFinishingEmpty() async throws {
        struct Row: Decodable, Sendable { let Id: Int }

        let connection = try makeConnection()
        defer { Task { await connection.close() } }

        do {
            for try await _ in connection.query(
                queryString: "SELECT Id FROM dbo.FreeTDSKitNoSuchTable",
                as: Row.self
            ) {
                XCTFail("Expected no rows from a missing table")
            }
            XCTFail("Expected the query to throw rather than finish empty")
        } catch let error as TDSConnectionError {
            XCTAssertEqual(error.primaryMessage?.number, 208)
            XCTAssertTrue(
                error.description.contains("FreeTDSKitNoSuchTable"),
                "Error should name the missing table: \(error.description)"
            )
        }
    }

    func testSyntaxErrorFromExecuteReportsServerMessage() async throws {
        let connection = try makeConnection()
        do {
            _ = try await connection.execute(queryString: "SELECT FROM WHERE")
            XCTFail("Expected a syntax error")
        } catch let error as TDSConnectionError {
            XCTAssertFalse(error.messages.isEmpty, "Expected a server message")
            XCTAssertNotEqual(error.primaryMessage?.text, "")
        }
        await connection.close()
    }
}

#endif
