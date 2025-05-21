import CFreeTDS
import Foundation

public enum SQLDataType {
    case uniqueidentifier(UUID)
    case char(String)
    case varchar(String)
    case nchar(String)
    case nvarchar(String)
    case text(String)
    case numeric(Decimal)
    case decimal(Decimal)
    case money(Decimal)
    case integer(Int)
    case smallInt(Int16)
    case bigInt(Int64)
    case tinyInt(UInt8)
    case float(Float)
    case real(Float)
    case double(Double)
    case date(TDSDate)
    case time(TDSTime)
    case datetime(TDSDateTime)
    case smalldatetime(TDSDateTime)
    case datetime2(TDSDateTime)
    case datetimeoffset(TDSDateTimeOffset)
    case bit(Bool)
    case binary(Data)
    case varbinary(Data)
    case spatial(WKTString)
    case null

    public struct WKTString: Equatable {
        let value: String
    }
}

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

public struct TDSDateTime: Equatable, Codable, CustomDebugStringConvertible {
    public var date: TDSDate
    public var hour: Int
    public var minute: Int
    public var second: Int
    public var fractionalSecond: Int

    public var debugDescription: String {
        "\(date.debugDescription), \(hour):\(minute):\(second).\(fractionalSecond)"
    }

    public init(
        date: TDSDate,
        hour: Int,
        minute: Int,
        second: Int,
        fractionalSecond: Int
    ) {
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
        self.fractionalSecond = fractionalSecond
    }
}

public struct TDSDateTimeOffset: Equatable, Codable,
    CustomDebugStringConvertible
{
    public var date: TDSDate
    public var time: TDSTime
    public var fractionalSecond: Int
    public var offset: Int  // Offset in minutes

    public var debugDescription: String {
        "\(date.debugDescription), \(time.debugDescription).\(fractionalSecond) (Offset: \(offset) minutes)"
    }

    public init(
        date: TDSDate,
        time: TDSTime,
        fractionalSecond: Int,
        offset: Int
    ) {
        self.date = date
        self.time = time
        self.fractionalSecond = fractionalSecond
        self.offset = offset
    }
}

//these are not available via FreeTDS
public let SYBGEOGRAPHY: Int = 240  // Actual value from SQL Server
public let SYBGEOMETRY: Int = 241  // Actual value from SQL Server

