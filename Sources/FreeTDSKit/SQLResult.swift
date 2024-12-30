//
//  SQLResult
//  FreeTDSKit
//
//  Created by David Oliver on 12/28/24.
//

import Foundation

public struct SQLResult {
    public let columns: [String: String]
    
    public init(columns: [String: String]) {
        self.columns = columns
    }
}
