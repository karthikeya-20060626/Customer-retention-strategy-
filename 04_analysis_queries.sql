/* =============================================================================
   04_analysis_queries.sql  |  PostgreSQL
   -----------------------------------------------------------------------------
   The analytical core. Each section maps to a slide in the consulting deck.
   Run sections independently. All read from mart.fact_order_items.
   ========================================================================== */


/* #############################################################################
   SECTION A — DELIVERY PERFORMANCE KPIs
   ########################################################################## */

/* A0. Headline KPIs (one row) ------------------------------------------------ */
SELECT
    COUNT(DISTINCT order_id)                                  AS delivered_orders,
    COUNT(*)                                                  AS order_items,
    ROUND(100.0*(1-AVG(is_late)),2)                           AS on_time_pct,
    ROUND(100.0*AVG(is_late),2)                               AS late_pct,
    ROUND(AVG(delivery_days),2)                               AS avg_delivery_days,
    ROUND(AVG(processing_days),2)                             AS avg_processing_days,
    ROUND(AVG(transit_days),2)                                AS avg_transit_days,
    ROUND(AVG(delay_days) FILTER (WHERE is_late=1),2)         AS avg_delay_when_late,
    ROUND(SUM(revenue),0)                                     AS total_revenue,
    ROUND(SUM(revenue) FILTER (WHERE is_late=1),0)            AS revenue_on_late_orders,
    ROUND(AVG(review_score),2)                                AS avg_review
FROM mart.fact_order_items;

/* A1. Delivery KPIs by SELLER STATE ----------------------------------------- */
SELECT
    ds.seller_state,
    COUNT(*)                                  AS items,
    ROUND(100.0*AVG(f.is_late),2)             AS late_pct,
    ROUND(AVG(f.delivery_days),2)             AS avg_delivery_days,
    ROUND(AVG(f.processing_days),2)           AS avg_processing_days,
    ROUND(AVG(f.transit_days),2)              AS avg_transit_days,
    ROUND(AVG(f.review_score),2)              AS avg_review,
    ROUND(SUM(f.revenue),0)                   AS revenue
FROM mart.fact_order_items f
JOIN mart.dim_seller ds ON f.seller_id = ds.seller_id
GROUP BY ds.seller_state
HAVING COUNT(*) >= 100          -- suppress thin states
ORDER BY late_pct DESC;

/* A2. Delivery KPIs by PRODUCT CATEGORY ------------------------------------- */
SELECT
    dp.category_en,
    COUNT(*)                                  AS items,
    ROUND(100.0*AVG(f.is_late),2)             AS late_pct,
    ROUND(AVG(f.delivery_days),2)             AS avg_delivery_days,
    ROUND(AVG(f.review_score),2)              AS avg_review,
    ROUND(SUM(f.revenue),0)                   AS revenue
FROM mart.fact_order_items f
JOIN mart.dim_product dp ON f.product_id = dp.product_id
GROUP BY dp.category_en
HAVING COUNT(*) >= 500
ORDER BY late_pct DESC;

/* A3. Delivery KPIs by PRODUCT SIZE BAND (volume / weight) ------------------ */
SELECT
    dp.size_band,
    COUNT(*)                                  AS items,
    ROUND(100.0*AVG(f.is_late),2)             AS late_pct,
    ROUND(AVG(f.delivery_days),2)             AS avg_delivery_days
FROM mart.fact_order_items f
JOIN mart.dim_product dp ON f.product_id = dp.product_id
GROUP BY dp.size_band
ORDER BY late_pct DESC;


/* #############################################################################
   SECTION B — PMI / PE VALUE-CREATION ANALYSIS
   ########################################################################## */

/* B1. Underperforming acquired regions — worst states by late % ------------- */
SELECT
    ds.seller_state,
    COUNT(*)                                  AS items,
    ROUND(100.0*AVG(f.is_late),2)             AS late_pct,
    ROUND(AVG(f.review_score),2)              AS avg_review,
    ROUND(SUM(f.revenue),0)                   AS revenue_exposed
