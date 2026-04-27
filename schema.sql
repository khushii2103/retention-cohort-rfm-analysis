/* ============================================================================
 *  PROJECT      : Olist Brazilian E-Commerce — Customer Retention,
 *                 Cohort & RFM Analysis 
 *  FILE         : schema.sql
 *  PURPOSE      : Create the `olist_retention` database, define the four
 *                 tables required for retention analysis, load the raw CSV
 *                 files, clean bad dates, deduplicate the reviews table,
 *                 enforce PRIMARY KEY / FOREIGN KEY constraints, and add
 *                 performance indexes for cohort / RFM / churn queries.
 *  DATABASE     : MySQL 8.x
 *  AUTHOR       : Khushi
 *  DATA SOURCE  : Brazilian E-Commerce Public Dataset by Olist (Kaggle)
 *  TABLES USED  : customers, orders, order_items, reviews
 *  HOW TO RUN   : Execute top-to-bottom in MySQL Workbench (single click on
 *                 the lightning-bolt). Ensure `local_infile` is enabled on
 *                 both the server and the client.
 *  RE-RUN SAFE  : The script begins with `DROP DATABASE IF EXISTS` so it can
 *                 be executed repeatedly without manual cleanup.
 * ============================================================================
 */


/* ----------------------------------------------------------------------------
 *  1. SESSION SETUP
 *     Create the database and relax MySQL's strict modes so the messy CSV
 *     data (invalid dates, duplicate review IDs) can be cleaned without
 *     being blocked by strict-mode errors.
 * ----------------------------------------------------------------------------
 */
DROP DATABASE IF EXISTS olist_retention;
CREATE DATABASE olist_retention;
USE olist_retention;

SET GLOBAL local_infile = 1;     -- allow CSV import from local filesystem
SET sql_mode            = '';    -- relax strict checks for cleaning steps
SET SQL_SAFE_UPDATES    = 0;     -- allow bulk UPDATE / DROP statements


/* ----------------------------------------------------------------------------
 *  2. TABLE : customers
 *     One row per customer account. customer_unique_id is the TRUE
 *     person-level identifier (customer_id is regenerated per order).
 * ----------------------------------------------------------------------------
 */
CREATE TABLE customers (
    customer_id              VARCHAR(50),
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix INT,
    customer_city            VARCHAR(100),
    customer_state           VARCHAR(10)
);

LOAD DATA LOCAL INFILE 'D:/Khushi backup/Khushi backup/SQL Projects/Project_2_Retention_Analysis/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, customer_unique_id, customer_zip_code_prefix,
 customer_city, customer_state);


/* ----------------------------------------------------------------------------
 *  3. TABLE : orders
 *     One row per order, with status and the key lifecycle timestamps
 *     (purchase, approval, carrier handover, customer delivery).
 * ----------------------------------------------------------------------------
 */
CREATE TABLE orders (
    order_id                      VARCHAR(50),
    customer_id                   VARCHAR(50),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME,
    order_approved_at             DATETIME,
    order_delivered_carrier_date  DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);

LOAD DATA LOCAL INFILE 'D:/Khushi backup/Khushi backup/SQL Projects/Project_2_Retention_Analysis/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, order_status, order_purchase_timestamp,
 order_approved_at, order_delivered_carrier_date,
 order_delivered_customer_date, order_estimated_delivery_date);


/* ----------------------------------------------------------------------------
 *  4. TABLE : order_items
 *     One row per product line within an order. Composite key
 *     (order_id, order_item_id). Holds the price + freight that drive
 *     monetary value for RFM and lifetime-value calculations.
 * ----------------------------------------------------------------------------
 */
CREATE TABLE order_items (
    order_id            VARCHAR(50),
    order_item_id       INT,
    product_id          VARCHAR(50),
    seller_id           VARCHAR(50),
    shipping_limit_date DATETIME,
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2)
);

LOAD DATA LOCAL INFILE 'D:/Khushi backup/Khushi backup/SQL Projects/Project_2_Retention_Analysis/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, order_item_id, product_id, seller_id,
 shipping_limit_date, price, freight_value);


/* ----------------------------------------------------------------------------
 *  5. TABLE : reviews
 *     Customer feedback per order (star score + optional text).
 *     Note: the raw CSV contains some duplicate review_id rows — these are
 *     cleaned in Section 7 before the PRIMARY KEY is added.
 * ----------------------------------------------------------------------------
 */
CREATE TABLE reviews (
    review_id              VARCHAR(50),
    order_id               VARCHAR(50),
    review_score           INT,
    review_comment_title   TEXT,
    review_comment_message TEXT,
    review_creation_date   DATETIME,
    review_answer_timestamp DATETIME
);

LOAD DATA LOCAL INFILE 'D:/Khushi backup/Khushi backup/SQL Projects/Project_2_Retention_Analysis/olist_order_reviews_dataset.csv'
INTO TABLE reviews
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(review_id, order_id, review_score, review_comment_title,
 review_comment_message, review_creation_date, review_answer_timestamp);


/* ----------------------------------------------------------------------------
 *  6. CLEAN BAD DATES
 *     Replace MySQL's invalid '0000-00-00 00:00:00' placeholders with NULL.
 *     This MUST run BEFORE adding NOT NULL constraints or running the
 *     deduplication step (which sorts by review_creation_date).
 * ----------------------------------------------------------------------------
 */

