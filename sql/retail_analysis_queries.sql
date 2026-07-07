-- =========================================================
-- ONLINE RETAIL SALES PERFORMANCE ANALYSIS
-- Data source: online_retail_clean.csv
-- =========================================================

-- ---------------------------------------------------------
-- 0. SETUP DATABASE & TABLE
-- ---------------------------------------------------------

CREATE DATABASE IF NOT EXISTS retail_analysis;

USE retail_analysis;

DROP TABLE IF EXISTS online_retail;

CREATE TABLE online_retail (
    Invoice VARCHAR(20),
    StockCode VARCHAR(20),
    Description VARCHAR(255),
    Quantity INT,
    InvoiceDate DATETIME,
    Price DECIMAL(10, 2),
    CustomerID VARCHAR(20),
    Country VARCHAR(100),
    Revenue DECIMAL(12, 2),
    YearMonth VARCHAR(7),
    DayOfWeek VARCHAR(15)
);

-- ---------------------------------------------------------
-- 1. IMPORT DATA
-- ---------------------------------------------------------

-- Aktifkan fitur LOAD DATA LOCAL INFILE di MySQL
SET GLOBAL local_infile = 1;

-- aktifkan LOAD DATA LOCAL INFILE
LOAD DATA LOCAL INFILE 'online_retail_clean.csv' INTO
TABLE online_retail FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS (
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CustomerID,
    Country,
    Revenue,
    YearMonth,
    DayOfWeek
);

-- Cek hasil import
SELECT COUNT(*) AS total_rows FROM online_retail;

-- Cek 10 baris pertama
SELECT * FROM online_retail LIMIT 10;

-- ---------------------------------------------------------
-- 2. VALIDASI DATA
-- ---------------------------------------------------------

-- Cek range tanggal transaksi
SELECT MIN(InvoiceDate) AS earliest, MAX(InvoiceDate) AS latest
FROM online_retail;

-- Cek apakah masih ada nilai negatif/invalid yang lolos dari cleaning Python
SELECT COUNT(*) AS invalid_rows
FROM online_retail
WHERE
    Quantity <= 0
    OR Price <= 0;

SELECT * FROM online_retail WHERE Quantity <= 0 OR Price <= 0;

DELETE FROM online_retail WHERE Quantity <= 0 OR Price <= 0;

-- ---------------------------------------------------------
-- 3. OVERVIEW BISNIS (KPI Summary)
-- ---------------------------------------------------------

SELECT
    COUNT(DISTINCT Invoice) AS total_orders,
    COUNT(DISTINCT CustomerID) AS total_customers,
    ROUND(SUM(Revenue), 2) AS total_revenue,
    ROUND(
        SUM(Revenue) / COUNT(DISTINCT Invoice),
        2
    ) AS avg_revenue_per_order
FROM online_retail;

-- ---------------------------------------------------------
-- 4. REVENUE PER BULAN (Trend Analysis)
-- ---------------------------------------------------------

SELECT
    YearMonth,
    COUNT(DISTINCT Invoice) AS total_orders,
    ROUND(SUM(Revenue), 2) AS total_revenue
FROM online_retail
GROUP BY
    YearMonth
ORDER BY YearMonth;

-- ---------------------------------------------------------
-- 5. REVENUE PER NEGARA
-- ---------------------------------------------------------

SELECT
    Country,
    COUNT(DISTINCT Invoice) AS total_orders,
    COUNT(DISTINCT CustomerID) AS total_customers,
    ROUND(SUM(Revenue), 2) AS total_revenue,
    ROUND(
        SUM(Revenue) * 100.0 / (
            SELECT SUM(Revenue)
            FROM online_retail
        ),
        1
    ) AS pct_of_total_revenue
FROM online_retail
GROUP BY
    Country
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------
-- 6. TOP 5 PRODUK PER NEGARA (Window Function)
-- ---------------------------------------------------------
-- Untuk menjawab produk apa yang paling laris di tiap negara

WITH
    product_by_country AS (
        SELECT
            Country,
            Description,
            SUM(Quantity) AS total_qty,
            RANK() OVER (
                PARTITION BY
                    Country
                ORDER BY SUM(Quantity) DESC
            ) AS rank_in_country
        FROM online_retail
        GROUP BY
            Country,
            Description
    )
SELECT
    Country,
    Description,
    total_qty,
    rank_in_country
FROM product_by_country
WHERE
    rank_in_country <= 5
ORDER BY Country, rank_in_country;

-- ---------------------------------------------------------
-- 7. TOP 10 PRODUK BERDASARKAN REVENUE (Global)
-- ---------------------------------------------------------

SELECT
    Description,
    SUM(Quantity) AS total_qty_sold,
    ROUND(SUM(Revenue), 2) AS total_revenue
FROM online_retail
GROUP BY
    Description
ORDER BY total_revenue DESC
LIMIT 10;

