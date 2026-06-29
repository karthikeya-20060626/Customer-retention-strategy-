/* =============================================================================
   OLIST SUPPLY CHAIN & DELIVERY PERFORMANCE ANALYSIS
   01_create_tables.sql  |  PostgreSQL
   -----------------------------------------------------------------------------
   Purpose : Create raw staging tables (1:1 with the source CSVs) and the
             analytical star-schema (dimensions + fact) used for all analysis.
   Author  : <your name>  |  Portfolio project
   Notes   : Run order -> 01_create_tables -> 02_load_data -> 03_cleaning
             -> 04_analysis_queries -> 05_final_output
   ========================================================================== */

DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS mart    CASCADE;
CREATE SCHEMA staging;   -- raw loaded data, matches CSVs exactly
CREATE SCHEMA mart;      -- cleaned star schema for analytics / BI

/* ---------------------------------------------------------------------------
   1. STAGING TABLES  (one per source file, no constraints, load-friendly)
   ------------------------------------------------------------------------ */

CREATE TABLE staging.orders (
    order_id                        VARCHAR(40),
    customer_id                     VARCHAR(40),
    order_status                    VARCHAR(20),
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP
);

CREATE TABLE staging.order_items (
    order_id            VARCHAR(40),
    order_item_id       INT,
    product_id          VARCHAR(40),
    seller_id           VARCHAR(40),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2)
);

CREATE TABLE staging.sellers (
    seller_id               VARCHAR(40),
    seller_zip_code_prefix  INT,
    seller_city             VARCHAR(80),
    seller_state            CHAR(2)
);

CREATE TABLE staging.products (
    product_id                  VARCHAR(40),
    product_category_name       VARCHAR(80),
    product_name_lenght         INT,
    product_description_lenght  INT,
    product_photos_qty          INT,
    product_weight_g            NUMERIC(12,2),
    product_length_cm           NUMERIC(12,2),
    product_height_cm           NUMERIC(12,2),
    product_width_cm            NUMERIC(12,2)
);

CREATE TABLE staging.order_reviews (
    review_id               VARCHAR(40),
    order_id                VARCHAR(40),
    review_score            INT,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

CREATE TABLE staging.customers (
    customer_id              VARCHAR(40),
    customer_unique_id       VARCHAR(40),
    customer_zip_code_prefix INT,
    customer_city            VARCHAR(80),
    customer_state           CHAR(2)
);

CREATE TABLE staging.order_payments (
    order_id             VARCHAR(40),
    payment_sequential   INT,
    payment_type         VARCHAR(30),
    payment_installments INT,
    payment_value        NUMERIC(10,2)
);

CREATE TABLE staging.category_translation (
    product_category_name         VARCHAR(80),
    product_category_name_english VARCHAR(80)
);

/* geolocation kept in staging only (optional v2 distance analysis) */
CREATE TABLE staging.geolocation (
    geolocation_zip_code_prefix INT,
    geolocation_lat             NUMERIC(12,6),
    geolocation_lng             NUMERIC(12,6),
    geolocation_city            VARCHAR(80),
    geolocation_state           CHAR(2)
);

/* ---------------------------------------------------------------------------
   2. STAR-SCHEMA (mart)  --  created empty here, populated in 03_cleaning.sql
   ---------------------------------------------------------------------------
   Grain of fact_order_items : ONE ROW PER ORDER ITEM (order_id + order_item_id)
   Order-level delivery timestamps are attributed down to each item; a
   multi-seller order therefore contributes its delay to every seller on it.
   This is a documented simplification (Olist has no item-level ship dates).
   ------------------------------------------------------------------------ */

CREATE TABLE mart.dim_seller (
    seller_id     VARCHAR(40) PRIMARY KEY,
    seller_city   VARCHAR(80),
    seller_state  CHAR(2),
    seller_zip    INT
);

CREATE TABLE mart.dim_customer (
    customer_id        VARCHAR(40) PRIMARY KEY,
    customer_unique_id VARCHAR(40),
    customer_city      VARCHAR(80),
    customer_state     CHAR(2),
    customer_zip       INT
);

CREATE TABLE mart.dim_product (
    product_id        VARCHAR(40) PRIMARY KEY,
    category_pt       VARCHAR(80),
    category_en       VARCHAR(80),
    weight_g          NUMERIC(12,2),
    volume_cm3        NUMERIC(14,2),
    size_band         VARCHAR(10)         -- Small / Medium / Large / XLarge
);

CREATE TABLE mart.dim_date (
    date_key   DATE PRIMARY KEY,
    year       INT,
    quarter    INT,
    month      INT,
    month_name VARCHAR(12),
    year_month CHAR(7)
);

CREATE TABLE mart.fact_order_items (
    order_id            VARCHAR(40),
    order_item_id       INT,
    customer_id         VARCHAR(40) REFERENCES mart.dim_customer(customer_id),
    seller_id           VARCHAR(40) REFERENCES mart.dim_seller(seller_id),
    product_id          VARCHAR(40) REFERENCES mart.dim_product(product_id),
    purchase_date_key   DATE        REFERENCES mart.dim_date(date_key),
    -- money
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
    revenue             NUMERIC(10,2),
    -- delivery measures (days)
    delivery_days       NUMERIC(8,2),   -- purchase -> delivered to customer
    processing_days     NUMERIC(8,2),   -- purchase -> handed to carrier
    transit_days        NUMERIC(8,2),   -- carrier  -> delivered to customer
    estimated_days      NUMERIC(8,2),   -- purchase -> estimated delivery
    delay_days          NUMERIC(8,2),   -- delivered - estimated (+ = late)
    is_late             INT,            -- 1 if delivered after estimate
    is_cross_state      INT,            -- 1 if seller_state <> customer_state
    review_score        NUMERIC(3,2),   -- avg review for the order
    PRIMARY KEY (order_id, order_item_id)
);

CREATE INDEX idx_foi_seller   ON mart.fact_order_items(seller_id);
CREATE INDEX idx_foi_product  ON mart.fact_order_items(product_id);
CREATE INDEX idx_foi_customer ON mart.fact_order_items(customer_id);
CREATE INDEX idx_foi_date     ON mart.fact_order_items(purchase_date_key);
