import Testing
@testable import FreeTDSKit

@Test func testVersion() async throws {
    let version = FreeTDSKit.getFreeTDSVersion()
    #expect(version != "")
    print("FreeTDS Version: \(String(describing: version))")
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