-- orders: three optional date fields can hold the bad placeholder
UPDATE orders SET order_approved_at             = NULL WHERE order_approved_at             = '0000-00-00 00:00:00';
UPDATE orders SET order_delivered_carrier_date  = NULL WHERE order_delivered_carrier_date  = '0000-00-00 00:00:00';
UPDATE orders SET order_delivered_customer_date = NULL WHERE order_delivered_customer_date = '0000-00-00 00:00:00';

-- reviews: both timestamp fields can hold the bad placeholder
UPDATE reviews SET review_creation_date    = NULL WHERE review_creation_date    = '0000-00-00 00:00:00';
UPDATE reviews SET review_answer_timestamp = NULL WHERE review_answer_timestamp = '0000-00-00 00:00:00';


/* ----------------------------------------------------------------------------
 *  7. DEDUPLICATE reviews
 *     The Olist reviews CSV contains some review_id values that appear more
 *     than once. ROW_NUMBER() partitions by review_id and orders by the
 *     creation date (newest first); we keep only rn = 1 — i.e. the most
 *     recent row per review_id. After this step the table is unique on
 *     review_id and ready for a PRIMARY KEY.
 * ----------------------------------------------------------------------------
 */
DROP TABLE IF EXISTS reviews_dedup;

CREATE TABLE reviews_dedup AS
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY review_id
               ORDER BY review_creation_date DESC
           ) AS rn
    FROM reviews
)
SELECT review_id, order_id, review_score,
       review_comment_title, review_comment_message,
       review_creation_date, review_answer_timestamp
FROM ranked
WHERE rn = 1;

DROP TABLE reviews;
RENAME TABLE reviews_dedup TO reviews;


/* ----------------------------------------------------------------------------
 *  8. NOT NULL + PRIMARY KEY CONSTRAINTS
 *     Promote the staged tables into a production-grade schema.
 * ----------------------------------------------------------------------------
 */

-- customers
ALTER TABLE customers
MODIFY customer_id              VARCHAR(50)  NOT NULL,
MODIFY customer_unique_id       VARCHAR(50)  NOT NULL,
MODIFY customer_zip_code_prefix INT          NOT NULL,
MODIFY customer_city            VARCHAR(100) NOT NULL,
MODIFY customer_state           VARCHAR(10)  NOT NULL;
ALTER TABLE customers ADD PRIMARY KEY (customer_id);

-- orders
ALTER TABLE orders
MODIFY order_id                      VARCHAR(50) NOT NULL,
MODIFY customer_id                   VARCHAR(50) NOT NULL,
MODIFY order_status                  VARCHAR(20) NOT NULL,
MODIFY order_purchase_timestamp      DATETIME    NOT NULL,
MODIFY order_estimated_delivery_date DATETIME    NOT NULL;
ALTER TABLE orders ADD PRIMARY KEY (order_id);

-- order_items
ALTER TABLE order_items
MODIFY order_id            VARCHAR(50)    NOT NULL,
MODIFY order_item_id       INT            NOT NULL,
MODIFY product_id          VARCHAR(50)    NOT NULL,
MODIFY seller_id           VARCHAR(50)    NOT NULL,
MODIFY shipping_limit_date DATETIME       NOT NULL,
MODIFY price               DECIMAL(10,2)  NOT NULL,
MODIFY freight_value       DECIMAL(10,2)  NOT NULL;
ALTER TABLE order_items ADD PRIMARY KEY (order_id, order_item_id);

-- reviews
ALTER TABLE reviews
MODIFY review_id    VARCHAR(50) NOT NULL,
MODIFY order_id     VARCHAR(50) NOT NULL,
MODIFY review_score INT         NOT NULL;
ALTER TABLE reviews ADD PRIMARY KEY (review_id);


/* ----------------------------------------------------------------------------
 *  9. FOREIGN KEY CONSTRAINTS
 *     Establish referential integrity between fact and dimension tables.
 * ----------------------------------------------------------------------------
 */

ALTER TABLE orders
ADD CONSTRAINT fk_orders_customers
FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

ALTER TABLE order_items
ADD CONSTRAINT fk_order_items_orders
FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE reviews
ADD CONSTRAINT fk_reviews_orders
FOREIGN KEY (order_id) REFERENCES orders(order_id);


/* ----------------------------------------------------------------------------
 * 10. PERFORMANCE INDEXES
 *     Speed up the cohort / RFM / churn queries in analysis.sql by indexing
 *     the columns that appear in JOINs, GROUP BYs, and WHERE clauses.
 * ----------------------------------------------------------------------------
 */

CREATE INDEX idx_customers_unique_id  ON customers   (customer_unique_id);
CREATE INDEX idx_orders_status_date   ON orders      (order_status, order_purchase_timestamp);
CREATE INDEX idx_orders_customer_id   ON orders      (customer_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);


/* ----------------------------------------------------------------------------
 * 11. FINAL SANITY CHECK
 *     Verify all four tables loaded with the expected row counts.
 *     Expected (approximate):
 *         customers   ~99,441
 *         orders      ~99,441
 *         order_items ~112,650
 *         reviews     ~98,673   (slightly lower than raw CSV after dedup)
 * ----------------------------------------------------------------------------
 */

SELECT 'customers'   AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'orders',                    COUNT(*)              FROM orders
UNION ALL
SELECT 'order_items',               COUNT(*)              FROM order_items
UNION ALL
SELECT 'reviews',                   COUNT(*)              FROM reviews;


/* ============================================================================
 *  END OF schema.sql
 *  Next step → open analysis.sql and run the 15 retention queries.
 * ============================================================================
 */
