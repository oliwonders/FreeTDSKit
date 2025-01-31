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

        // Convenient typed accessors
        public var int: Int? {
            if case .integer(let value) = value { return value }
            return nil
        }

        public var smallInt: Int16? {
            if case .smallInt(let value) = value { return value }
            return nil
        }

        public var string: String? {
            if case .char(let value) = value { return value }
            if case .varchar(let value) = value { return value }
            if case .nchar(let value) = value { return value }
            if case .nvarchar(let value) = value { return value }
            return nil
        }
        
        // Add more computed properties for other SQLDataTypes as needed.
    }

    // Enable subscript for direct access
    public subscript(rowIndex: Int, column: String) -> Value? {
        guard rows.indices.contains(rowIndex), let value = rows[rowIndex][column] else { return nil }
        return Value(column: column, value: value)
    }
}
