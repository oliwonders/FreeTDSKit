import Foundation
import CFreeTDS

public struct FreeTDSKit {
    
    public static func getFreeTDSVersion() -> String {
        if let cString = getDBVersion() {
            return String(cString: cString)
        } else {
            return "Unknown Version"
        }
    }

    /// The libraries FreeTDSKit is built on, as linked into this binary --
    /// for an app's About box or diagnostic report, and for checking a
    /// security fix actually shipped.
    public struct Versions: Sendable, Equatable {
        /// e.g. "1.5.19"
        public let freeTDS: String
        /// e.g. "3.5.9", statically linked with FreeTDS.
        public let openSSL: String
        /// The macOS libiconv FreeTDS converts character sets with, e.g. "1.11".
        public let libiconv: String
    }

    public static let versions = Versions(
        freeTDS: number(in: getFreeTDSVersion()),
        openSSL: getOpenSSLVersion().map { number(in: String(cString: $0)) } ?? "unknown",
        libiconv: { let v = getLibiconvVersion(); return "\(v >> 8).\(v & 0xFF)" }()
    )

    /// "freetds v1.5.19" -> "1.5.19"; "OpenSSL 3.5.9  30 Jun 2026" -> "3.5.9".
    static func number(in text: String) -> String {
        text.split(separator: " ")
            .map { $0.hasPrefix("v") ? $0.dropFirst() : $0 }
            .first { $0.first?.isNumber == true && $0.contains(".") }
            .map(String.init) ?? text
    }

}
