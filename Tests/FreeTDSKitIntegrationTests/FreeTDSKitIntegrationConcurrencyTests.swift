import XCTest
@testable import FreeTDSKit

/// One connection used from several tasks at once. DB-Library allows a single
/// thread per connection; these ran the C calls of overlapping queries -- or of
/// a query and `close()` -- at the same time on the same DBPROCESS.
final class FreeTDSKitIntegrationConcurrencyTests: FreeTDSKitIntegrationTestCase {

    func testOverlappingExecutesOnOneConnection() async throws {
        let connection = try makeConnection()
        let values = try await withThrowingTaskGroup(of: (Int, Int?).self) { group in
            for i in 0..<20 {
                group.addTask {
                    let result = try await connection.execute(queryString: "SELECT \(i) AS n")
                    return (i, result.rows.first?["n"]?.int)
                }
            }
            var all: [(Int, Int?)] = []
            for try await value in group { all.append(value) }
            return all
        }
        XCTAssertEqual(values.count, 20)
        for (i, n) in values {
            XCTAssertEqual(n, i, "query \(i) got another query's result")
        }
        await connection.close()
    }

    func testOverlappingStreamsOnOneConnection() async throws {
        let connection = try makeConnection()
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    var rows = 0
                    for try await _ in connection.query(query: "SELECT TOP 50 name FROM sys.objects") {
                        rows += 1
                    }
                    return rows
                }
            }
            var all: [Int] = []
            for try await count in group { all.append(count) }
            return all
        }
        XCTAssertEqual(Set(counts).count, 1, "every stream should see the same rows: \(counts)")
        await connection.close()
    }

    /// `close()` waits for the query in flight rather than freeing the
    /// connection underneath it; anything after the close is refused.
    func testCloseWaitsForRunningQuery() async throws {
        let connection = try makeConnection()
        async let running = connection.execute(queryString: "WAITFOR DELAY '00:00:01'; SELECT 42 AS n")
        try await Task.sleep(for: .milliseconds(200))
        await connection.close()

        let result = try await running
        XCTAssertEqual(result.rows.first?["n"]?.int, 42)

        do {
            _ = try await connection.execute(queryString: "SELECT 1")
            XCTFail("a closed connection should refuse queries")
        } catch TDSConnectionError.notConnected {
        }
    }

    /// Each connection reports its own errors, even when another fails at the
    /// same moment.
    func testErrorsStayWithTheirConnection() async throws {
        let first = try makeConnection()
        let second = try makeConnection()

        async let a: String = {
            do {
                _ = try await first.execute(queryString: "SELECT * FROM FreeTDSKitMissingTableA")
                return "succeeded"
            } catch let error as TDSConnectionError {
                return error.messages.map(\.text).joined()
            }
        }()
        async let b: String = {
            do {
                _ = try await second.execute(queryString: "SELECT * FROM FreeTDSKitMissingTableB")
                return "succeeded"
            } catch let error as TDSConnectionError {
                return error.messages.map(\.text).joined()
            }
        }()

        let (messageA, messageB) = try await (a, b)
        XCTAssertTrue(messageA.contains("FreeTDSKitMissingTableA"), messageA)
        XCTAssertTrue(messageB.contains("FreeTDSKitMissingTableB"), messageB)
        XCTAssertFalse(messageA.contains("TableB"), messageA)
        XCTAssertFalse(messageB.contains("TableA"), messageB)

        await first.close()
        await second.close()
    }
}