FROM mart.fact_order_items f
JOIN mart.dim_seller ds ON f.seller_id = ds.seller_id
GROUP BY ds.seller_state
HAVING COUNT(*) >= 200
ORDER BY late_pct DESC
LIMIT 10;

/* B2. Operational bottleneck — high-volume + high-late sellers -------------- */
WITH s AS (
    SELECT seller_id,
           COUNT(*)                       AS items,
           100.0*AVG(is_late)             AS late_pct,
           AVG(review_score)              AS avg_review,
           SUM(revenue)                   AS revenue
    FROM mart.fact_order_items
    GROUP BY seller_id
)
SELECT s.seller_id, ds.seller_state,
       s.items, ROUND(s.late_pct,1) AS late_pct,
       ROUND(s.avg_review,2) AS avg_review, ROUND(s.revenue,0) AS revenue
FROM s JOIN mart.dim_seller ds ON s.seller_id = ds.seller_id
WHERE s.items >= 200 AND s.late_pct > 8.11      -- above national late benchmark
ORDER BY s.revenue DESC
LIMIT 10;

/* B3. Review-score impact of late delivery (proves customer damage) --------- */
SELECT
    CASE WHEN is_late=1 THEN 'Late' ELSE 'On-time' END AS delivery_outcome,
    COUNT(*)                                            AS orders,
    ROUND(AVG(review_score),2)                          AS avg_review,
    ROUND(100.0*AVG(CASE WHEN review_score<=2 THEN 1 ELSE 0 END),1) AS pct_1_2_star
FROM (  -- collapse to order grain so multi-item orders aren't double counted
    SELECT order_id, MAX(is_late) AS is_late, AVG(review_score) AS review_score
    FROM mart.fact_order_items
    GROUP BY order_id
) o
WHERE review_score IS NOT NULL
GROUP BY 1;

/* B4. Margin protection — revenue exposed to delay, by state ---------------- */
SELECT
    ds.seller_state,
    ROUND(SUM(f.revenue),0)                                          AS total_revenue,
    ROUND(SUM(f.revenue) FILTER (WHERE f.is_late=1),0)               AS revenue_at_risk,
    ROUND(100.0*SUM(f.revenue) FILTER (WHERE f.is_late=1)/SUM(f.revenue),1) AS pct_at_risk
FROM mart.fact_order_items f
JOIN mart.dim_seller ds ON f.seller_id = ds.seller_id
GROUP BY ds.seller_state
HAVING COUNT(*) >= 200
ORDER BY revenue_at_risk DESC
LIMIT 10;


/* #############################################################################
   SECTION C — ADVANCED FRAMEWORKS
   ########################################################################## */

/* C1. SELLER PERFORMANCE MATRIX (4 quadrants) ------------------------------- */
WITH s AS (
    SELECT seller_id,
           COUNT(*)            AS items,
           100.0*AVG(is_late)  AS late_pct,
           AVG(review_score)   AS avg_review,
           SUM(revenue)        AS revenue
    FROM mart.fact_order_items
    GROUP BY seller_id
),
thr AS (  -- volume threshold = median items per seller; late benchmark = 8.11%
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY items) AS vol_median FROM s
)
SELECT
    CASE
        WHEN s.items >= t.vol_median AND s.late_pct <= 8.11 THEN '1 Strategic Partner'
        WHEN s.items >= t.vol_median AND s.late_pct >  8.11 THEN '2 Fix Immediately'
        WHEN s.items <  t.vol_median AND s.late_pct >  8.11 THEN '3 Monitor'
        ELSE                                                     '4 Maintain'
    END                                       AS quadrant,
    COUNT(*)                                  AS sellers,
    SUM(s.items)                              AS items,
    ROUND(SUM(s.revenue),0)                   AS revenue,
    ROUND(100.0*SUM(s.revenue)/SUM(SUM(s.revenue)) OVER (),1) AS revenue_pct,
    ROUND(AVG(s.late_pct),1)                  AS avg_late_pct
FROM s CROSS JOIN thr t
GROUP BY 1
ORDER BY 1;

