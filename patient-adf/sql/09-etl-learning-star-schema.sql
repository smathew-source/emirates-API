-- Run in any SQL Server database for a self-contained ETL exercise.
SET XACT_ABORT ON;
GO
IF SCHEMA_ID('src') IS NULL EXEC('CREATE SCHEMA src AUTHORIZATION dbo');
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg AUTHORIZATION dbo');
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw AUTHORIZATION dbo');
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl AUTHORIZATION dbo');
GO

IF OBJECT_ID('src.Customer','U') IS NULL
CREATE TABLE src.Customer (
    CustomerId int NOT NULL PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    City nvarchar(80) NOT NULL,
    CountryCode char(2) NOT NULL
);
IF OBJECT_ID('src.Product','U') IS NULL
CREATE TABLE src.Product (
    ProductId int NOT NULL PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    CategoryName nvarchar(80) NOT NULL,
    UnitPrice decimal(12,2) NOT NULL CHECK (UnitPrice >= 0)
);
IF OBJECT_ID('src.Store','U') IS NULL
CREATE TABLE src.Store (
    StoreId int NOT NULL PRIMARY KEY,
    StoreName nvarchar(100) NOT NULL,
    City nvarchar(80) NOT NULL
);
IF OBJECT_ID('src.SalesOrder','U') IS NULL
CREATE TABLE src.SalesOrder (
    OrderId int NOT NULL PRIMARY KEY,
    CustomerId int NOT NULL REFERENCES src.Customer(CustomerId),
    StoreId int NOT NULL REFERENCES src.Store(StoreId),
    OrderDate date NOT NULL,
    OrderStatus varchar(20) NOT NULL
);
IF OBJECT_ID('src.SalesOrderLine','U') IS NULL
CREATE TABLE src.SalesOrderLine (
    OrderId int NOT NULL REFERENCES src.SalesOrder(OrderId),
    LineNumber int NOT NULL,
    ProductId int NOT NULL REFERENCES src.Product(ProductId),
    Quantity int NOT NULL CHECK (Quantity > 0),
    UnitPrice decimal(12,2) NOT NULL CHECK (UnitPrice >= 0),
    CONSTRAINT PK_SalesOrderLine PRIMARY KEY (OrderId, LineNumber)
);
GO

INSERT src.Customer (CustomerId, CustomerName, City, CountryCode)
SELECT v.* FROM (VALUES
    (101,N'Ada Lovelace',N'London','GB'),
    (102,N'Alan Turing',N'Manchester','GB'),
    (103,N'Grace Hopper',N'New York','US')
) v(CustomerId,CustomerName,City,CountryCode)
WHERE NOT EXISTS (SELECT 1 FROM src.Customer t WHERE t.CustomerId=v.CustomerId);
INSERT src.Product (ProductId, ProductName, CategoryName, UnitPrice)
SELECT v.* FROM (VALUES
    (201,N'Keyboard',N'Accessories',45.00),
    (202,N'Monitor',N'Hardware',220.00),
    (203,N'Laptop',N'Hardware',950.00),
    (204,N'USB Cable',N'Accessories',12.50)
) v(ProductId,ProductName,CategoryName,UnitPrice)
WHERE NOT EXISTS (SELECT 1 FROM src.Product t WHERE t.ProductId=v.ProductId);
INSERT src.Store (StoreId, StoreName, City)
SELECT v.* FROM (VALUES
    (301,N'Central London',N'London'),
    (302,N'Northern Hub',N'Manchester')
) v(StoreId,StoreName,City)
WHERE NOT EXISTS (SELECT 1 FROM src.Store t WHERE t.StoreId=v.StoreId);
INSERT src.SalesOrder (OrderId,CustomerId,StoreId,OrderDate,OrderStatus)
SELECT v.* FROM (VALUES
    (4001,101,301,CONVERT(date,'20260901'),'Completed'),
    (4002,102,302,CONVERT(date,'20260902'),'Completed'),
    (4003,103,301,CONVERT(date,'20260903'),'Cancelled')
) v(OrderId,CustomerId,StoreId,OrderDate,OrderStatus)
WHERE NOT EXISTS (SELECT 1 FROM src.SalesOrder t WHERE t.OrderId=v.OrderId);
INSERT src.SalesOrderLine (OrderId,LineNumber,ProductId,Quantity,UnitPrice)
SELECT v.* FROM (VALUES
    (4001,1,201,2,45.00),
    (4001,2,204,3,12.50),
    (4002,1,203,1,950.00),
    (4003,1,202,1,220.00)
) v(OrderId,LineNumber,ProductId,Quantity,UnitPrice)
WHERE NOT EXISTS (
    SELECT 1 FROM src.SalesOrderLine t
    WHERE t.OrderId=v.OrderId AND t.LineNumber=v.LineNumber
);
GO

