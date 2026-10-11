use RetailOLTP

-- import ProductCatalog
-- tasks --> import flat file 

Select * from ProductCatalog
select * from Customers
select * from OrderLines
select * from Orders
select * from stores
-------------------------------------------------
-- Now we have 4 tables in Bronze layer
-------------------------------------------------

-- Silver layer :
-- Cleaning and Transformation

-- ProductCatalog Table:

Select * from ProductCatalog

ALTER TABLE ProductCatalog
ALTER COLUMN LastModifiedAt DATETIME;

EXEC sp_help 'ProductCatalog';


ALTER TABLE ProductCatalog
DROP CONSTRAINT PK_ProductCatalog;

ALTER TABLE ProductCatalog
ALTER COLUMN ProductID int NOT NULL;

ALTER TABLE ProductCatalog
ADD CONSTRAINT PK_ProductCatalog PRIMARY KEY (ProductID);

ALTER TABLE ProductCatalog
ALTER COLUMN IsActive char(1) NOT NULL;

-- Customers Table :

select * from Customers

ALTER TABLE Customers
ALTER COLUMN LastModifiedAt datetime NOT NULL;


-- OrderLines Table:

select * from OrderLines

ALTER TABLE OrderLines
ALTER COLUMN UnitPrice float NOT NULL;

ALTER TABLE OrderLines
ALTER COLUMN DiscountAmount float NOT NULL;

ALTER TABLE OrderLines
ALTER COLUMN LastModifiedAt datetime NOT NULL;
 
-- Orders Table:

select * from Orders

ALTER TABLE Orders
ALTER COLUMN OrderDate datetime NOT NULL;

ALTER TABLE Orders
ALTER COLUMN LastModifiedAt datetime NOT NULL;

-- Stores Table

select * from stores

ALTER TABLE stores
ALTER COLUMN LastModifiedAt datetime NOT NULL;


-------------------------------------------------------------------------

-- Gold layer:

-- DimDate:
create schema dim

CREATE TABLE dim.DimDate
(
    DateKey INT NOT NULL PRIMARY KEY,
    FullDate DATE NOT NULL UNIQUE,
    DayNumber INT NOT NULL,
    MonthNumber INT NOT NULL,
    MonthName NVARCHAR(20) NOT NULL,
    QuarterNumber INT NOT NULL,
    YearNumber INT NOT NULL
);
GO
;WITH DateCTE AS
(
    SELECT CAST('2020-01-01' AS DATE) AS FullDate

    UNION ALL

    SELECT DATEADD(DAY, 1, FullDate)
    FROM DateCTE
    WHERE FullDate < '2030-12-31'
)

INSERT INTO dim.DimDate
(
    DateKey,
    FullDate,
    DayNumber,
    MonthNumber,
    MonthName,
    QuarterNumber,
    YearNumber
)
SELECT
    CAST(CONVERT(VARCHAR(8), FullDate, 112) AS INT),
    FullDate,
    DAY(FullDate),
    MONTH(FullDate),
    DATENAME(MONTH, FullDate),
    DATEPART(QUARTER, FullDate),
    YEAR(FullDate)
FROM DateCTE
OPTION (MAXRECURSION 0);
GO

-- DimProduct:

CREATE TABLE dim.DimProduct (
    ProductKey INT IDENTITY(1,1) CONSTRAINT PK_DimProduct PRIMARY KEY,
    ProductID INT NOT NULL,
    SKU NVARCHAR(100),
    ProductName NVARCHAR(255),
    Category NVARCHAR(100),
    Brand NVARCHAR(100),
    UnitCost DECIMAL(18,2),
    StartDate DATETIME NOT NULL,
    EndDate DATETIME NULL
);

INSERT INTO dim.DimProduct (
    ProductID, SKU, ProductName, Category, Brand, UnitCost, StartDate, EndDate
)
SELECT 
    ProductID, 
    SKU, 
    ProductName, 
    Category, 
    Brand, 
    UnitCost,
    SYSUTCDATETIME() AS StartDate,
    NULL AS EndDate
FROM dbo.ProductCatalog;


select * from dim.DimProduct

-- DimCustomer :


CREATE TABLE dim.DimCustomer (
    CustomerKey  INT IDENTITY(1,1) CONSTRAINT PK_DimCustomer PRIMARY KEY,
    CustomerID   INT NOT NULL CONSTRAINT UQ_DimCustomer_CustomerID UNIQUE,
    CustomerName NVARCHAR(255) NOT NULL,
    City         NVARCHAR(100),
    Region       NVARCHAR(100),
    Email        NVARCHAR(255)
);

