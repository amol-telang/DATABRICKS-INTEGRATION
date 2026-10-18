-- =====================================================================
-- SILVER LAYER: cleaned, typed, de-duplicated, validated
-- Source : databricks_project.bronze.bronze_*
-- Target : databricks_project.silver.silver_*
-- Data quality is enforced with expectations:
--   EXPECT (...)                          -> WARN : keep row, record metric
--   EXPECT (...) ON VIOLATION DROP ROW    -> DROP : remove row, record metric
-- Violation counts appear in the pipeline event log / UI.
-- =====================================================================

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.silver.silver_customers (
  CONSTRAINT customer_id_present  EXPECT (customer_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT region_is_valid      EXPECT (region IN ('North','South','East','West')) ON VIOLATION DROP ROW,
  CONSTRAINT signup_date_valid    EXPECT (signup_date IS NOT NULL AND signup_date <= current_date()) ON VIOLATION DROP ROW,
  CONSTRAINT email_present_valid  EXPECT (email IS NOT NULL)   -- WARN only: invalid or missing emails are nulled, not dropped
)
COMMENT 'Cleaned customers: latest version per customer_id, standardised region, validated email.'
AS
SELECT
  customer_id,
  initcap(trim(first_name)) AS first_name,
  initcap(trim(last_name))  AS last_name,
  CASE WHEN email RLIKE '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$' THEN lower(trim(email)) END AS email,
  phone,
  initcap(trim(region)) AS region,
  city,
  segment,
  CAST(signup_date AS DATE) AS signup_date,
  CAST(updated_at AS DATE)  AS updated_at
FROM (
  SELECT *, row_number() OVER (PARTITION BY customer_id ORDER BY updated_at DESC, _ingested_at DESC) AS rn
  FROM databricks_project.bronze.bronze_customers
)
WHERE rn = 1;

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.silver.silver_products (
  CONSTRAINT product_id_present EXPECT (product_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT unit_price_positive EXPECT (unit_price > 0) ON VIOLATION DROP ROW,
  CONSTRAINT unit_cost_present  EXPECT (unit_cost IS NOT NULL),                 -- WARN
  CONSTRAINT cost_below_price   EXPECT (unit_cost IS NULL OR unit_cost < unit_price)  -- WARN
)
COMMENT 'Cleaned product catalogue with typed price and cost.'
AS
SELECT
  product_id,
  trim(product_name) AS product_name,
  trim(category)     AS category,
  CAST(unit_price AS DECIMAL(12,2)) AS unit_price,
  CAST(unit_cost  AS DECIMAL(12,2)) AS unit_cost
FROM (
  SELECT *, row_number() OVER (PARTITION BY product_id ORDER BY _ingested_at DESC) AS rn
  FROM databricks_project.bronze.bronze_products
)
WHERE rn = 1;

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.silver.silver_orders (
  CONSTRAINT order_id_present   EXPECT (order_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT order_date_valid   EXPECT (order_date IS NOT NULL AND order_date <= current_date()) ON VIOLATION DROP ROW,
  CONSTRAINT customer_exists    EXPECT (customer_fk_ok) ON VIOLATION DROP ROW,
  CONSTRAINT status_is_valid    EXPECT (order_status IN ('Completed','Cancelled','Returned')) ON VIOLATION DROP ROW
)
COMMENT 'Cleaned orders: de-duplicated, typed dates, standardised status, valid customer reference.'
AS
SELECT
  o.order_id,
  o.customer_id,
  CAST(o.order_date AS DATE) AS order_date,
  o.channel,
  o.payment_method,
  initcap(trim(o.order_status)) AS order_status,
  (c.customer_id IS NOT NULL)   AS customer_fk_ok
FROM (
  SELECT *, row_number() OVER (PARTITION BY order_id ORDER BY _ingested_at DESC) AS rn
  FROM databricks_project.bronze.bronze_orders
) o
LEFT JOIN databricks_project.silver.silver_customers c ON o.customer_id = c.customer_id
WHERE o.rn = 1;

CREATE OR REFRESH MATERIALIZED VIEW databricks_project.silver.silver_order_items (
  CONSTRAINT order_item_id_present EXPECT (order_item_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT quantity_positive     EXPECT (quantity > 0) ON VIOLATION DROP ROW,
  CONSTRAINT discount_in_range     EXPECT (discount_pct BETWEEN 0 AND 100) ON VIOLATION DROP ROW,
  CONSTRAINT unit_price_positive   EXPECT (unit_price > 0) ON VIOLATION DROP ROW,
  CONSTRAINT product_exists        EXPECT (product_fk_ok) ON VIOLATION DROP ROW,
  CONSTRAINT order_exists          EXPECT (order_fk_ok) ON VIOLATION DROP ROW
)
COMMENT 'Cleaned order lines with valid product and order references.'
AS
SELECT
  i.order_item_id,
  i.order_id,
  i.product_id,
  CAST(i.quantity AS INT)              AS quantity,
  CAST(i.unit_price AS DECIMAL(12,2))  AS unit_price,
  CAST(i.discount_pct AS DECIMAL(5,2)) AS discount_pct,
  (p.product_id IS NOT NULL) AS product_fk_ok,
  (o.order_id   IS NOT NULL) AS order_fk_ok
FROM (
  SELECT *, row_number() OVER (PARTITION BY order_item_id ORDER BY _ingested_at DESC) AS rn
  FROM databricks_project.bronze.bronze_order_items
) i
LEFT JOIN databricks_project.silver.silver_products p ON i.product_id = p.product_id
LEFT JOIN databricks_project.silver.silver_orders   o ON i.order_id   = o.order_id
WHERE i.rn = 1;