-- ---------------------------------------------------------
-- 8. RFM SEGMENTATION
-- ---------------------------------------------------------
-- Menghitung ulang RFM scores untuk tiap customer di SQL
-- menggunakan CTE + window function.

WITH
    customer_rfm AS (
        SELECT
            CustomerID,
            DATEDIFF(
                (
                    SELECT MAX(InvoiceDate)
                    FROM online_retail
                ) + INTERVAL 1 DAY,
                MAX(InvoiceDate)
            ) AS recency,
            COUNT(DISTINCT Invoice) AS frequency,
            ROUND(SUM(Revenue), 2) AS monetary
        FROM online_retail
        GROUP BY
            CustomerID
    ),
    rfm_scored AS (
        SELECT
            CustomerID,
            recency,
            frequency,
            monetary,
            NTILE(4) OVER (
                ORDER BY recency DESC
            ) AS r_score,
            NTILE(4) OVER (
                ORDER BY frequency ASC
            ) AS f_score,
            NTILE(4) OVER (
                ORDER BY monetary ASC
            ) AS m_score
        FROM customer_rfm
    )
SELECT
    *,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Champion'
        WHEN (r_score + f_score + m_score) >= 7 THEN 'Loyal Customer'
        WHEN (r_score + f_score + m_score) >= 4 THEN 'At Risk'
        ELSE 'Lost Customer'
    END AS segment
FROM rfm_scored
ORDER BY monetary DESC;

-- ---------------------------------------------------------
-- 9. KONTRIBUSI REVENUE PER SEGMENT CUSTOMER
-- ---------------------------------------------------------
-- Membuktikan prinsip Pareto: berapa % revenue yang disumbang tiap segmen?

WITH
    customer_rfm AS (
        SELECT
            CustomerID,
            DATEDIFF(
                (
                    SELECT MAX(InvoiceDate)
                    FROM online_retail
                ) + INTERVAL 1 DAY,
                MAX(InvoiceDate)
            ) AS recency,
            COUNT(DISTINCT Invoice) AS frequency,
            SUM(Revenue) AS monetary
        FROM online_retail
        GROUP BY
            CustomerID
    ),
    rfm_scored AS (
        SELECT
            CustomerID,
            monetary,
            NTILE(4) OVER (
                ORDER BY recency DESC
            ) AS r_score,
            NTILE(4) OVER (
                ORDER BY frequency ASC
            ) AS f_score,
            NTILE(4) OVER (
                ORDER BY monetary ASC
            ) AS m_score
        FROM customer_rfm
    ),
    segmented AS (
        SELECT
            CustomerID,
            monetary,
            CASE
                WHEN (r_score + f_score + m_score) >= 10 THEN 'Champion'
                WHEN (r_score + f_score + m_score) >= 7 THEN 'Loyal Customer'
                WHEN (r_score + f_score + m_score) >= 4 THEN 'At Risk'
                ELSE 'Lost Customer'
            END AS segment
        FROM rfm_scored
    )
SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(
        SUM(monetary) * 100.0 / (
            SELECT SUM(monetary)
            FROM segmented
        ),
        1
    ) AS pct_revenue
FROM segmented
GROUP BY
    segment
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------
-- 10. POLA TRANSAKSI PER HARI DALAM SEMINGGU
-- ---------------------------------------------------------

SELECT
    DayOfWeek,
    COUNT(DISTINCT Invoice) AS total_orders,
    ROUND(SUM(Revenue), 2) AS total_revenue
FROM online_retail
GROUP BY
    DayOfWeek
ORDER BY FIELD(
        DayOfWeek, 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    );

-- ---------------------------------------------------------
-- 11. CUSTOMER DENGAN REVENUE TERTINGGI (Top Spender)
-- ---------------------------------------------------------

SELECT
    CustomerID,
    Country,
    COUNT(DISTINCT Invoice) AS total_orders,
    ROUND(SUM(Revenue), 2) AS total_revenue
FROM online_retail
GROUP BY
    CustomerID,
    Country
ORDER BY total_revenue DESC
LIMIT 10;

-- ---------------------------------------------------------
-- 12. MONTH-OVER-MONTH GROWTH RATE
-- ---------------------------------------------------------
-- Melakukan analisis pertumbuhan revenue per bulan (MoM Growth Rate).

WITH
    monthly AS (
        SELECT YearMonth, SUM(Revenue) AS revenue
        FROM online_retail
        GROUP BY
            YearMonth
    )
SELECT
    YearMonth,
    revenue,
    LAG(revenue) OVER (
        ORDER BY YearMonth
    ) AS prev_month_revenue,
    ROUND(
        (
            revenue - LAG(revenue) OVER (
                ORDER BY YearMonth
            )
        ) * 100.0 / LAG(revenue) OVER (
            ORDER BY YearMonth
        ),
        1
    ) AS mom_growth_pct
FROM monthly
ORDER BY YearMonth;