INSERT INTO dim.DimCustomer (
    CustomerID,
    CustomerName,
    City,
    Region,
    Email
)
SELECT 
    CustomerID,
    CustomerName,
    City,
    Region,
    Email
FROM dbo.Customers; 

select * from dim.DimCustomer

-- DimStore:


CREATE TABLE dim.DimStore (
    StoreKey   INT IDENTITY(1,1) CONSTRAINT PK_DimStore PRIMARY KEY,
    StoreID    INT NOT NULL CONSTRAINT UQ_DimStore_StoreID UNIQUE,
    StoreName  NVARCHAR(255) NOT NULL,
    City       NVARCHAR(100),
    Region     NVARCHAR(100)
);


INSERT INTO dim.DimStore (
    StoreID,
    StoreName,
    City,
    Region
)
SELECT 
    StoreID,
    StoreName,
    City,
    Region
FROM dbo.Stores; 

select * from dim.DimStore
select * from dim.DimDate


-- Fact Table

CREATE SCHEMA fact;

CREATE TABLE fact.FactSales (
    SalesKey             BIGINT IDENTITY(1,1) CONSTRAINT PK_FactSales PRIMARY KEY, 
    SourceOrderLineID    INT NOT NULL CONSTRAINT UQ_FactSales_SourceOrderLineID UNIQUE,
    OrderID              INT NOT NULL,         
    DateKey              INT NOT NULL,
    CustomerKey          INT NOT NULL,
    StoreKey             INT NOT NULL,
    ProductKey           INT NOT NULL,
    Quantity             INT NOT NULL,
    UnitPrice            DECIMAL(18,2) NOT NULL,
    GrossSales           DECIMAL(18,2) NOT NULL,
    DiscountAmount       DECIMAL(18,2) NOT NULL DEFAULT 0,
    NetSales             DECIMAL(18,2) NOT NULL,
    LoadedAt             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_FactSales_DimDate     FOREIGN KEY (DateKey)     REFERENCES dim.DimDate(DateKey),
    CONSTRAINT FK_FactSales_DimCustomer FOREIGN KEY (CustomerKey) REFERENCES dim.DimCustomer(CustomerKey),
    CONSTRAINT FK_FactSales_DimStore    FOREIGN KEY (StoreKey)    REFERENCES dim.DimStore(StoreKey),
    CONSTRAINT FK_FactSales_DimProduct  FOREIGN KEY (ProductKey)  REFERENCES dim.DimProduct(ProductKey)
);

INSERT INTO fact.FactSales (
    SourceOrderLineID,
    OrderID,
    DateKey,
    CustomerKey,
    StoreKey,
    ProductKey,
    Quantity,
    UnitPrice,
    GrossSales,
    DiscountAmount,
    NetSales,
    LoadedAt
)
SELECT 
    dbo.OrderLines.OrderLineID AS SourceOrderLineID,
    dbo.Orders.OrderID AS OrderID,
    
    CONVERT(INT, CONVERT(VARCHAR(8), dbo.Orders.OrderDate, 112)) AS DateKey,
    dim.DimCustomer.CustomerKey,
    dim.DimStore.StoreKey,
    dim.DimProduct.ProductKey,
    dbo.OrderLines.Quantity,
    dbo.OrderLines.UnitPrice,
    
    (dbo.OrderLines.Quantity * dbo.OrderLines.UnitPrice)    AS GrossSales,
    ISNULL(dbo.OrderLines.DiscountAmount, 0)                AS DiscountAmount,
    (dbo.OrderLines.Quantity * dbo.OrderLines.UnitPrice) - ISNULL(dbo.OrderLines.DiscountAmount, 0) AS NetSales,  SYSUTCDATETIME()AS LoadedAt

FROM dbo.OrderLines
JOIN dbo.Orders 
    ON dbo.OrderLines.OrderID = dbo.Orders.OrderID
JOIN dim.DimCustomer 
    ON dbo.Orders.CustomerID = dim.DimCustomer.CustomerID
JOIN dim.DimStore 
    ON dbo.Orders.StoreID = dim.DimStore.StoreID
JOIN dim.DimProduct 
    ON dbo.OrderLines.ProductID = dim.DimProduct.ProductID 
   AND (dim.DimProduct.EndDate IS NULL OR dbo.Orders.OrderDate BETWEEN dim.DimProduct.StartDate AND dim.DimProduct.EndDate);


   select * from fact.FactSales

