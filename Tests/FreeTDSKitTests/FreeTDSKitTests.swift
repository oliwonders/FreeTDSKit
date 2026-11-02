import Foundation
import Testing
@testable import FreeTDSKit

@Test func testVersion() async throws {
    let version = FreeTDSKit.getFreeTDSVersion()
    #expect(version != "")
    print("FreeTDS Version: \(String(describing: version))")
}

/// The versions the archive was built with (Support/buildandlinkfreetds.sh):
/// a different one means a system copy got linked instead.
@Test func linkedLibraryVersions() throws {
    let script = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../../Support/buildandlinkfreetds.sh"), encoding: .utf8)
    func pinned(_ name: String) -> String? {
        script.split(separator: "\n").first { $0.hasPrefix("\(name)=") }
            .map { $0.dropFirst(name.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }
    let versions = FreeTDSKit.versions
    #expect(versions.freeTDS == pinned("FREETDS_VERSION"))
    #expect(versions.openSSL == pinned("OPENSSL_VERSION"))
    #expect(versions.libiconv.first?.isNumber == true)
    #expect(FreeTDSKit.number(in: "OpenSSL 3.5.9  30 Jun 2026") == "3.5.9")
    #expect(FreeTDSKit.number(in: "freetds v1.5.19") == "1.5.19")
}


@Test("Connection defaults leave room for a serverless database to resume")
func connectionTimeoutDefaults() async throws {
    let config = ConnectionConfiguration(
        host: "example",
        username: "u",
        password: "p",
        database: "d"
    )
    #expect(config.loginTimeout == defaultLoginTimeout)
    #expect(config.loginTimeout >= 15)
    // 0 means "wait indefinitely", DB-Library's own default: opting into a
    // query timeout must stay a deliberate choice.
    #expect(config.queryTimeout == 0)
    #expect(ConnectionConfiguration().loginTimeout == defaultLoginTimeout)
}
