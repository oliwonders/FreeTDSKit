import Foundation
import Testing
@testable import FreeTDSKit

//#if INTEGRATON_TESTS

@Suite("FreeTDS Integration Tests")
struct FreeTDSKitIntegrationTests  {
   
    let server: String = "127.0.0.1"
    let username: String = "sa"
    let password: String = "yourStrongPassword1"
    let database: String = "FreeTDSKitTestDB"
    let testTable: String = "DataTypeTest"
    
    
    @Test("FreeTDS Version Check")
    func testFreeTDSVersion() async throws {
        let version = FreeTDSKit.getFreeTDSVersion()
        #expect(!version.isEmpty)
    }
    
    @Test("Database Connection")
    func testDatabaseConnection() async throws {
        let dbConnection = try TDSConnection(
            server: server,
            username: username,
            password: password,
            database: database
        )
        
        #expect(dbConnection != nil)
        dbConnection.disconnect()
    }
    
    @Test("Test DataTypeTest Table Query")
    func testTerritoryTableQuery() async throws {
        let dbConnection = try TDSConnection(
            server: server,
            username: username,
            password: password,
            database: database
        )
        
        let result = try dbConnection.execute(query: "SELECT * FROM \(testTable)")
        #expect(result != nil, "Query should return results")
        
        // Additional assertions can be added here
        // #assert(result.count > 0, "Territory table should not be empty")
        // if let firstRow = result.first {
        //     #assert(firstRow["Name"] != nil)
        //     #assert(firstRow["Description"] != nil)
        // }
    }
}


// Extension to add setup to test suite
extension FreeTDSKitIntegrationTests {
    static func setUp() async throws {
        try await FreeTDSKitIntegrationTestBase.setUp()
    }
}

//#endif
