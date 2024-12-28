import Testing
@testable import FreeTDSKit

@Test func testVersion() async throws {
    let version = FreeTDSKit.getFreeTDSVersion()
    #expect(version != nil)
    print("Runnin' FreeTDS Version: \(String(describing: version))")
}
