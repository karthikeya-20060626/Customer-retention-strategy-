/* =============================================================================
   03_cleaning.sql  |  PostgreSQL
   -----------------------------------------------------------------------------
   Purpose : Clean staging data and populate the mart star-schema.
   Key decisions (documented for the client database):
     1. Analysis is restricted to order_status = 'delivered' -> only delivered
        orders have the full set of timestamps needed for delivery KPIs.
     2. Rows missing delivered/estimated/purchase/carrier timestamps are dropped
        (a few hundred rows; cannot compute lead time without them).
     3. delay_days > 0  => late;  the raw mean of delay_days is NEGATIVE because
        Olist sets padded (conservative) estimates, so LATE % is the headline
        reliability metric, not average delay.
     4. Grain of fact = order item. Order-level timings attributed to each item.
   ========================================================================== */

/* ---------- DIM: SELLER ---------- */
INSERT INTO mart.dim_seller (seller_id, seller_city, seller_state, seller_zip)
SELECT DISTINCT seller_id,
       lower(trim(seller_city)),
       upper(seller_state),
       seller_zip_code_prefix
FROM staging.sellers
WHERE seller_id IS NOT NULL;

/* ---------- DIM: CUSTOMER ---------- */
INSERT INTO mart.dim_customer (customer_id, customer_unique_id, customer_city, customer_state, customer_zip)
SELECT DISTINCT customer_id, customer_unique_id,
       lower(trim(customer_city)), upper(customer_state), customer_zip_code_prefix
FROM staging.customers
WHERE customer_id IS NOT NULL;

/* ---------- DIM: PRODUCT (+ english category + size band) ---------- */
INSERT INTO mart.dim_product (product_id, category_pt, category_en, weight_g, volume_cm3, size_band)
SELECT p.product_id,
       p.product_category_name,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown'),
       p.product_weight_g,
       (p.product_length_cm * p.product_height_cm * p.product_width_cm)        AS volume_cm3,
       CASE
           WHEN p.product_weight_g IS NULL                       THEN 'Unknown'
           WHEN p.product_weight_g <  500                        THEN 'Small'
           WHEN p.product_weight_g <  2000                       THEN 'Medium'
           WHEN p.product_weight_g < 10000                       THEN 'Large'
           ELSE 'XLarge'
       END                                                                      AS size_band
FROM staging.products p
LEFT JOIN staging.category_translation t
       ON p.product_category_name = t.product_category_name;

/* ---------- DIM: DATE ---------- */
INSERT INTO mart.dim_date (date_key, year, quarter, month, month_name, year_month)
SELECT d::date,
       EXTRACT(year    FROM d)::int,
       EXTRACT(quarter FROM d)::int,
       EXTRACT(month   FROM d)::int,
       to_char(d,'Mon'),
       to_char(d,'YYYY-MM')
FROM generate_series('2016-01-01'::date, '2018-12-31'::date, interval '1 day') d;

/* ---------- CLEANED ORDER-LEVEL CTE -> reused below ---------- */
DROP VIEW IF EXISTS mart.v_orders_clean CASCADE;
CREATE VIEW mart.v_orders_clean AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    /* delivery KPIs in days */
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))/86400      AS delivery_days,
    EXTRACT(EPOCH FROM (o.order_delivered_carrier_date  - o.order_purchase_timestamp))/86400      AS processing_days,
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date))/86400  AS transit_days,
    EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp))/86400      AS estimated_days,
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date))/86400 AS delay_days,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END AS is_late
FROM staging.orders o
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp      IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_delivered_carrier_date  IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;

/* ---------- per-order average review ---------- */
DROP VIEW IF EXISTS mart.v_order_review CASCADE;
CREATE VIEW mart.v_order_review AS
SELECT order_id, AVG(review_score::numeric) AS review_score
FROM staging.order_reviews
GROUP BY order_id;

/* ---------- POPULATE FACT ---------- */
INSERT INTO mart.fact_order_items
SELECT
    i.order_id,
    i.order_item_id,
    oc.customer_id,
    i.seller_id,
    i.product_id,
    oc.order_purchase_timestamp::date                       AS purchase_date_key,
    i.price,
    i.freight_value,
    (i.price + i.freight_value)                             AS revenue,
    ROUND(oc.delivery_days,2),
    ROUND(oc.processing_days,2),
    ROUND(oc.transit_days,2),
    ROUND(oc.estimated_days,2),
    ROUND(oc.delay_days,2),
    oc.is_late,
    CASE WHEN ds.seller_state <> dc.customer_state THEN 1 ELSE 0 END AS is_cross_state,
    ROUND(r.review_score,2)
FROM staging.order_items i
JOIN mart.v_orders_clean oc ON i.order_id   = oc.order_id
LEFT JOIN mart.dim_seller   ds ON i.seller_id   = ds.seller_id
LEFT JOIN mart.dim_customer dc ON oc.customer_id = dc.customer_id
LEFT JOIN mart.v_order_review r ON i.order_id   = r.order_id;

/* ---------- sanity checks ---------- */
SELECT count(*)                                   AS fact_rows,        -- ~110,188
       ROUND(100.0*AVG(is_late),2)                AS late_pct,         -- ~7.9
       ROUND(AVG(delivery_days),2)                AS avg_delivery_days,-- ~12.5
       ROUND(AVG(processing_days),2)              AS avg_processing,   -- ~3.3
       ROUND(AVG(transit_days),2)                 AS avg_transit       -- ~9.2
FROM mart.fact_order_items;
