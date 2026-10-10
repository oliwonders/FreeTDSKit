import Foundation
import Testing
@testable import FreeTDSKit

@Suite("Concurrency")
struct ConcurrencyTests {
    /// Errors used to live in process-wide buffers, so connections failing at
    /// the same time could report each other's errors (or write past the end
    /// of the buffer). Each must now report only its own.
    @Test func concurrentFailedConnectsReportTheirOwnErrors() async {
        let count = 64
        let results = await withTaskGroup(of: (Int, String).self) { group in
            for i in 0..<count {
                group.addTask {
                    // .invalid never resolves (RFC 6761), so each fails at once,
                    // naming the host it tried.
                    do {
                        _ = try TDSConnection(
                            server: "freetdskit-concurrency-\(i).invalid:1433",
                            username: "u", password: "p", database: "", loginTimeout: 3)
                        return (i, "connected")
                    } catch {
                        return (i, "\(error)")
                    }
                }
            }
            var all: [(Int, String)] = []
            for await result in group { all.append(result) }
            return all
        }

        #expect(results.count == count)
        for (i, message) in results {
            #expect(message.contains("freetdskit-concurrency-\(i).invalid"),
                    "connection \(i) reported: \(message)")
        }
    }
}