func determineSQLType(_ colValue: UnsafePointer<CChar>, columnType: Int)
    -> SQLDataType
{

    switch columnType {
    case 36:  // uniqueidentifier
        if let uuid = UUID(uuidString: String(cString: colValue)) {
            return .uniqueidentifier(uuid)
        }
    case 40:  // Date type
        let dateParts = String(cString: colValue).split(separator: "-")
            .compactMap { Int($0) }
        if dateParts.count == 3 {
            return .date(
                TDSDate(
                    day: dateParts[2],
                    month: dateParts[1],
                    year: dateParts[0]
                )
            )
        }
    case 41:  // Time type
        let timeString = String(cString: colValue).split(separator: ":")
            .compactMap { Int($0) }
        if timeString.count == 3 {
            return .time(
                TDSTime(
                    hour: timeString[0],
                    minute: timeString[1],
                    second: timeString[2]
                )
            )
        }
    case 42:  // datetime2
        // Extracts higher precision seconds
        let dateTimeParts = String(cString: colValue).split(separator: ".")
        if let dateTime = dateTimeParts.first {
            let dateAndTime = dateTime.split(separator: " ")
            if dateAndTime.count == 2 {
                let dateParts = dateAndTime[0].split(separator: "-").compactMap
                { Int($0) }
                let timeParts = dateAndTime[1].split(separator: ":").compactMap
                { Int($0) }
                let fractionalSeconds = Int(dateTimeParts.last ?? "0") ?? 0
                if dateParts.count == 3, timeParts.count == 3 {
                    let date = TDSDate(
                        day: dateParts[2],
                        month: dateParts[1],
                        year: dateParts[0]
                    )
                    let timestamp = TDSDateTime(
                        date: date,
                        hour: timeParts[0],
                        minute: timeParts[1],
                        second: timeParts[2],
                        fractionalSecond: fractionalSeconds
                    )
                    return .datetime2(timestamp)
                }
            }
        }
    case 43:  // DateTimeOffset type
        let dateTimeParts = String(cString: colValue).split(separator: " ")
        if dateTimeParts.count == 3 {
            // Extract date, time, and offset parts
            let dateParts = dateTimeParts[0].split(separator: "-").compactMap {
                Int($0)
            }
            let timeParts = dateTimeParts[1].split(separator: ":").compactMap {
                Int($0)
            }
            let offsetString = String(dateTimeParts[2])

            // Parse offset
            let sign = offsetString.hasPrefix("-") ? -1 : 1
            let offsetParts = offsetString.dropFirst().split(separator: ":")
                .compactMap { Int($0) }
            if offsetParts.count == 2 {
                let offset = sign * (offsetParts[0] * 60 + offsetParts[1])  // Convert to minutes

                if dateParts.count == 3, timeParts.count == 3 {
                    let date = TDSDate(
                        day: dateParts[2],
                        month: dateParts[1],
                        year: dateParts[0]
                    )
                    let time = TDSTime(
                        hour: timeParts[0],
                        minute: timeParts[1],
                        second: timeParts[2]
                    )
                    let fractionalSecond = 0  // Assuming no fractional second for this case
                    return .datetimeoffset(
                        TDSDateTimeOffset(
                            date: date,
                            time: time,
                            fractionalSecond: fractionalSecond,
                            offset: offset
                        )
                    )
                }
            }
        }
    case SYBINT1:  //sql server type 48
        if let value = UInt8(String(cString: colValue)) {
            return .tinyInt(value)
        }
    case SYBINT2:  //sql server type 52
        if let value = Int16(String(cString: colValue)) {
            return .smallInt(value)
        }
    case SYBINT4:  //sql server type 56
        if let value = Int32(String(cString: colValue)) {
            return .integer(Int(value))
        }
    case 58:  // smalldatetime
        // Similar to datetime but truncates seconds
        let dateTimeParts = String(cString: colValue).split(separator: " ")
        if dateTimeParts.count == 2 {
            let dateParts = dateTimeParts[0].split(separator: "-").compactMap {
                Int($0)
            }
            let timeParts = dateTimeParts[1].split(separator: ":").compactMap {
                Int($0)
            }
            if dateParts.count == 3,
                timeParts.count >= 2
            {
                let date = TDSDate(
                    day: dateParts[2],
                    month: dateParts[1],
                    year: dateParts[0]
                )
                let timestamp = TDSDateTime(
                    date: date,
                    hour: timeParts[0],
                    minute: timeParts[1],
                    second: 0,
                    fractionalSecond: 0
                )
                return .smalldatetime(timestamp)
            }
        }
    case 61:  // datetime
        let dateTimeParts = String(cString: colValue).split(separator: " ")
        if dateTimeParts.count == 2 {
            let dateParts = dateTimeParts[0].split(separator: "-").compactMap {
                Int($0)
            }
            let timeParts = dateTimeParts[1].split(separator: ":").compactMap {
                Int($0)
            }
            if dateParts.count == 3,
                timeParts.count == 3
            {
                let date = TDSDate(
                    day: dateParts[2],
                    month: dateParts[1],
                    year: dateParts[0]
                )
                let timestamp = TDSDateTime(
                    date: date,
                    hour: timeParts[0],
                    minute: timeParts[1],
                    second: timeParts[2],
                    fractionalSecond: 0
                )
                return .datetime(timestamp)
            }
        }
    case SYBFLT8:  // 8-byte FLOAT
        if let v = Double(String(cString: colValue)) {
            return .double(v)
        }
    case SYBINT8:  //sql server type 127
        if let value = Int64(String(cString: colValue)) {
            return .bigInt(value)
        }
    case SYBREAL:
        if let value = Float(String(cString: colValue)) {
            return .real(value)
        }
    case SYBCHAR:  //sql server type 175 and nchar is 239
        return .char(String(cString: colValue))
    case SYBNVARCHAR:
        return .nvarchar(String(cString: colValue))
    case 239:
        return .nchar(String(cString: colValue))
    case SYBVARCHAR:  //sql server type 167
        return .varchar(String(cString: colValue))
    case SYBTEXT, 99:  // 99 = SYBNTEXT (Unicode)
        return .text(String(cString: colValue))
    case SYBBINARY, SYBVARBINARY:  //sql server type 165, 173
        let dataLength = strlen(colValue)
        let data = Data(bytes: colValue, count: Int(dataLength))
        return .binary(data)
    case SYBBIT:
        let valueStr = String(cString: colValue).lowercased()
        if valueStr == "1" || valueStr == "true" {
            return .bit(true)
        } else if valueStr == "0" || valueStr == "false" {
            return .bit(false)
        }
        return .null
    case 60:  //money
        if let value = Decimal(string: String(cString: colValue)) {
            return .money(value)
        }
    case SYBMONEY, SYBMONEY4:
        if let value = Decimal(string: String(cString: colValue)) {
            // Round to the expected precision for money types
            return .money(value.rounded(scale: 2))
        }
    case SYBDECIMAL, SYBNUMERIC:
        if let value = Decimal(string: String(cString: colValue)) {
            return .decimal(value)
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

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, scale, .plain)
        return result
    }
}
public extension SQLDataType {

