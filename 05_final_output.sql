/* =============================================================================
   05_final_output.sql  |  PostgreSQL
   -----------------------------------------------------------------------------
   Purpose : Materialise clean summary tables that Power BI / Tableau connect to
             directly, plus the value-creation impact scenario.
   ========================================================================== */

/* ---------- OUT 1: seller scorecard (one row per seller) ------------------- */
DROP TABLE IF EXISTS mart.out_seller_scorecard;
CREATE TABLE mart.out_seller_scorecard AS
WITH s AS (
    SELECT f.seller_id, ds.seller_state,
           COUNT(*) items, 100.0*AVG(f.is_late) late_pct,
           AVG(f.delivery_days) avg_delivery, AVG(f.review_score) avg_review,
           SUM(f.revenue) revenue
    FROM mart.fact_order_items f JOIN mart.dim_seller ds ON f.seller_id=ds.seller_id
    GROUP BY f.seller_id, ds.seller_state
),
thr AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY items) vol_median FROM s)
SELECT s.*,
       CASE
         WHEN items>=vol_median AND late_pct<=8.11 THEN '1 Strategic Partner'
         WHEN items>=vol_median AND late_pct> 8.11 THEN '2 Fix Immediately'
         WHEN items< vol_median AND late_pct> 8.11 THEN '3 Monitor'
         ELSE '4 Maintain' END AS quadrant
FROM s CROSS JOIN thr;

/* ---------- OUT 2: state KPI table ----------------------------------------- */
DROP TABLE IF EXISTS mart.out_state_kpi;
CREATE TABLE mart.out_state_kpi AS
SELECT ds.seller_state,
       COUNT(*) items, 100.0*AVG(f.is_late) late_pct,
       AVG(f.delivery_days) avg_delivery_days, AVG(f.transit_days) avg_transit_days,
       AVG(f.processing_days) avg_processing_days, AVG(f.review_score) avg_review,
       SUM(f.revenue) revenue,
       SUM(f.revenue) FILTER (WHERE f.is_late=1) revenue_at_risk
FROM mart.fact_order_items f JOIN mart.dim_seller ds ON f.seller_id=ds.seller_id
GROUP BY ds.seller_state;

/* ---------- OUT 3: monthly delivery trend ---------------------------------- */
DROP TABLE IF EXISTS mart.out_monthly_trend;
CREATE TABLE mart.out_monthly_trend AS
SELECT dd.year_month,
       COUNT(*) items,
       100.0*AVG(f.is_late) late_pct,
       AVG(f.delivery_days) avg_delivery_days,
       SUM(f.revenue) revenue
FROM mart.fact_order_items f JOIN mart.dim_date dd ON f.purchase_date_key=dd.date_key
GROUP BY dd.year_month
ORDER BY dd.year_month;

/* ---------- OUT 4: VALUE-CREATION IMPACT SCENARIO -------------------------- */
/* Lever: bring "Fix Immediately" sellers (high-vol, >8.11% late) to the
   national late benchmark. Quantifies late deliveries avoided + revenue exposure. */
DROP TABLE IF EXISTS mart.out_impact_scenario;
CREATE TABLE mart.out_impact_scenario AS
WITH base AS (
    SELECT COUNT(*) tot_items, SUM(is_late) tot_late, AVG(revenue) rev_per_item
    FROM mart.fact_order_items
),
fix AS (
    SELECT SUM(items) fix_items, SUM(items*late_pct/100.0) fix_late_now
    FROM mart.out_seller_scorecard WHERE quadrant='2 Fix Immediately'
)
SELECT
    8.11                                                       AS national_late_pct,
    fix.fix_items,
    ROUND(fix.fix_late_now)                                    AS fix_late_now,
    ROUND(fix.fix_items*0.0811)                                AS fix_late_target,
    ROUND(fix.fix_late_now - fix.fix_items*0.0811)             AS late_deliveries_avoided,
    ROUND(100.0*(fix.fix_late_now - fix.fix_items*0.0811)/base.tot_late,1) AS pct_reduction_in_late,
    ROUND(100.0*base.tot_late/base.tot_items,2)                AS late_pct_before,
    ROUND(100.0*(base.tot_late-(fix.fix_late_now-fix.fix_items*0.0811))/base.tot_items,2) AS late_pct_after,
    ROUND((fix.fix_late_now-fix.fix_items*0.0811)*base.rev_per_item,0) AS revenue_exposure_protected
FROM base CROSS JOIN fix;

SELECT * FROM mart.out_impact_scenario;
-- Expected: ~2,000 late deliveries avoided | late% 7.91 -> ~6.1 | ~23% relative cut
