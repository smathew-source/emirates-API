PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS dw_fact_sales;
DROP TABLE IF EXISTS dw_dim_customer;
DROP TABLE IF EXISTS dw_dim_product;
DROP TABLE IF EXISTS dw_dim_store;
DROP TABLE IF EXISTS dw_dim_date;
DROP TABLE IF EXISTS stg_sales_extract;
DROP TABLE IF EXISTS src_sales_order_line;
DROP TABLE IF EXISTS src_sales_order;
DROP TABLE IF EXISTS src_customer;
DROP TABLE IF EXISTS src_product;
DROP TABLE IF EXISTS src_store;

CREATE TABLE src_customer (
    customer_id INTEGER PRIMARY KEY,
    customer_name TEXT NOT NULL,
    city TEXT NOT NULL,
    country_code TEXT NOT NULL
);

CREATE TABLE src_product (
    product_id INTEGER PRIMARY KEY,
    product_name TEXT NOT NULL,
    category_name TEXT NOT NULL,
    unit_price NUMERIC NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE src_store (
    store_id INTEGER PRIMARY KEY,
    store_name TEXT NOT NULL,
    city TEXT NOT NULL
);

CREATE TABLE src_sales_order (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES src_customer(customer_id),
    store_id INTEGER NOT NULL REFERENCES src_store(store_id),
    order_date TEXT NOT NULL,
    order_status TEXT NOT NULL
);

CREATE TABLE src_sales_order_line (
    order_id INTEGER NOT NULL REFERENCES src_sales_order(order_id),
    line_number INTEGER NOT NULL,
    product_id INTEGER NOT NULL REFERENCES src_product(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, line_number)
);

INSERT INTO src_customer VALUES
    (101, 'Ada Lovelace', 'London', 'GB'),
    (102, 'Alan Turing', 'Manchester', 'GB'),
    (103, 'Grace Hopper', 'New York', 'US');

INSERT INTO src_product VALUES
    (201, 'Keyboard', 'Accessories', 45.00),
    (202, 'Monitor', 'Hardware', 220.00),
    (203, 'Laptop', 'Hardware', 950.00),
    (204, 'USB Cable', 'Accessories', 12.50);

INSERT INTO src_store VALUES
    (301, 'Central London', 'London'),
    (302, 'Northern Hub', 'Manchester');

INSERT INTO src_sales_order VALUES
    (4001, 101, 301, '2026-09-01', 'Completed'),
    (4002, 102, 302, '2026-09-02', 'Completed'),
    (4003, 103, 301, '2026-09-03', 'Cancelled');

INSERT INTO src_sales_order_line VALUES
    (4001, 1, 201, 2, 45.00),
    (4001, 2, 204, 3, 12.50),
    (4002, 1, 203, 1, 950.00),
    (4003, 1, 202, 1, 220.00);

CREATE TABLE stg_sales_extract AS
SELECT o.order_id, l.line_number,
       c.customer_id, c.customer_name, c.city AS customer_city, c.country_code,
       p.product_id, p.product_name, p.category_name,
       s.store_id, s.store_name, s.city AS store_city,
       o.order_date, o.order_status, l.quantity, l.unit_price
FROM src_sales_order o
JOIN src_sales_order_line l ON l.order_id = o.order_id
JOIN src_customer c ON c.customer_id = o.customer_id
JOIN src_product p ON p.product_id = l.product_id
JOIN src_store s ON s.store_id = o.store_id;

CREATE TABLE dw_dim_date (
    date_key INTEGER PRIMARY KEY,
    calendar_date TEXT NOT NULL UNIQUE,
    calendar_year INTEGER NOT NULL,
    calendar_month INTEGER NOT NULL
);

CREATE TABLE dw_dim_customer (
    customer_key INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL UNIQUE,
    customer_name TEXT NOT NULL,
    city TEXT NOT NULL,
    country_code TEXT NOT NULL
);

CREATE TABLE dw_dim_product (
    product_key INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL UNIQUE,
    product_name TEXT NOT NULL,
    category_name TEXT NOT NULL
);

CREATE TABLE dw_dim_store (
    store_key INTEGER PRIMARY KEY AUTOINCREMENT,
    store_id INTEGER NOT NULL UNIQUE,
    store_name TEXT NOT NULL,
    city TEXT NOT NULL
);

CREATE TABLE dw_fact_sales (
    sales_key INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL,
    line_number INTEGER NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dw_dim_date(date_key),
    customer_key INTEGER NOT NULL REFERENCES dw_dim_customer(customer_key),
    product_key INTEGER NOT NULL REFERENCES dw_dim_product(product_key),
    store_key INTEGER NOT NULL REFERENCES dw_dim_store(store_key),
    quantity INTEGER NOT NULL,
    unit_price NUMERIC NOT NULL,
    sales_amount NUMERIC NOT NULL,
    UNIQUE (order_id, line_number)
);

INSERT INTO dw_dim_date
SELECT DISTINCT CAST(REPLACE(order_date, '-', '') AS INTEGER), order_date,
       CAST(substr(order_date, 1, 4) AS INTEGER),
       CAST(substr(order_date, 6, 2) AS INTEGER)
FROM stg_sales_extract;

INSERT INTO dw_dim_customer (customer_id, customer_name, city, country_code)
SELECT DISTINCT customer_id, customer_name, customer_city, country_code
FROM stg_sales_extract;

INSERT INTO dw_dim_product (product_id, product_name, category_name)
SELECT DISTINCT product_id, product_name, category_name
FROM stg_sales_extract;

INSERT INTO dw_dim_store (store_id, store_name, city)
SELECT DISTINCT store_id, store_name, store_city
FROM stg_sales_extract;

INSERT INTO dw_fact_sales
    (order_id, line_number, date_key, customer_key, product_key, store_key,
     quantity, unit_price, sales_amount)
SELECT x.order_id, x.line_number, d.date_key, c.customer_key,
       p.product_key, s.store_key, x.quantity, x.unit_price,
       x.quantity * x.unit_price
FROM stg_sales_extract x
JOIN dw_dim_date d ON d.calendar_date = x.order_date
JOIN dw_dim_customer c ON c.customer_id = x.customer_id
JOIN dw_dim_product p ON p.product_id = x.product_id
JOIN dw_dim_store s ON s.store_id = x.store_id
WHERE x.order_status = 'Completed';

SELECT d.calendar_year, d.calendar_month, p.category_name,
       SUM(f.quantity) AS units_sold,
       SUM(f.sales_amount) AS revenue
FROM dw_fact_sales f
JOIN dw_dim_date d ON d.date_key = f.date_key
JOIN dw_dim_product p ON p.product_key = f.product_key
GROUP BY d.calendar_year, d.calendar_month, p.category_name
ORDER BY d.calendar_year, d.calendar_month, p.category_name;