IF OBJECT_ID('stg.SalesExtract','U') IS NULL
CREATE TABLE stg.SalesExtract (
    OrderId int NOT NULL,
    LineNumber int NOT NULL,
    CustomerId int NOT NULL,
    CustomerName nvarchar(100) NOT NULL,
    CustomerCity nvarchar(80) NOT NULL,
    CountryCode char(2) NOT NULL,
    ProductId int NOT NULL,
    ProductName nvarchar(100) NOT NULL,
    CategoryName nvarchar(80) NOT NULL,
    StoreId int NOT NULL,
    StoreName nvarchar(100) NOT NULL,
    StoreCity nvarchar(80) NOT NULL,
    OrderDate date NOT NULL,
    OrderStatus varchar(20) NOT NULL,
    Quantity int NOT NULL,
    UnitPrice decimal(12,2) NOT NULL
);
IF OBJECT_ID('dw.DimDate','U') IS NULL
CREATE TABLE dw.DimDate (
    DateKey int NOT NULL PRIMARY KEY,
    CalendarDate date NOT NULL UNIQUE,
    CalendarYear smallint NOT NULL,
    CalendarMonth tinyint NOT NULL,
    MonthName varchar(20) NOT NULL
);
IF OBJECT_ID('dw.DimCustomer','U') IS NULL
CREATE TABLE dw.DimCustomer (
    CustomerKey int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerId int NOT NULL UNIQUE,
    CustomerName nvarchar(100) NOT NULL,
    City nvarchar(80) NOT NULL,
    CountryCode char(2) NOT NULL
);
IF OBJECT_ID('dw.DimProduct','U') IS NULL
CREATE TABLE dw.DimProduct (
    ProductKey int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ProductId int NOT NULL UNIQUE,
    ProductName nvarchar(100) NOT NULL,
    CategoryName nvarchar(80) NOT NULL
);
IF OBJECT_ID('dw.DimStore','U') IS NULL
CREATE TABLE dw.DimStore (
    StoreKey int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StoreId int NOT NULL UNIQUE,
    StoreName nvarchar(100) NOT NULL,
    City nvarchar(80) NOT NULL
);
IF OBJECT_ID('dw.FactSales','U') IS NULL
CREATE TABLE dw.FactSales (
    SalesKey bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId int NOT NULL,
    LineNumber int NOT NULL,
    DateKey int NOT NULL REFERENCES dw.DimDate(DateKey),
    CustomerKey int NOT NULL REFERENCES dw.DimCustomer(CustomerKey),
    ProductKey int NOT NULL REFERENCES dw.DimProduct(ProductKey),
    StoreKey int NOT NULL REFERENCES dw.DimStore(StoreKey),
    Quantity int NOT NULL CHECK (Quantity > 0),
    UnitPrice decimal(12,2) NOT NULL CHECK (UnitPrice >= 0),
    SalesAmount AS (CONVERT(decimal(14,2), Quantity * UnitPrice)) PERSISTED,
    CONSTRAINT UQ_FactSales_OrderLine UNIQUE (OrderId, LineNumber)
);
GO

