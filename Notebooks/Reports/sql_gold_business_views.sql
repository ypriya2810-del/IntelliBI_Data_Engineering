-- =====================================================================
--  IntelliBI Sales Lakehouse — GOLD Business Views & KPI Aggregates
-- =====================================================================
--  These views sit on top of the star schema (fact_sales, fact_invoice
--  + dim_*) and form the semantic / reporting layer consumed by
--  Databricks SQL dashboards, Power BI, Tableau, etc.
--
--  Naming convention:   vw_<subject_area>_<grain>
--
--  Run once per environment after the fact tables are loaded.
--  Replace `dev` with `qa` / `prd` as required.
-- =====================================================================

USE CATALOG saleslake_dev;
USE SCHEMA gold_dev;

-- =====================================================================
--  1.  EXECUTIVE SUMMARY  —  current period KPIs
-- =====================================================================
CREATE OR REPLACE VIEW vw_exec_kpi_summary AS
SELECT
    COUNT(DISTINCT f.sale_id)                          AS total_orders,
    SUM(f.quantity)                                    AS total_units_sold,
    ROUND(SUM(f.gross_amount),     2)                  AS gross_revenue,
    ROUND(SUM(f.discount_amount),  2)                  AS total_discount,
    ROUND(SUM(f.net_amount),       2)                  AS net_revenue,
    ROUND(SUM(f.cost_amount),      2)                  AS total_cogs,
    ROUND(SUM(f.profit_amount),    2)                  AS total_profit,
    ROUND(SUM(f.profit_amount) / NULLIF(SUM(f.net_amount),0) * 100, 2)
                                                       AS overall_margin_pct,
    ROUND(SUM(f.net_amount) / NULLIF(COUNT(DISTINCT f.sale_id),0), 2)
                                                       AS avg_order_value,
    COUNT(DISTINCT f.customer_sk)                      AS unique_customers
FROM fact_sales f;


-- =====================================================================
--  2.  SALES TRENDS  —  daily / monthly / yearly
-- =====================================================================
CREATE OR REPLACE VIEW vw_sales_daily AS
SELECT
    d.full_date,
    d.day_name,
    SUM(f.quantity)        AS units,
    SUM(f.net_amount)      AS net_revenue,
    SUM(f.profit_amount)   AS profit,
    COUNT(DISTINCT f.sale_id) AS orders,
    COUNT(DISTINCT f.customer_sk) AS unique_customers
FROM fact_sales f
JOIN dim_date d ON f.date_sk = d.date_sk
GROUP BY d.full_date, d.day_name;

CREATE OR REPLACE VIEW vw_sales_monthly AS
SELECT
    d.year, d.month, d.month_name,
    CONCAT(d.year, '-', LPAD(d.month, 2, '0')) AS year_month,
    SUM(f.quantity)        AS units,
    ROUND(SUM(f.net_amount), 2)   AS net_revenue,
    ROUND(SUM(f.discount_amount), 2) AS discount_given,
    ROUND(SUM(f.profit_amount), 2)   AS profit,
    ROUND(SUM(f.profit_amount) / NULLIF(SUM(f.net_amount),0) * 100, 2) AS margin_pct,
    COUNT(DISTINCT f.sale_id) AS orders,
    COUNT(DISTINCT f.customer_sk) AS unique_customers
FROM fact_sales f
JOIN dim_date d ON f.date_sk = d.date_sk
GROUP BY d.year, d.month, d.month_name;

CREATE OR REPLACE VIEW vw_sales_yoy AS
SELECT
    cur.year, cur.month, cur.month_name,
    cur.net_revenue                  AS net_revenue_current,
    prev.net_revenue                 AS net_revenue_prior_year,
    ROUND((cur.net_revenue - prev.net_revenue) / NULLIF(prev.net_revenue, 0) * 100, 2)
                                     AS yoy_growth_pct
