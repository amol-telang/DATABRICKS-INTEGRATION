-- =====================================================================
-- BRONZE LAYER: raw ingestion (no business logic)
-- Source : /Volumes/databricks_project/bronze/raw_landing/<entity>/
-- Target : databricks_project.bronze.bronze_*
-- Notes  : All columns kept as STRING (inferColumnTypes = false) so that
--          bad values are never lost at ingestion. Typing happens in silver.
--          Lineage columns _source_file and _ingested_at are added.
-- =====================================================================

CREATE OR REFRESH STREAMING TABLE databricks_project.bronze.bronze_customers
COMMENT 'Raw customer records as received from the source system (all STRING).'
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '/Volumes/databricks_project/bronze/raw_landing/customers/',
  format => 'csv', header => true, inferColumnTypes => false, pathGlobFilter => '*.csv');

CREATE OR REFRESH STREAMING TABLE databricks_project.bronze.bronze_products
COMMENT 'Raw product catalogue as received from the source system (all STRING).'
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '/Volumes/databricks_project/bronze/raw_landing/products/',
  format => 'csv', header => true, inferColumnTypes => false, pathGlobFilter => '*.csv');

CREATE OR REFRESH STREAMING TABLE databricks_project.bronze.bronze_orders
COMMENT 'Raw order headers as received from the source system (all STRING).'
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '/Volumes/databricks_project/bronze/raw_landing/orders/',
  format => 'csv', header => true, inferColumnTypes => false, pathGlobFilter => '*.csv');

CREATE OR REFRESH STREAMING TABLE databricks_project.bronze.bronze_order_items
COMMENT 'Raw order line items as received from the source system (all STRING).'
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '/Volumes/databricks_project/bronze/raw_landing/order_items/',
  format => 'csv', header => true, inferColumnTypes => false, pathGlobFilter => '*.csv');