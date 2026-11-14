//
//  TLS.swift
//  FreeTDSKit
//

import Foundation
#if os(macOS)
import Security
#endif

/// How a connection uses TLS. The names follow Microsoft's `Encrypt=` keyword.
public enum TDSEncryption: String, Sendable, CaseIterable {
    /// TDS 8.0: TLS from the first byte, and the server certificate is always
    /// verified (`trustServerCertificate` is ignored, as it is in Microsoft's
    /// drivers). Needs SQL Server 2022 or Azure SQL.
    case strict
    /// Refuse to connect unless the whole session is encrypted. The default.
    case mandatory
    /// Encrypt if the server offers it, otherwise send the login and all data in
    /// clear text. Only for servers that cannot do TLS; anyone on the network
    /// path can then read the password and the data.
    case optional

    /// The value FreeTDS's `encryption` setting takes.
    var freeTDSValue: String {
        switch self {
        case .strict: return "strict"
        case .mandatory: return "require"
        case .optional: return "request"
        }
    }
}

/// The certificates a connection's server certificate is checked against.
enum TrustedRoots {
    struct ExportError: Error {
        let reason: String
    }

    /// A PEM file holding the system root certificates, which FreeTDS is
    /// pointed at because OpenSSL can't read Apple's trust store, and the CA
    /// path compiled into it doesn't exist on users' devices.
    ///
    /// - macOS: the live trust store, written once per process to the caches
    ///   directory (inside the container when sandboxed). Rewriting it at each
    ///   launch keeps it in step with macOS updates.
    /// - iOS and iPadOS: no API lists the trusted roots, so this is
    ///   ``bundledRootsFile()``, a snapshot of the same Apple root program
    ///   taken when FreeTDSKit was built.
    static func systemRootsFile() throws(ExportError) -> URL {
        try systemRoots.get()
    }

    #if os(macOS)
    private static let systemRoots: Result<URL, ExportError> = Result { () throws(ExportError) -> URL in
        var anchors: CFArray?
        let status = SecTrustCopyAnchorCertificates(&anchors)
        guard status == errSecSuccess, let certificates = anchors as? [SecCertificate],
              !certificates.isEmpty
        else {
            throw ExportError(reason: "Could not read the macOS root certificates (OSStatus \(status))")
        }

        var pem = ""
        for certificate in certificates {
            let der = SecCertificateCopyData(certificate) as Data
            pem += "-----BEGIN CERTIFICATE-----\n"
            pem += der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            pem += "\n-----END CERTIFICATE-----\n"
        }

        do {
            let directory = try FileManager.default
                .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("FreeTDSKit", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("system-roots.pem")
            try Data(pem.utf8).write(to: file, options: .atomic)
            return file
        } catch {
            throw ExportError(reason: "Could not save the macOS root certificates: \(error.localizedDescription)")
        }
    }
    #else
    private static let systemRoots: Result<URL, ExportError> = Result { () throws(ExportError) -> URL in
        try bundledRootsFile()
    }
    #endif

    /// Apple's root certificates as of FreeTDSKit's build, in its resource
    /// bundle (`AppleRootCertificates.pem`, written by
    /// `Support/export-apple-roots.sh`). Present on every platform; used on
    /// those that can't export the live trust store.
    static func bundledRootsFile() throws(ExportError) -> URL {
        guard let file = Bundle.module.url(forResource: "AppleRootCertificates", withExtension: "pem") else {
            throw ExportError(reason: "FreeTDSKit's root certificates (AppleRootCertificates.pem) are missing")
        }
        return file
    }

    /// The CA file to hand FreeTDS, or nil to skip verification.
    static func caFile(
        encryption: TDSEncryption,
        trustServerCertificate: Bool,
        certificateAuthorityFile: URL?
    ) throws(ExportError) -> String? {
        if trustServerCertificate && encryption != .strict {
            return nil
        }
        if let certificateAuthorityFile {
            return certificateAuthorityFile.path
        }
        return try systemRootsFile().path
    }
}