FROM vw_sales_monthly cur
LEFT JOIN vw_sales_monthly prev
       ON cur.month = prev.month AND cur.year = prev.year + 1;


-- =====================================================================
--  3.  PRODUCT PERFORMANCE
-- =====================================================================
CREATE OR REPLACE VIEW vw_product_performance AS
SELECT
    p.product_id, p.sku, p.product_name, p.category, p.sub_category,
    p.brand,
    SUM(f.quantity)                AS units_sold,
    ROUND(SUM(f.net_amount), 2)    AS net_revenue,
    ROUND(SUM(f.profit_amount), 2) AS profit,
    ROUND(SUM(f.profit_amount) / NULLIF(SUM(f.net_amount), 0) * 100, 2) AS margin_pct,
    COUNT(DISTINCT f.sale_id)      AS orders,
    COUNT(DISTINCT f.customer_sk)  AS unique_customers,
    ROUND(SUM(f.net_amount) / NULLIF(COUNT(DISTINCT f.sale_id), 0), 2) AS avg_order_value
FROM fact_sales f
JOIN dim_product p
  ON f.product_sk = p.product_sk
WHERE p.is_active = 'Y'
GROUP BY p.product_id, p.sku, p.product_name, p.category, p.sub_category, p.brand;

CREATE OR REPLACE VIEW vw_top10_products AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY net_revenue DESC) AS rnk
    FROM vw_product_performance
) WHERE rnk <= 10;

CREATE OR REPLACE VIEW vw_category_performance AS
SELECT
    p.category,
    SUM(f.quantity)                AS units_sold,
    ROUND(SUM(f.net_amount), 2)    AS net_revenue,
    ROUND(SUM(f.profit_amount), 2) AS profit,
    ROUND(SUM(f.profit_amount) / NULLIF(SUM(f.net_amount), 0) * 100, 2) AS margin_pct,
    COUNT(DISTINCT p.product_id)   AS distinct_products
FROM fact_sales f
JOIN dim_product p
  ON f.product_sk = p.product_sk
WHERE p.is_active = 'Y'
GROUP BY p.category;


-- =====================================================================
--  4.  STORE PERFORMANCE
-- =====================================================================
CREATE OR REPLACE VIEW vw_store_performance AS
SELECT
    s.store_id, s.store_code, s.store_name, s.store_type,
    s.city, s.state, s.region_id,
    SUM(f.quantity)                AS units_sold,
    ROUND(SUM(f.net_amount), 2)    AS net_revenue,
    ROUND(SUM(f.profit_amount), 2) AS profit,
    COUNT(DISTINCT f.sale_id)      AS orders,
    COUNT(DISTINCT f.customer_sk)  AS unique_customers,
    ROUND(SUM(f.net_amount) / NULLIF(s.square_feet, 0), 2) AS revenue_per_sqft
FROM fact_sales f
JOIN dim_store s
  ON f.store_sk = s.store_sk
WHERE s.is_active = 'Y'
GROUP BY s.store_id, s.store_code, s.store_name, s.store_type,
         s.city, s.state, s.region_id, s.square_feet;


-- =====================================================================
--  5.  REGIONAL PERFORMANCE
-- =====================================================================
CREATE OR REPLACE VIEW vw_regional_performance AS
SELECT
    r.region_id, r.region_code, r.region_name, r.country,
    SUM(f.quantity)                AS units_sold,
    ROUND(SUM(f.net_amount), 2)    AS net_revenue,
    ROUND(SUM(f.profit_amount), 2) AS profit,
    ROUND(SUM(f.profit_amount) / NULLIF(SUM(f.net_amount), 0) * 100, 2) AS margin_pct,
    COUNT(DISTINCT f.sale_id)      AS orders,
    COUNT(DISTINCT f.customer_sk)  AS unique_customers,
    COUNT(DISTINCT f.store_sk)     AS active_stores
FROM fact_sales f
JOIN dim_region r ON f.region_sk = r.region_sk
GROUP BY r.region_id, r.region_code, r.region_name, r.country;


