//
//  ConnectionHandle.swift
//  FreeTDSKit
//

import CFreeTDS
import Dispatch
import Synchronization

/// One open DB-Library connection, and the serial queue every call on it runs on.
///
/// DB-Library allows one thread at a time per connection. `TDSConnection` is an
/// actor, but its work can't simply run on the actor: a query blocks its thread
/// for as long as the server takes, and actors are reentrant across `await`, so
/// a second query or a `close()` could start while the first was still running
/// -- on the same DBPROCESS, or after it had been freed. Funnelling every call
/// through this queue makes them strictly one after another, and lets `close()`
/// wait for whatever is in flight.
final class ConnectionHandle: @unchecked Sendable {
    // @unchecked: `dbproc` is only ever read or written on `queue`.
    private let queue: DispatchQueue
    private var dbproc: OpaquePointer?

    init(_ dbproc: OpaquePointer, label: String) {
        self.dbproc = dbproc
        self.queue = DispatchQueue(label: "FreeTDSKit.connection.\(label)", qos: .userInitiated)
    }

    /// Run `body` on the connection's queue, after everything queued before it.
    /// `body` receives nil once the connection is closed.
    func enqueue(_ body: @escaping @Sendable (OpaquePointer?) -> Void) {
        queue.async { body(self.dbproc) }
    }

    /// Run `body` on the connection's queue and return its result.
    func run<T: Sendable>(
        _ body: @escaping @Sendable (OpaquePointer) throws(TDSConnectionError) -> T
    ) async throws(TDSConnectionError) -> T {
        let result: Result<T, TDSConnectionError> = await withCheckedContinuation { continuation in
            enqueue { dbproc in
                guard let dbproc else {
                    continuation.resume(returning: .failure(.notConnected))
                    return
                }
                continuation.resume(returning: Result { () throws(TDSConnectionError) -> T in try body(dbproc) })
            }
        }
        return try result.get()
    }

    /// Close the connection once the work already queued has finished.
    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.closeNow()
                continuation.resume()
            }
        }
    }

    private func closeNow() {
        if let dbproc {
            closeConnection(dbproc)
            self.dbproc = nil
        }
    }

    /// Queued work holds a strong reference, so this only runs once nothing
    /// can still be using the connection.
    deinit {
        closeNow()
    }
}

/// Set when a row stream's consumer goes away, read by the queue filling it.
final class CancellationFlag: Sendable {
    private let value = Atomic<Bool>(false)

    func cancel() { value.store(true, ordering: .relaxed) }
    var isCancelled: Bool { value.load(ordering: .relaxed) }
}
