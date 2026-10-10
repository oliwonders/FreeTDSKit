import Foundation
import Testing
@testable import FreeTDSKit

@Suite("Configuration redaction")
struct ConfigurationRedactionTests {
    let secret = "correct-horse-battery-staple"

    var config: ConnectionConfiguration {
        ConnectionConfiguration(host: "db.example.com", username: "app", password: secret, database: "geo")
    }

    @Test func descriptionHidesPassword() {
        #expect(!"\(config)".contains(secret))
        #expect(!String(describing: config).contains(secret))
        #expect(!String(reflecting: config).contains(secret))
        #expect("\(config)".contains("db.example.com"))
    }

    @Test func dumpHidesPassword() {
        var output = ""
        dump(config, to: &output)
        #expect(!output.contains(secret))
        #expect(output.contains("<redacted>"))
    }

    @Test func passwordIsStillUsable() {
        #expect(config.password == secret)
    }
}
