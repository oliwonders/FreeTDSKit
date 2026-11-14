import Foundation
import Testing
@testable import FreeTDSKit

@Suite("TLS settings")
struct TLSTests {
    @Test func encryptionMapsToFreeTDSValues() {
        #expect(TDSEncryption.strict.freeTDSValue == "strict")
        #expect(TDSEncryption.mandatory.freeTDSValue == "require")
        #expect(TDSEncryption.optional.freeTDSValue == "request")
    }

    @Test func defaultsAreMandatoryAndVerified() {
        let config = ConnectionConfiguration(host: "h", username: "u", password: "p", database: "d")
        #expect(config.encryption == .mandatory)
        #expect(config.trustServerCertificate == false)
        #expect(config.certificateAuthorityFile == nil)
    }

    @Test func systemRootsAreExportedAsPEM() throws {
        let file = try TrustedRoots.systemRootsFile()
        let pem = try String(contentsOf: file, encoding: .utf8)
        let count = pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1
        // Apple ships well over a hundred roots; a handful would mean the export
        // picked up the wrong store.
        #expect(count > 50)
        #expect(pem.components(separatedBy: "-----END CERTIFICATE-----").count - 1 == count)
    }

    /// The snapshot iOS verifies against ships on every platform, so it is
    /// checked on macOS too.
    @Test func bundledRootsAreUsablePEM() throws {
        let file = try TrustedRoots.bundledRootsFile()
        let pem = try String(contentsOf: file, encoding: .utf8)
        let blocks = pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst()
        #expect(blocks.count > 50)
        for block in blocks {
            let body = block.components(separatedBy: "-----END CERTIFICATE-----")
            #expect(body.count == 2)
            let der = Data(base64Encoded: body[0], options: .ignoreUnknownCharacters)
            #expect(der != nil && der!.count > 100)
        }
    }

    #if !os(macOS)
    @Test func systemRootsAreTheBundledSnapshotOffMacOS() throws {
        #expect(try TrustedRoots.systemRootsFile() == TrustedRoots.bundledRootsFile())
    }
    #endif

    @Test func verificationUsesSystemRootsByDefault() throws {
        let caFile = try TrustedRoots.caFile(
            encryption: .mandatory, trustServerCertificate: false, certificateAuthorityFile: nil)
        #expect(caFile == (try TrustedRoots.systemRootsFile().path))
    }

    @Test func trustServerCertificateSkipsVerification() throws {
        let caFile = try TrustedRoots.caFile(
            encryption: .mandatory, trustServerCertificate: true, certificateAuthorityFile: nil)
        #expect(caFile == nil)
    }

    @Test func strictAlwaysVerifies() throws {
        let caFile = try TrustedRoots.caFile(
            encryption: .strict, trustServerCertificate: true, certificateAuthorityFile: nil)
        #expect(caFile != nil)
    }

    @Test func customCertificateAuthorityWins() throws {
        let custom = URL(fileURLWithPath: "/tmp/company-ca.pem")
        let caFile = try TrustedRoots.caFile(
            encryption: .mandatory, trustServerCertificate: false, certificateAuthorityFile: custom)
        #expect(caFile == custom.path)
    }
}
