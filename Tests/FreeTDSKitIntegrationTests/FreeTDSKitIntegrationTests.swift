import Foundation
import Testing

@testable import FreeTDSKit

struct TestHelpers {
    static var isRunningIntegrationTests: Bool {
        #if INTEGRATION_TESTS
            return true
        #else
            return false
        #endif
    }
}

@Suite(
    "FreeTDS Integration Tests",
    .disabled(if: !TestHelpers.isRunningIntegrationTests))
final class FreeTDSKitIntegrationTests {

    var server: String
    var port: String
    var username: String
    var password: String
    let database: String = "FreeTDSKitTestDB"
    let testTable: String = "DataTypeTest"

    init() async throws {
        guard let serverEnv = ProcessInfo.processInfo.environment["FREETDSKIT_SQL_SERVER"], !serverEnv.isEmpty
        else {
            throw EnvironmentVariableError(variableName: "FREETDSKIT_SQL_SERVER")
        }
        guard
            let userEnv = ProcessInfo.processInfo.environment[
                "FREETDSKIT_SQL_USER"], !userEnv.isEmpty
        else {
            throw EnvironmentVariableError(variableName: "FREETDSKIT_SQL_USER")
        }
        guard
            let passwordEnv = ProcessInfo.processInfo.environment[
                "FREETDSKIT_SQL_PASSWORD"], !passwordEnv.isEmpty
        else {
            throw EnvironmentVariableError(
                variableName: "FREETDSKIT_SQL_PASSWORD")
        }
        guard
            let portEnv = ProcessInfo.processInfo.environment[
                "FREETDSKIT_SQL_PORT"], !portEnv.isEmpty
        else {
            throw EnvironmentVariableError(variableName: "FREETDSKIT_SQL_PORT")
        }

        // Set the properties if all validations pass
        self.server = serverEnv
        self.username = userEnv
        self.password = passwordEnv
        self.port = portEnv
        
    }

    deinit {

    }

    @Test("Test Database Connection ")
    func testDatabaseConnection() async throws {
        print(
            "testing database connection with \(server), \(username), \(password), \(database)"
        )
        let dbConnection = try TDSConnection(
            server: "\(server):\(port)",
            username: username,
            password: password,
            database: database
        )

        #expect(dbConnection != nil)
        dbConnection.disconnect()
    }

    @Test("Test DataTypeTest Table Query")
    func testBasicQuery() async throws {
        let dbConnection = try TDSConnection(
            server: "\(server):\(port)",
            username: username,
            password: password,
            database: database
        )
        try #require(dbConnection != nil)

        let result = try dbConnection.execute(
            query: "SELECT * FROM \(testTable)")
        #expect(result != nil, "Query should return results")

        // more than one row should be returned
        #expect(
            result.affectedRows > 0, "\(testTable) table should not be empty")
        dbConnection.disconnect()
    }
    
    @Test("Test Id Column")
    func testId() async throws {
        let dbConnection = try TDSConnection(
            server: "\(server):\(port)",
            username: username,
            password: password,
            database: database
        )
        try #require(dbConnection != nil)

        let result = try dbConnection.execute(
            query: "SELECT Id FROM \(testTable)")
        #expect(result != nil, "Query should return results")
        result.rows.forEach { row in
            #expect(row["Id"] != nil)
            print("Int: \(try row["int"]!.smallInt!)")
            #expect(try row["Id"]!.smallInt! > 0)
        }
    
    }
}

// Extension to add setup to test suite
//extension FreeTDSKitIntegrationTests {
//    static func setUp() async throws {
//        try await FreeTDSKitIntegrationTestBase.setUp()
//    }
//}

struct EnvironmentVariableError: Error, CustomStringConvertible {
    let variableName: String
    var description: String {
        return
            "Environment variable '\(variableName)' is not set or is invalid."
    }
}
