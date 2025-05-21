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
    "FreeTDS Integration Tests")
//.disabled(if: !TestHelpers.isRunningIntegrationTests))
final class FreeTDSKitIntegrationTests {

    var server: String
    var port: String
    var username: String
    var password: String
    let database: String = "FreeTDSKitTestDB"
    let testTable: String = "DataTypeTest"

    init() async throws {
        //TODO: remove after testing
        self.server = "localhost"
        self.username = "sa"
        self.password = "YourStrongPassword1"
        self.port = "1438"
        //
        //        guard
        //            let serverEnv = ProcessInfo.processInfo.environment[
        //                "FREETDSKIT_SQL_SERVER"], !serverEnv.isEmpty
        //        else {
        //            throw EnvironmentVariableError(
        //                variableName: "FREETDSKIT_SQL_SERVER")
        //        }
        //        guard
        //            let userEnv = ProcessInfo.processInfo.environment[
        //                "FREETDSKIT_SQL_USER"], !userEnv.isEmpty
        //        else {
        //            throw EnvironmentVariableError(variableName: "FREETDSKIT_SQL_USER")
        //        }
        //        guard
        //            let passwordEnv = ProcessInfo.processInfo.environment[
        //                "FREETDSKIT_SQL_PASSWORD"], !passwordEnv.isEmpty
        //        else {
        //            throw EnvironmentVariableError(
        //                variableName: "FREETDSKIT_SQL_PASSWORD")
        //        }
        //        guard
        //            let portEnv = ProcessInfo.processInfo.environment[
        //                "FREETDSKIT_SQL_PORT"], !portEnv.isEmpty
        //        else {
        //            throw EnvironmentVariableError(variableName: "FREETDSKIT_SQL_PORT")
        //        }
        //
        //        // Set the properties if all validations pass
        //        self.server = serverEnv
        //        self.username = userEnv
        //        self.password = passwordEnv
        //        self.port = portEnv

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
        #expect(result.columns.count == 1, "Column Count Should be 1")
        #expect(result[0, "Id"]?.int == 1, "row 1 id should be 1")
    }

    @Test("Test Columns")
    func testColumns() async throws {
        let dbConnection = try TDSConnection(
            server: "\(server):\(port)",
            username: username,
            password: password,
            database: database
        )
        try #require(dbConnection != nil)

        let result = try dbConnection.execute(
            query: "SELECT * FROM \(testTable)")
        #expect(
            result.columns.count > 0, "More than one column should be returned")
        // Print the list of column names
        print("Columns:")
        for (index, column) in result.columns.enumerated() {
            print("Column \(index): \(column)")
        }

        // Print each row and its values for every column
        print("\nRows:")
        for (rowIndex, row) in result.rows.enumerated() {
            print("Row \(rowIndex):")
            for column in result.columns {
                // Attempt to get the value for this column from the row; prints 'nil' if missing.
                let value = row[column] ?? .null
                print("  \(column): \(value)")
            }
        }

    }
}

struct EnvironmentVariableError: Error, CustomStringConvertible {
    let variableName: String
    var description: String {
        return
            "Environment variable '\(variableName)' is not set or is invalid."
    }
}