-- =====================================================================
--  6.  CUSTOMER 360 / SEGMENT ANALYTICS
-- =====================================================================
CREATE OR REPLACE VIEW vw_customer_360 AS
SELECT
    c.customer_id, c.customer_name, c.email, c.segment,
    c.city, c.state, c.country,
    COUNT(DISTINCT f.sale_id)      AS lifetime_orders,
    SUM(f.quantity)                AS lifetime_units,
    ROUND(SUM(f.net_amount), 2)    AS lifetime_value,
    ROUND(SUM(f.profit_amount), 2) AS lifetime_profit,
    ROUND(AVG(f.net_amount), 2)    AS avg_order_value,
    MIN(f.sale_date)               AS first_purchase_date,
    MAX(f.sale_date)               AS last_purchase_date,
    DATEDIFF(CURRENT_DATE(), MAX(f.sale_date)) AS days_since_last_purchase
FROM fact_sales f
JOIN refinedCustomer c
  ON f.customer_sk = c.customer_sk
WHERE c.is_active = 'Y'
GROUP BY c.customer_id, c.customer_name, c.email, c.segment,
         c.city, c.state, c.country;

CREATE OR REPLACE VIEW vw_customer_segment_perf AS
SELECT
    c.segment,
    COUNT(DISTINCT c.customer_id)  AS customers,
    COUNT(DISTINCT f.sale_id)      AS orders,
    ROUND(SUM(f.net_amount), 2)    AS net_revenue,
    ROUND(SUM(f.profit_amount), 2) AS profit,
    ROUND(SUM(f.net_amount) / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2) AS revenue_per_customer
FROM fact_sales f
JOIN refinedCustomer c
  ON f.customer_sk = c.customer_sk
WHERE c.is_active = 'Y'
GROUP BY c.segment;

CREATE OR REPLACE VIEW vw_customer_rfm AS
WITH base AS (
    SELECT customer_id, customer_name, segment,
           days_since_last_purchase AS recency_days,
           lifetime_orders AS frequency,
           lifetime_value AS monetary
    FROM vw_customer_360
)
SELECT b.*,
    NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
    NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
    NTILE(5) OVER (ORDER BY monetary  DESC)    AS m_score
FROM base b;


-- =====================================================================
--  7.  DISCOUNT EFFECTIVENESS
-- =====================================================================
CREATE OR REPLACE VIEW vw_discount_effectiveness AS
SELECT
    d.discount_code, d.discount_name, d.discount_type, d.discount_value,
    d.applicable_segment, d.applicable_category,
    COUNT(DISTINCT f.sale_id)       AS orders_with_discount,
    SUM(f.quantity)                 AS units_sold,
    ROUND(SUM(f.gross_amount), 2)   AS gross_revenue,
    ROUND(SUM(f.discount_amount), 2) AS total_discount_given,
    ROUND(SUM(f.net_amount), 2)     AS net_revenue,
    ROUND(SUM(f.profit_amount), 2)  AS profit,
    ROUND(SUM(f.profit_amount) / NULLIF(SUM(f.net_amount), 0) * 100, 2) AS margin_pct,
    ROUND(SUM(f.discount_amount) / NULLIF(SUM(f.gross_amount), 0) * 100, 2)
                                    AS discount_pct_of_gross
FROM fact_sales f
JOIN dim_discount d
  ON f.discount_sk = d.discount_sk
WHERE d.is_active = 'Y'
GROUP BY d.discount_code, d.discount_name, d.discount_type, d.discount_value,
         d.applicable_segment, d.applicable_category;

