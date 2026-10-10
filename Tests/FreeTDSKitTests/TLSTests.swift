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
        // macOS ships well over a hundred roots; a handful would mean the export
        // picked up the wrong store.
        #expect(count > 50)
        #expect(pem.components(separatedBy: "-----END CERTIFICATE-----").count - 1 == count)
    }

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
