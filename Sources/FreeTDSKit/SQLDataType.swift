import Foundation
import CFreeTDS

public struct TDSTime: Equatable, Codable, CustomDebugStringConvertible {
    public var hour: Int
    public var minute: Int
    public var second: Int
    
    public var debugDescription: String {
        "\(hour):\(minute):\(second)"
    }
    
    public init(hour: Int, minute: Int, second: Int) {
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

public struct TDSDate: Equatable, Codable, CustomDebugStringConvertible {
    public var day: Int
    public var month: Int
    public var year: Int
    
    public var debugDescription: String {
        "\(month) \(day), \(year)"
    }
    
    public init(day: Int, month: Int, year: Int) {
        self.day = day
        self.month = month
        self.year = year
    }
}

public struct TDSTimestamp: Equatable, Codable, CustomDebugStringConvertible {
    public var date: TDSDate
    public var hour: Int
    public var minute: Int
    public var second: Int
    public var fractionalSecond: Int
    
    public var debugDescription: String {
        "\(date.debugDescription), \(hour):\(minute):\(second).\(fractionalSecond)"
    }
    
    public init(date: TDSDate, hour: Int, minute: Int, second: Int, fractionalSecond: Int) {
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
        self.fractionalSecond = fractionalSecond
    }
}

// Define the data types enum
public enum SQLDataType {
    case char(String)
    case numeric(Decimal)
    case decimal(Decimal)
    case integer(Int)
    case smallInt(Int16)
    case float(Float)
    case real(Float)
    case double(Double)
    case date(TDSDate)
    case time(TDSTime)
    case timestamp(TDSTimestamp)
    case varchar(String)
    case binary(Data)
    case varbinary(Data)
    case bigInt(Int64)
    case tinyInt(UInt8)
    case bit(Bool)
    case spatial(WKTString)
    //case guid()
    case null

    public struct WKTString {
        let value: String
    }
}

//these are not available via FreeTDS
public let SYBGEOGRAPHY: Int = 240  // Actual value from SQL Server
public let SYBGEOMETRY: Int = 241   // Actual value from SQL Server

func determineSQLType(_ colValue: UnsafePointer<CChar>, columnType: Int) -> SQLDataType {
    switch columnType {
    case SYBINT1:
        if let value = UInt8(String(cString: colValue)) {
            return .tinyInt(value)
        }
    case SYBINT2:
        if let value = Int16(String(cString: colValue)) {
            return .smallInt(value)
        }
    case SYBINT4:
        if let value = Int32(String(cString: colValue)) {
            return .integer(Int(value))
        }
    case SYBINT8:
        if let value = Int64(String(cString: colValue)) {
            return .bigInt(value)
        }
    case SYBFLT8:
        if let value = Double(String(cString: colValue)) {
            return .double(value)
        }
    case SYBREAL:
        if let value = Float(String(cString: colValue)) {
            return .real(value)
        }
    case SYBCHAR:
        return .char(String(cString: colValue))
    case SYBVARCHAR:
        return .varchar(String(cString: colValue))
    case SYBBINARY, SYBVARBINARY:
        let dataLength = strlen(colValue)
        let data = Data(bytes: colValue, count: Int(dataLength))
        return .binary(data)
    case SYBBIT:
        if let value = Int(String(cString: colValue)) {
            return .bit(value != 0)
        }
    case 106: // Decimal type
        if let value = Decimal(string: String(cString: colValue)) {
            return .decimal(value)
        }
    case 40: // Date type
        let dateParts = String(cString: colValue).split(separator: "-").compactMap { Int($0) }
        if dateParts.count == 3 {
            return .date(TDSDate(day: dateParts[2], month: dateParts[1], year: dateParts[0]))
        }
    case 41: // Time type
        let timeString = String(cString: colValue).split(separator: ":").compactMap { Int($0) }
           if timeString.count == 3 {
            return .time(TDSTime(hour: timeString[0], minute: timeString[1], second: timeString[2]))
        }
    case 61: // DateTime type
        let dateTimeParts = String(cString: colValue).split(separator: " ")
        if dateTimeParts.count == 2 {
            let dateParts = dateTimeParts[0].split(separator: "-").compactMap { Int($0) }
            let timeParts = dateTimeParts[1].split(separator: ":").compactMap { Int($0) }
            if dateParts.count == 3,
               timeParts.count == 3 {
                let date = TDSDate(day: dateParts[2], month: dateParts[1], year: dateParts[0])
                let time = TDSTimestamp(date: date,
                                        hour: timeParts[0],
                                        minute: timeParts[1],
                                        second: timeParts[2],
                                        fractionalSecond: 0)
                return .timestamp(time)
            }
        }
    case SYBGEOGRAPHY, SYBGEOMETRY:
        let colAsString = String(cString: colValue)
        let spatialWKT = SQLDataType.WKTString(value: colAsString)
        return .spatial(spatialWKT)
    default:
        print("Unknown column type: \(columnType)")
        return .null
    }
    return .null
}
