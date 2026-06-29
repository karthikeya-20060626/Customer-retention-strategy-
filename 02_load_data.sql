/* =============================================================================
   02_load_data.sql  |  PostgreSQL
   -----------------------------------------------------------------------------
   Purpose : Bulk-load the raw CSVs into the staging schema.
   How to run:
     - psql : \i 02_load_data.sql   (server must see the file paths below)
     - OR run each \copy from the psql client (client-side paths, recommended).
   Edit the path prefix below to match where you saved /data.
   ========================================================================== */

-- \copy reads from the CLIENT machine (works without superuser). Recommended.
-- Replace the absolute path with your own project /data folder.

\copy staging.orders               FROM 'data/olist_orders.csv'                    WITH (FORMAT csv, HEADER true);
\copy staging.order_items          FROM 'data/olist_order_items.csv'               WITH (FORMAT csv, HEADER true);
\copy staging.sellers              FROM 'data/olist_sellers.csv'                   WITH (FORMAT csv, HEADER true);
\copy staging.products             FROM 'data/olist_products.csv'                  WITH (FORMAT csv, HEADER true);
\copy staging.order_reviews        FROM 'data/olist_order_reviews.csv'             WITH (FORMAT csv, HEADER true);
\copy staging.customers            FROM 'data/olist_customers.csv'                 WITH (FORMAT csv, HEADER true);
\copy staging.order_payments       FROM 'data/olist_order_payments.csv'            WITH (FORMAT csv, HEADER true);
\copy staging.category_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true);
\copy staging.geolocation          FROM 'data/olist_geolocation.csv'               WITH (FORMAT csv, HEADER true);

-- quick load check
SELECT 'orders'        AS tbl, count(*) FROM staging.orders
UNION ALL SELECT 'order_items',    count(*) FROM staging.order_items
UNION ALL SELECT 'sellers',        count(*) FROM staging.sellers
UNION ALL SELECT 'products',       count(*) FROM staging.products
UNION ALL SELECT 'order_reviews',  count(*) FROM staging.order_reviews
UNION ALL SELECT 'customers',      count(*) FROM staging.customers
UNION ALL SELECT 'order_payments', count(*) FROM staging.order_payments
ORDER BY 1;
-- Expected (approx): orders 99,441 | order_items 112,650 | sellers 3,095
--                    products 32,951 | reviews 99,224 | customers 99,441
