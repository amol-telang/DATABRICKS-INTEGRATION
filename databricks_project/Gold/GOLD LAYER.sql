-- =====================================================================
-- GOLD LAYER: star schema for reporting (Power BI, dashboards, Genie)
-- Source : databricks_project.silver.silver_*
-- Target : databricks_project.gold.gold_*
-- Governance: email/phone masked and rows filtered by region
--             (functions live in databricks_project.governance)
--   Dimensions : gold_dim_date, gold_dim_customer, gold_dim_product
--   Facts      : gold_fact_sales (order-line grain),
--                gold_fact_customer_snapshot (one row per customer)
-- Churn definition: no completed purchase in the last 90 days,
-- measured as of the latest order date in the data.
-- =====================================================================

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.gold.gold_dim_date (
  CONSTRAINT date_key_present EXPECT (date_key IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Calendar dimension, 2023-01-01 to 2026-12-31.'
AS
SELECT
  CAST(date_format(d, 'yyyyMMdd') AS INT) AS date_key,
  d AS full_date,
  year(d) AS year,
  quarter(d) AS quarter,
  month(d) AS month_number,
  date_format(d, 'MMMM') AS month_name,
  date_format(d, 'yyyy-MM') AS year_month,
  weekofyear(d) AS week_of_year,
  date_format(d, 'EEEE') AS day_name,
  dayofweek(d) IN (1, 7) AS is_weekend
FROM (SELECT explode(sequence(DATE'2023-01-01', DATE'2026-12-31', INTERVAL 1 DAY)) AS d);

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.gold.gold_dim_customer (
  customer_key STRING,
  first_name   STRING,
  last_name    STRING,
  email        STRING MASK databricks_project.governance.mask_email,
  phone        STRING MASK databricks_project.governance.mask_phone,
  region       STRING,
  city         STRING,
  segment      STRING,
  signup_date  DATE,
  CONSTRAINT customer_key_present EXPECT (customer_key IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Customer dimension. email and phone are masked for non-admins; rows are filtered by region (see governance schema).'
WITH ROW FILTER databricks_project.governance.region_filter ON (region)
AS
SELECT
  customer_id AS customer_key,
  first_name, last_name, email, phone,
  region, city, segment, signup_date
FROM databricks_project.silver.silver_customers;

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.gold.gold_dim_product (
  CONSTRAINT product_key_present EXPECT (product_key IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Product dimension with list price, unit cost and margin %.'
AS
SELECT
  product_id AS product_key,
  product_name, category, unit_price, unit_cost,
  round((unit_price - unit_cost) / unit_price * 100, 2) AS margin_pct
FROM databricks_project.silver.silver_products;

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.gold.gold_fact_sales (
  CONSTRAINT net_revenue_non_negative EXPECT (net_revenue >= 0) ON VIOLATION DROP ROW,
  CONSTRAINT date_key_present         EXPECT (date_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT cost_present             EXPECT (cost_amount IS NOT NULL)   -- WARN: products with missing cost
)
COMMENT 'Sales fact at order-line grain. net_revenue = qty * price * (1 - discount). Rows filtered by region.'
WITH ROW FILTER databricks_project.governance.region_filter ON (region)
AS
SELECT
  i.order_item_id,
  i.order_id,
  CAST(date_format(o.order_date, 'yyyyMMdd') AS INT) AS date_key,
  o.order_date,
  o.customer_id AS customer_key,
  c.region      AS region,
  i.product_id  AS product_key,
  o.channel,
  o.payment_method,
  o.order_status,
  i.quantity,
  i.unit_price,
  i.discount_pct,
  i.quantity * i.unit_price                                        AS gross_amount,
  i.quantity * i.unit_price * (i.discount_pct / 100)               AS discount_amount,
  i.quantity * i.unit_price * (1 - i.discount_pct / 100)           AS net_revenue,
  i.quantity * p.unit_cost                                         AS cost_amount,
  i.quantity * i.unit_price * (1 - i.discount_pct / 100) - i.quantity * p.unit_cost AS gross_margin
FROM databricks_project.silver.silver_order_items i
JOIN databricks_project.silver.silver_orders  o ON i.order_id   = o.order_id
JOIN databricks_project.silver.silver_products p ON i.product_id = p.product_id
JOIN databricks_project.silver.silver_customers c ON o.customer_id = c.customer_id;

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.gold.gold_fact_customer_snapshot (
  CONSTRAINT customer_key_present EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'One row per customer: lifetime value, recency and churn flag (no completed purchase in 90 days). Rows filtered by region.'
WITH ROW FILTER databricks_project.governance.region_filter ON (region)
AS
WITH ref AS (SELECT max(order_date) AS as_of_date FROM databricks_project.silver.silver_orders),
agg AS (
  SELECT
    customer_id AS customer_key,
    count(DISTINCT order_id) AS lifetime_orders,
    min(order_date) AS first_order_date,
    max(order_date) AS last_order_date
  FROM databricks_project.silver.silver_orders
  WHERE order_status = 'Completed'
  GROUP BY customer_id
),
rev AS (
  SELECT customer_key, sum(net_revenue) AS lifetime_revenue, sum(gross_margin) AS lifetime_margin
  FROM databricks_project.gold.gold_fact_sales
  WHERE order_status = 'Completed'
  GROUP BY customer_key
)
SELECT
  c.customer_id AS customer_key,
  c.region AS region,
  ref.as_of_date,
  coalesce(a.lifetime_orders, 0)  AS lifetime_orders,
  coalesce(r.lifetime_revenue, 0) AS lifetime_revenue,
  coalesce(r.lifetime_margin, 0)  AS lifetime_margin,
  a.first_order_date,
  a.last_order_date,
  datediff(ref.as_of_date, a.last_order_date) AS days_since_last_order,
  coalesce(datediff(ref.as_of_date, a.last_order_date) > 90, TRUE) AS is_churned
FROM databricks_project.silver.silver_customers c
CROSS JOIN ref
LEFT JOIN agg a ON c.customer_id = a.customer_key
LEFT JOIN rev r ON c.customer_id = r.customer_key;