    // MARK: – Scalar look-ups

    var uuid: UUID? {
        if case .uniqueidentifier(let v) = self { return v }
        return nil
    }

    var bool: Bool? {
        if case .bit(let v) = self { return v }
        return nil
    }

    var int: Int? {
        switch self {
        case .integer(let v):  return v
        case .bigInt(let v):   return Int(v)
        case .bit(let b):      return b ? 1 : 0
        default:               return nil
        }
    }

    var bigInt: Int64? {
        if case .bigInt(let v) = self { return v }
        return nil
    }

    var smallInt: Int16? {
        if case .smallInt(let v) = self { return v }
        return nil
    }

    var tinyInt: UInt8? {
        if case .tinyInt(let v) = self { return v }
        return nil
    }

    var double: Double? {
        switch self {
        case .double(let v):             return v
        case .float(let v), .real(let v): return Double(v)
        case .decimal(let d), .money(let d), .numeric(let d):
            return (d as NSDecimalNumber).doubleValue
        default: return nil
        }
    }

    var float: Float? {
        switch self {
        case .float(let v), .real(let v): return v
        default: return nil
        }
    }

    var decimal: Decimal? {
        switch self {
        case .decimal(let v), .numeric(let v), .money(let v): return v
        default: return nil
        }
    }

    var string: String? {
        switch self {
        case .char(let s), .varchar(let s),
             .nchar(let s), .nvarchar(let s),
             .text(let s):
            return s
        default: return nil
        }
    }

    // MARK: – Temporal helpers (raw structs)

    var date: TDSDate? {
        if case .date(let v) = self { return v }
        return nil
    }

    var time: TDSTime? {
        if case .time(let v) = self { return v }
        return nil
    }

    var dateTime: TDSDateTime? {
        switch self {
        case .datetime(let v), .datetime2(let v), .smalldatetime(let v):
            return v
        default: return nil
        }
    }

    var dateTimeOffset: TDSDateTimeOffset? {
        if case .datetimeoffset(let v) = self { return v }
        return nil
    }

    // MARK: – Binary & Spatial

    var binary: Data? {
        switch self {
        case .binary(let d), .varbinary(let d): return d
        default: return nil
        }
    }

    var spatial: String? {
        if case .spatial(let wkt) = self { return wkt.value }
        return nil
    }
}