/* C2. SUPPLY-CHAIN RISK SCORE per seller (0-100, weighted min-max) ---------- */
WITH s AS (
    SELECT f.seller_id, ds.seller_state,
           COUNT(*)                                       AS items,
           100.0*AVG(f.is_late)                           AS late_pct,
           AVG(f.delay_days) FILTER (WHERE f.is_late=1)   AS avg_delay_late,
           AVG(f.review_score)                            AS avg_review,
           SUM(f.revenue)                                 AS revenue
    FROM mart.fact_order_items f
    JOIN mart.dim_seller ds ON f.seller_id = ds.seller_id
    GROUP BY f.seller_id, ds.seller_state
),
norm AS (
    SELECT *,
        (late_pct - MIN(late_pct) OVER())/NULLIF(MAX(late_pct) OVER()-MIN(late_pct) OVER(),0)                         AS r_late,
        (COALESCE(avg_delay_late,0)-MIN(COALESCE(avg_delay_late,0)) OVER())
            /NULLIF(MAX(COALESCE(avg_delay_late,0)) OVER()-MIN(COALESCE(avg_delay_late,0)) OVER(),0)                  AS r_delay,
        ((5-COALESCE(avg_review,4))-MIN(5-COALESCE(avg_review,4)) OVER())
            /NULLIF(MAX(5-COALESCE(avg_review,4)) OVER()-MIN(5-COALESCE(avg_review,4)) OVER(),0)                      AS r_review,
        (LN(items+1)-MIN(LN(items+1)) OVER())/NULLIF(MAX(LN(items+1)) OVER()-MIN(LN(items+1)) OVER(),0)               AS r_vol
    FROM s
)
SELECT seller_id, seller_state, items,
       ROUND(late_pct,1) AS late_pct, ROUND(avg_review,2) AS avg_review, ROUND(revenue,0) AS revenue,
       ROUND( (0.35*r_late + 0.20*r_delay + 0.25*r_review + 0.20*r_vol)*100 ,1) AS risk_score
FROM norm
WHERE items >= 50          -- volume floor so the ranking is actionable, not noise
ORDER BY risk_score DESC
LIMIT 15;

/* C3. ROOT CAUSE — decomposition ------------------------------------------- */
-- (a) lead-time split: processing vs transit  (transit ~74% of total)
SELECT ROUND(AVG(processing_days),2) AS avg_processing,
       ROUND(AVG(transit_days),2)    AS avg_transit,
       ROUND(100.0*AVG(transit_days)/(AVG(processing_days)+AVG(transit_days)),0) AS transit_share_pct
FROM mart.fact_order_items;

-- (b) geography: same-state vs cross-state
SELECT CASE WHEN is_cross_state=1 THEN 'Cross-state' ELSE 'Same-state' END AS route,
       COUNT(*) AS items, ROUND(100.0*AVG(is_late),2) AS late_pct,
       ROUND(AVG(transit_days),2) AS avg_transit_days
FROM mart.fact_order_items
GROUP BY 1 ORDER BY 1;

-- (c) product size effect
SELECT dp.size_band, COUNT(*) AS items, ROUND(100.0*AVG(f.is_late),2) AS late_pct
FROM mart.fact_order_items f JOIN mart.dim_product dp ON f.product_id=dp.product_id
GROUP BY dp.size_band ORDER BY late_pct DESC;

-- (d) seller effect WITHIN one geography (SP): spread of late% = seller-driven variance
WITH sp AS (
    SELECT f.seller_id, COUNT(*) items, AVG(f.is_late) late_rate
    FROM mart.fact_order_items f JOIN mart.dim_seller ds ON f.seller_id=ds.seller_id
    WHERE ds.seller_state='SP' GROUP BY f.seller_id HAVING COUNT(*)>=100
)
SELECT ROUND(100*percentile_cont(0.10) WITHIN GROUP (ORDER BY late_rate),1) AS p10_late,
       ROUND(100*percentile_cont(0.50) WITHIN GROUP (ORDER BY late_rate),1) AS median_late,
       ROUND(100*percentile_cont(0.90) WITHIN GROUP (ORDER BY late_rate),1) AS p90_late
FROM sp;
