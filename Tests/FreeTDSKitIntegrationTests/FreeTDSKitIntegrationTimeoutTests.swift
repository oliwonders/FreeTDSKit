import XCTest
@testable import FreeTDSKit

#if !INTEGRATION_TESTS

/// Integration tests for the per-connection query timeout.
final class FreeTDSKitIntegrationTimeoutTests: FreeTDSKitIntegrationTestCase {

    private func makeConnection(queryTimeout: Int) throws -> TDSConnection {
        try TDSConnection(
            server: connectionString,
            username: username,
            password: password,
            database: database,
            queryTimeout: queryTimeout
        )
    }

    func testQueryTimeoutAbortsALongRunningQuery() async throws {
        let connection = try makeConnection(queryTimeout: 1)
        let started = Date()

        do {
            _ = try await connection.execute(queryString: "WAITFOR DELAY '00:00:10'")
            XCTFail("Expected the query to be abandoned after its timeout")
        } catch is TDSConnectionError {
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(
                elapsed, 8,
                "Expected to give up around the 1s timeout, not to wait out the query"
            )
        }
    }

    func testQueryInsideTheTimeoutStillSucceeds() async throws {
        let connection = try makeConnection(queryTimeout: 30)
        let result = try await connection.execute(
            queryString: "WAITFOR DELAY '00:00:01'; SELECT 1 AS Value"
        )
        XCTAssertFalse(result.rows.isEmpty, "Expected the query to run to completion")
        await connection.close()
    }

    /// The default leaves DB-Library's own behaviour in place: no timeout.
    func testDefaultQueryTimeoutDoesNotAbortSlowQueries() async throws {
        let connection = try makeConnection()
        let result = try await connection.execute(
            queryString: "WAITFOR DELAY '00:00:03'; SELECT 1 AS Value"
        )
        XCTAssertFalse(result.rows.isEmpty, "A slow query should not be cut off by default")
        await connection.close()
    }
}

#endif