CREATE OR REPLACE VIEW vw_discount_vs_nondiscount AS
SELECT
    CASE WHEN discount_sk IS NULL THEN 'NO_DISCOUNT' ELSE 'WITH_DISCOUNT' END AS group_type,
    COUNT(DISTINCT sale_id)        AS orders,
    SUM(quantity)                  AS units,
    ROUND(SUM(net_amount),     2)  AS net_revenue,
    ROUND(SUM(profit_amount),  2)  AS profit,
    ROUND(AVG(net_amount),     2)  AS avg_order_value,
    ROUND(SUM(profit_amount) / NULLIF(SUM(net_amount), 0) * 100, 2) AS margin_pct
FROM fact_sales
GROUP BY CASE WHEN discount_sk IS NULL THEN 'NO_DISCOUNT' ELSE 'WITH_DISCOUNT' END;


-- =====================================================================
--  8.  PAYMENT & CHANNEL ANALYTICS
-- =====================================================================
CREATE OR REPLACE VIEW vw_payment_method_perf AS
SELECT
    payment_method,
    COUNT(DISTINCT sale_id)        AS orders,
    ROUND(SUM(net_amount), 2)      AS net_revenue,
    ROUND(AVG(net_amount), 2)      AS avg_order_value
FROM fact_sales
GROUP BY payment_method;

CREATE OR REPLACE VIEW vw_channel_perf AS
SELECT
    channel,
    COUNT(DISTINCT sale_id)        AS orders,
    SUM(quantity)                  AS units,
    ROUND(SUM(net_amount), 2)      AS net_revenue,
    ROUND(SUM(profit_amount), 2)   AS profit,
    ROUND(SUM(profit_amount) / NULLIF(SUM(net_amount), 0) * 100, 2) AS margin_pct
FROM fact_sales
GROUP BY channel;


-- =====================================================================
--  9.  INVOICE / AR / COLLECTIONS DASHBOARDS
-- =====================================================================
CREATE OR REPLACE VIEW vw_invoice_status_summary AS
SELECT
    payment_status,
    COUNT(*)                         AS invoice_count,
    ROUND(SUM(total_amount), 2)      AS total_billed,
    ROUND(AVG(total_amount), 2)      AS avg_invoice_amount,
    ROUND(AVG(days_to_pay),  2)      AS avg_days_to_pay
FROM fact_invoice
GROUP BY payment_status;

CREATE OR REPLACE VIEW vw_invoice_overdue AS
SELECT
    fi.invoice_id, fi.invoice_number, fi.total_amount,
    fi.invoice_date, fi.due_date,
    DATEDIFF(CURRENT_DATE(), fi.due_date) AS days_overdue,
    c.customer_id, c.customer_name, c.email, c.segment
FROM fact_invoice fi
JOIN refinedCustomer c ON fi.customer_sk = c.customer_sk
WHERE fi.payment_status IN ('OVERDUE', 'PENDING')
  AND CURRENT_DATE() > fi.due_date;


-- =====================================================================
--  10.  COHORT / RETENTION
-- =====================================================================
CREATE OR REPLACE VIEW vw_monthly_new_vs_returning AS
WITH first_order AS (
    SELECT customer_sk, MIN(sale_date) AS first_dt
    FROM fact_sales GROUP BY customer_sk
)
SELECT
    YEAR(f.sale_date)  AS year,
    MONTH(f.sale_date) AS month,
    SUM(CASE WHEN YEAR(fo.first_dt) = YEAR(f.sale_date)
              AND MONTH(fo.first_dt) = MONTH(f.sale_date) THEN 1 ELSE 0 END) AS new_customers,
    SUM(CASE WHEN YEAR(fo.first_dt) <> YEAR(f.sale_date)
              OR  MONTH(fo.first_dt) <> MONTH(f.sale_date) THEN 1 ELSE 0 END) AS returning_orders,
    ROUND(SUM(f.net_amount), 2) AS revenue
FROM fact_sales f
JOIN first_order fo ON f.customer_sk = fo.customer_sk
GROUP BY YEAR(f.sale_date), MONTH(f.sale_date);


-- =====================================================================
--  END  —  All business views created.
-- =====================================================================


--SHOW VIEWS IN saleslake_dev.gold_dev;