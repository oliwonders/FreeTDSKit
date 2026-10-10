import Foundation
import Testing
@testable import FreeTDSKit

/// Checks certificate verification against a real server with a publicly
/// trusted certificate, such as an Azure SQL logical server.
///
/// No credentials are needed: the TLS handshake happens before the login, so a
/// made-up user shows which side of the handshake a connection got to. A
/// "Login failed" message (18456) from the server means TLS was negotiated and
/// the certificate accepted; a failure with no server message at all means the
/// connection was refused before the server ever saw the login.
///
///     FREETDSKIT_TLS_TEST_HOST=yourserver.database.windows.net swift test --filter TLSVerification
@Suite(
    "TLS verification",
    .enabled(if: ProcessInfo.processInfo.environment["FREETDSKIT_TLS_TEST_HOST"] != nil)
)
struct FreeTDSKitTLSVerificationTests {
    let host = ProcessInfo.processInfo.environment["FREETDSKIT_TLS_TEST_HOST"] ?? ""
    let loginFailed = 18456

    /// Connect with a made-up login; returns the error, which is always expected.
    private func attempt(
        server: String,
        encryption: TDSEncryption = .mandatory,
        trustServerCertificate: Bool = false,
        certificateAuthorityFile: URL? = nil,
        hostNameInCertificate: String? = nil
    ) -> TDSConnectionError? {
        do {
            let connection = try TDSConnection(
                server: "\(server):1433",
                username: "freetdskit-tls-check",
                password: "not-a-real-password",
                database: "",
                encryption: encryption,
                trustServerCertificate: trustServerCertificate,
                certificateAuthorityFile: certificateAuthorityFile,
                hostNameInCertificate: hostNameInCertificate
            )
            Task { await connection.close() }
            return nil
        } catch let error as TDSConnectionError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }

    private func reachedLogin(_ error: TDSConnectionError?) -> Bool {
        error?.messages.contains { $0.number == loginFailed } ?? false
    }

    private func ipAddress(of host: String) throws -> String {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else {
            throw TDSConnectionError.connectionFailed(reason: "Could not resolve \(host)")
        }
        defer { freeaddrinfo(result) }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count),
                    nil, 0, NI_NUMERICHOST)
        return String(cString: buffer)
    }

    @Test func trustedCertificateIsAccepted() {
        #expect(reachedLogin(attempt(server: host)))
    }

    @Test func strictEncryptionIsAccepted() {
        #expect(reachedLogin(attempt(server: host, encryption: .strict)))
    }

    /// By IP address, the name doesn't match the certificate, so a verifying
    /// connection must stop at the handshake.
    @Test func mismatchedHostNameIsRefused() throws {
        let error = attempt(server: try ipAddress(of: host))
        #expect(error != nil)
        #expect(error?.messages.isEmpty == true, "the server should never have seen the login")
    }

    @Test func hostNameInCertificateOverridesTheConnectionName() throws {
        let error = attempt(server: try ipAddress(of: host), hostNameInCertificate: host)
        #expect(error?.messages.isEmpty == false, "TLS should have succeeded and the server answered")
    }

    @Test func trustServerCertificateSkipsTheCheck() throws {
        let error = attempt(server: try ipAddress(of: host), trustServerCertificate: true)
        #expect(error?.messages.isEmpty == false, "TLS should have succeeded and the server answered")
    }

    /// A self-signed certificate, generated once for this test and trusted by
    /// nothing; the server's chain can't lead to it.
    private let unrelatedCA = """
        -----BEGIN CERTIFICATE-----
        MIICzDCCAbQCCQCDtpncPjRZnDANBgkqhkiG9w0BAQsFADAnMSUwIwYDVQQDDBxG
        cmVlVERTS2l0IHVucmVsYXRlZCB0ZXN0IENBMCAXDTI2MTAxMDIyMDYxNVoYDzIx
        MjYwOTE2MjIwNjE1WjAnMSUwIwYDVQQDDBxGcmVlVERTS2l0IHVucmVsYXRlZCB0
        ZXN0IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3DqWB9j1wXoC
        Wl+UqyfHxhx9uOA4ZslKo6uBJ6+BwCbT7FXBt4dGHKx+/WfD0Bj/W/CN3qw4dvDt
        AEnO4rw4T5giOg2kt7ieWiNHKHr6TGsrc+qRCues69n9LFI8u3haZ79l3STsnh5F
        6UQQLsOzV8Lkla0MxtpHBCXXfC7XYfUqMoOpbwyzDsTqtqvAY0acDxMLvYQjI/vU
        BypncT1gZWHsmygdCluqvocOkDhqjJc3g0AQ+t1H+KYScM59cb80pn/JSPc60/Xw
        fdmgUiOrjIfjnxHqMUbTp0pM1epwEl6iJAI93RkudW9LJZ4IUp76iVo3j0nbDH0L
        3ZozzqmCbQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQCoIUD9Zvr/qEj/EGoPfBLE
        bRidrHRcPBv/fBPn+EECf3OqRwdT5k0XrPUV5VLlSoLVlX7xs9OXRQroFy0IsA2l
        +DQ7VQzI/s0RochFO6z8dwYSxmNC0ZY7vIU3Il18uO+J/7eLnQXYvnSUVFIcAuns
        VA5fS2FqkX97sfoNxVtWm7JdbLUUCS86dUuZxPmp3B6wqx/KgYyU9IqpDxK9Z3+Z
        KeNuFXCYb7FMouYhonm/EH391U/irUXXBBUmTBw6HRCQ4dEqJJ/RJ0owpTcyv1mX
        DvlDwL69aSdbwUk8YC6ceFvq+KIwGSrIS72WsFlmSwI/CJY27nM0FnU+OxFflwPE
        -----END CERTIFICATE-----
        """

    /// A CA file that doesn't contain the server's root must be refused, which
    /// shows the file is what verification actually uses.
    @Test func unrelatedCertificateAuthorityIsRefused() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("freetdskit-unrelated-ca.pem")
        try unrelatedCA.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let error = attempt(server: host, certificateAuthorityFile: file)
        #expect(error != nil)
        #expect(error?.messages.isEmpty == true, "the server should never have seen the login")
    }
}
