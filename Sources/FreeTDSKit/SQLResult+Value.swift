import Foundation

extension SQLResult {
    public struct Value: CustomStringConvertible, CustomDebugStringConvertible {
        public let column: String
        public let value: SQLDataType?
        
        public var description: String {
            guard let value = value else { return "null" }
            switch value {
            case .uniqueidentifier(let uuid):
                return uuid.uuidString
            case .char(let string), .varchar(let string), .nchar(let string), .nvarchar(let string):
                return string
            case .numeric(let decimal), .decimal(let decimal), .money(let decimal):
                return decimal.description
            case .integer(let int):
                return "\(int)"
            case .bigInt(let int64):
                return "\(int64)"
            case .smallInt(let int16):
                return "\(int16)"
            case .tinyInt(let uint8):
                return "\(uint8)"
            case .float(let float), .real(let float):
                return "\(float)"
            case .date(let date):
                return date.debugDescription
            case .time(let time):
                return time.debugDescription
            case .datetime(let timestamp), .smalldatetime(let timestamp), .datetime2(let timestamp):
                return timestamp.debugDescription
            case .datetimeoffset(let offset):
                return offset.debugDescription
            case .bit(let bool):
                return bool ? "true" : "false"
            case .binary(let data), .varbinary(let data):
                return data.map { String(format: "%02x", $0) }.joined()
            case .spatial(let wktString):
                return wktString.value
            case .null:
                return "null"
            }
        }
        
        public var debugDescription: String { description }
        
        public var uuid: UUID? {
            if case .uniqueidentifier(let value) = value { return value }
            return nil
        }
        
        public var bool: Bool? {
            if case .bit(let value) = value { return value }
            return nil
        }
      
        public var smallInt: Int16? {
            if case .smallInt(let value) = value { return value }
            return nil
        }
        
        public var int: Int? {
            if case .integer(let value) = value { return value }
            return nil
        }
        
        public var bigInt: Int64? {
            if case .bigInt(let value) = value { return value }
            return nil
        }
        
        public var tinyInt: UInt8? {
            if case .tinyInt(let value) = value { return value }
            return nil
        }
        
        public var float: Float? {
            if case .float(let value) = value { return value }
            if case .real(let value) = value { return value }
            return nil
        }
        
        public var decimal: Decimal? {
            if case .numeric(let value) = value { return value }
            if case .decimal(let value) = value { return value }
            if case .money(let value) = value { return value }
            return nil
        }
        
        public var string: String? {
            if case .char(let value) = value { return value }
            if case .varchar(let value) = value { return value }
            if case .nchar(let value) = value { return value }
            if case .nvarchar(let value) = value { return value }
            return nil
        }
        
        public var time: TDSTime? {
            if case .time(let value) = value { return value }
            return nil
        }
        
        public var date: TDSDate? {
            if case .date(let value) = value { return value }
            return nil
        }
        
        public var dateTime: TDSDateTime? {
            if case .smalldatetime(let value) = value { return value }
            if case .datetime(let value) = value { return value }
            if case .datetime2(let value) = value { return value }
            return nil
        }
        
        public var dateTimeOffset: TDSDateTimeOffset? {
            if case .datetimeoffset(let value) = value { return value }
            return nil
        }
        
        public var binary: Data? {
            if case .binary(let value) = value { return value }
            if case .varbinary(let value) = value { return value }
            return nil
        }
    
        public var spatial: String? {
            if case .spatial (let value) = value { return value.value }
            return nil
        }
    }

    // Enable subscript for direct access
    public subscript(rowIndex: Int, column: String) -> Value? {
        guard rows.indices.contains(rowIndex), let value = rows[rowIndex][column] else { return nil }
        return Value(column: column, value: value)
    }
}