CREATE OR ALTER PROCEDURE etl.LoadStarSchema
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    TRUNCATE TABLE stg.SalesExtract;
    INSERT stg.SalesExtract
    SELECT o.OrderId,l.LineNumber,c.CustomerId,c.CustomerName,c.City,c.CountryCode,
           p.ProductId,p.ProductName,p.CategoryName,s.StoreId,s.StoreName,s.City,
           o.OrderDate,o.OrderStatus,l.Quantity,l.UnitPrice
    FROM src.SalesOrder o
    JOIN src.SalesOrderLine l ON l.OrderId=o.OrderId
    JOIN src.Customer c ON c.CustomerId=o.CustomerId
    JOIN src.Product p ON p.ProductId=l.ProductId
    JOIN src.Store s ON s.StoreId=o.StoreId;

    INSERT dw.DimDate (DateKey,CalendarDate,CalendarYear,CalendarMonth,MonthName)
    SELECT DISTINCT CONVERT(int,CONVERT(char(8),OrderDate,112)),OrderDate,
           YEAR(OrderDate),MONTH(OrderDate),DATENAME(month,OrderDate)
    FROM stg.SalesExtract x
    WHERE NOT EXISTS (SELECT 1 FROM dw.DimDate d WHERE d.CalendarDate=x.OrderDate);
    INSERT dw.DimCustomer (CustomerId,CustomerName,City,CountryCode)
    SELECT DISTINCT CustomerId,CustomerName,CustomerCity,CountryCode
    FROM stg.SalesExtract x
    WHERE NOT EXISTS (SELECT 1 FROM dw.DimCustomer d WHERE d.CustomerId=x.CustomerId);
    INSERT dw.DimProduct (ProductId,ProductName,CategoryName)
    SELECT DISTINCT ProductId,ProductName,CategoryName
    FROM stg.SalesExtract x
    WHERE NOT EXISTS (SELECT 1 FROM dw.DimProduct d WHERE d.ProductId=x.ProductId);
    INSERT dw.DimStore (StoreId,StoreName,City)
    SELECT DISTINCT StoreId,StoreName,StoreCity
    FROM stg.SalesExtract x
    WHERE NOT EXISTS (SELECT 1 FROM dw.DimStore d WHERE d.StoreId=x.StoreId);

    INSERT dw.FactSales (OrderId,LineNumber,DateKey,CustomerKey,ProductKey,StoreKey,Quantity,UnitPrice)
    SELECT x.OrderId,x.LineNumber,d.DateKey,c.CustomerKey,p.ProductKey,s.StoreKey,x.Quantity,x.UnitPrice
    FROM stg.SalesExtract x
    JOIN dw.DimDate d ON d.CalendarDate=x.OrderDate
    JOIN dw.DimCustomer c ON c.CustomerId=x.CustomerId
    JOIN dw.DimProduct p ON p.ProductId=x.ProductId
    JOIN dw.DimStore s ON s.StoreId=x.StoreId
    WHERE x.OrderStatus='Completed'
      AND NOT EXISTS (
          SELECT 1 FROM dw.FactSales f
          WHERE f.OrderId=x.OrderId AND f.LineNumber=x.LineNumber
      );
    COMMIT;
END;
GO

EXEC etl.LoadStarSchema;
GO

SELECT d.CalendarYear,d.MonthName,p.CategoryName,
       SUM(f.Quantity) AS UnitsSold,SUM(f.SalesAmount) AS Revenue
FROM dw.FactSales f
JOIN dw.DimDate d ON d.DateKey=f.DateKey
JOIN dw.DimProduct p ON p.ProductKey=f.ProductKey
GROUP BY d.CalendarYear,d.MonthName,p.CategoryName
ORDER BY d.CalendarYear,d.MonthName,p.CategoryName;
GO