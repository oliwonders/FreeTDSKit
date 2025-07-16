-- Check if the database exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'FreeTDSKitTestDB')
BEGIN
    CREATE DATABASE FreeTDSKitTestDB;
END
GO

-- Use the test database
USE FreeTDSKitTestDB;
GO

-- Check if the table exists
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DataTypeTest]') AND type in (N'U'))
BEGIN
    CREATE TABLE DataTypeTest (
        Id INT PRIMARY KEY IDENTITY(1,1),         -- Auto-incrementing primary key
        CharColumn CHAR(10) NOT NULL,             -- Fixed-length character data
        VarCharColumn VARCHAR(50) NOT NULL,       -- Variable-length character data
        IntColumn INT NOT NULL,                   -- Integer
        SmallIntColumn SMALLINT NOT NULL,         -- Small integer
        BigIntColumn BIGINT NOT NULL,             -- Large integer
        DecimalColumn DECIMAL(10, 2) NOT NULL,    -- Fixed precision decimal
        FloatColumn FLOAT NOT NULL,               -- Floating-point number
        RealColumn REAL NOT NULL,                 -- Approximate floating-point
        BitColumn BIT NOT NULL,                   -- Boolean-like column
        DateColumn DATE NOT NULL,                 -- Date without time
        TimeColumn TIME NOT NULL,                 -- Time without date
        DateTimeColumn DATETIME NOT NULL,         -- Date and time
        SmallDateTimeColumn SMALLDATETIME NOT NULL, -- Date and time with less precision
        DateTime2Column DATETIME2(7) NOT NULL,   -- More precise date and time
        DateTimeOffsetColumn DATETIMEOFFSET(7) NOT NULL, -- Date and time with timezone offset
        MoneyColumn MONEY NOT NULL,               -- Monetary values
        SmallMoneyColumn SMALLMONEY NOT NULL,     -- Smaller monetary values
        NCharColumn NCHAR(10) NOT NULL,           -- Fixed-length Unicode character data
        NVarCharColumn NVARCHAR(50) NOT NULL,     -- Variable-length Unicode character data
        BinaryColumn BINARY(10),                  -- Fixed-length binary data
        VarBinaryColumn VARBINARY(50),            -- Variable-length binary data
        SpatialColumn GEOGRAPHY NULL,                 -- Spatial data
        ComputedSpatialColumnLat  AS ([SpatialColumn].[Lat]),
        ComputedSpatialColumnLong  AS ([SpatialColumn].[Long]),
        UniqueIdentifierColumn [uniqueidentifier] NOT NULL -- Unique Id
    );
END
GO

    ALTER TABLE [DataTypeTest] ADD  DEFAULT (newid()) FOR [UniqueIdentifierColumn]
    GO
-- Insert sample data if the table is empty
IF NOT EXISTS (SELECT 1 FROM DataTypeTest)
BEGIN
    INSERT INTO DataTypeTest (
        CharColumn, VarCharColumn, IntColumn, SmallIntColumn, BigIntColumn,
        DecimalColumn, FloatColumn, RealColumn, BitColumn, DateColumn,
        TimeColumn, DateTimeColumn, SmallDateTimeColumn, DateTime2Column,
        DateTimeOffsetColumn, MoneyColumn, SmallMoneyColumn, NCharColumn,
        NVarCharColumn, BinaryColumn, VarBinaryColumn, SpatialColumn
    )
    VALUES
        ('FixedChar', 'VariableChar', 42, 123, 9223372036854775807,
        12345.67, 3.141592653589793, 1.23, 1, '2024-12-28',
        '12:34:56', '2024-12-28 12:34:56', '2024-12-28 12:34:00',
        '2024-12-28 12:34:56.1234567', '2024-12-28 12:34:56.1234567 +00:00',
        1000000.99, 12345.67, N'UnicodeFix', N'UnicodeVar',
        0x0102030405060708090A, 0x010203,
        geography::STGeomFromText('POINT(-122.335167 47.608013)', 4326)),
        
        ('Another', 'TestString', -42, -123, -9223372036854775808,
        -12345.67, -3.14, -1.23, 0, '2024-12-29',
        '23:59:59', '2024-12-29 23:59:59', '2024-12-29 23:59:00',
        '2024-12-29 23:59:59.7654321', '2024-12-29 23:59:59.7654321 -08:00',
        -1000000.99, -12345.67, N'AnotherFix', N'AnotherVar',
        0x0A0B0C0D0E0F10111213, NULL,
        geography::STGeomFromText('POINT(-118.243683 34.052235)', 4326));
END

-- Check if the table exists
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[UpdateTableTest]') AND type in (N'U'))
BEGIN
    CREATE TABLE UpdateTableTest (
        Id INT PRIMARY KEY IDENTITY(1,1),         -- Auto-incrementing primary key
        Text VARCHAR(50) NOT NULL,       -- Variable-length character data
    );
END
GO
GO
