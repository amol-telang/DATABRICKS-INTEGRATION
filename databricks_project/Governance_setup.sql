-- =====================================================================
-- GOVERNANCE SETUP (databricks_project.governance)
-- Role-based access, PII masking and region row filter.
-- Already executed in the workspace; kept here for the GitHub repo.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS databricks_project.governance
  COMMENT 'Access policy table plus masking and row-filter functions';

-- 1) Role / region policy table
CREATE TABLE IF NOT EXISTS databricks_project.governance.access_policy (
  principal STRING COMMENT 'User email (current_user()) this rule applies to',
  role      STRING COMMENT 'admin = all rows + unmasked PII | finance = all rows + masked PII | regional_manager = own region + masked PII',
  region    STRING COMMENT 'Region the principal may see, or * for all regions'
);

-- Seed the first admin (replace with your own login email). Safe to re-run: it only inserts if missing.
MERGE INTO databricks_project.governance.access_policy t
USING (SELECT 'your.email@example.com' AS principal, 'admin' AS role, '*' AS region) s
ON t.principal = s.principal
WHEN NOT MATCHED THEN INSERT *;
-- Examples to add real users:
-- ('finance.user@company.com',   'finance',          '*'),
-- ('west.manager@company.com',   'regional_manager', 'West'),
-- ('north.manager@company.com',  'regional_manager', 'North');

-- 2) Column masks
CREATE OR REPLACE FUNCTION databricks_project.governance.mask_email(email STRING)
RETURNS STRING
COMMENT 'Admins see the full email; everyone else sees first letter + *** + domain'
RETURN CASE
  WHEN EXISTS (SELECT 1 FROM databricks_project.governance.access_policy p WHERE p.principal = current_user() AND p.role = 'admin') THEN email
  WHEN email IS NULL THEN NULL
  ELSE concat(left(email, 1), '***@', split_part(email, '@', 2))
END;

CREATE OR REPLACE FUNCTION databricks_project.governance.mask_phone(phone STRING)
RETURNS STRING
COMMENT 'Admins see the full phone number; everyone else sees only the last 3 digits'
RETURN CASE
  WHEN EXISTS (SELECT 1 FROM databricks_project.governance.access_policy p WHERE p.principal = current_user() AND p.role = 'admin') THEN phone
  WHEN phone IS NULL THEN NULL
  ELSE concat('+91-XXXXX-XX', right(phone, 3))
END;

-- 3) Row filter by region
CREATE OR REPLACE FUNCTION databricks_project.governance.region_filter(region_value STRING)
RETURNS BOOLEAN
COMMENT 'Row filter: a user sees a row only if access_policy gives them that region or * (all regions)'
RETURN EXISTS (
  SELECT 1 FROM databricks_project.governance.access_policy p
  WHERE p.principal = current_user() AND (p.region = '*' OR p.region = region_value)
);

-- 4) Attach to gold tables: done inside gold_star_schema.sql
--    (MASK on gold_dim_customer.email / phone, WITH ROW FILTER on region
--     for gold_dim_customer, gold_fact_sales, gold_fact_customer_snapshot).

-- 5) Role-based GRANTS (run in a workspace that has account groups; not executed here)
-- GRANT USE CATALOG ON CATALOG databricks_project TO `analytics_readers`;
-- GRANT USE SCHEMA, SELECT ON SCHEMA databricks_project.gold TO `analytics_readers`;
-- GRANT USE SCHEMA, SELECT ON SCHEMA databricks_project.silver TO `data_engineers`;
-- GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA databricks_project.bronze TO `data_engineers`;
-- REVOKE ALL PRIVILEGES ON SCHEMA databricks_project.bronze FROM `analytics_readers`;

-- 6) Test (change your own row temporarily, then restore it):
-- UPDATE databricks_project.governance.access_policy
--   SET role = 'regional_manager', region = 'West' WHERE principal = current_user();
-- SELECT * FROM databricks_project.gold.gold_dim_customer LIMIT 10;