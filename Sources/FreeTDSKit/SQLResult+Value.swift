import Foundation

extension SQLResult {
    public struct Value: CustomStringConvertible, CustomDebugStringConvertible {

        public let column: String
        let raw: SQLDataType

        // delegate
        public var uuid           : UUID?               { raw.uuid }
        public var bool           : Bool?               { raw.bool }
        public var smallInt       : Int16?              { raw.smallInt }
        public var int            : Int?                { raw.int }
        public var bigInt         : Int64?              { raw.bigInt }
        public var tinyInt        : UInt8?              { raw.tinyInt }
        public var double         : Double?             { raw.double }
        public var float          : Float?              { raw.float }
        public var decimal        : Decimal?            { raw.decimal }
        public var string         : String?             { raw.string }
        public var time           : TDSTime?            { raw.time }
        public var date           : TDSDate?            { raw.date }
        public var dateTime       : TDSDateTime?        { raw.dateTime }
        public var dateTimeOffset : TDSDateTimeOffset?  { raw.dateTimeOffset }
        public var binary         : Data?               { raw.binary }
        public var spatial        : String?             { raw.spatial }

        // MARK: – Description

        public var description: String {
            if let s = raw.string                         { return s }
            if let uuid = raw.uuid                       { return uuid.uuidString }
            if let dec = raw.decimal                     { return dec.description }
            if let dbl = raw.double                      { return String(dbl) }
            if let flt = raw.float                       { return String(flt) }
            if let i   = raw.int                         { return String(i) }
            if let bi  = raw.bigInt                      { return String(bi) }
            if let si  = raw.smallInt                    { return String(si) }
            if let ti  = raw.tinyInt                     { return String(ti) }
            if let b   = raw.bool                        { return b ? "true" : "false" }
            if let ts  = raw.dateTime                    { return ts.debugDescription }
            if let d   = raw.date                        { return d.debugDescription }
            if let t   = raw.time                        { return t.debugDescription }
            if let off = raw.dateTimeOffset              { return off.debugDescription }
            if let data = raw.binary {
                return data.map { String(format: "%02x", $0) }.joined()
            }
            if let wkt = raw.spatial                     { return wkt }
            return "null"
        }


        public var debugDescription: String { description }
    }

}

extension SQLResult.Value: Sendable {}


