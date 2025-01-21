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
    
}
