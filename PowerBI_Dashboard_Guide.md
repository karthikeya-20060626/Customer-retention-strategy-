# Power BI Dashboard — Design & Build Guide
### Olist Supply Chain & Delivery Performance

This guide specifies the full Power BI model: data connections, relationships,
DAX measures, the three report pages, visuals, and slicers. Build it against the
summary tables produced by `sql/05_final_output.sql` (or load the cleaned CSVs in
`/outputs`).

---

## 1. Data model & relationships

Load these tables (from the `mart` schema or the exported CSVs):

| Table | Grain | Role |
|---|---|---|
| `fact_order_items` | one row per order item | **Fact** |
| `dim_seller` | one row per seller | Dimension |
| `dim_customer` | one row per customer | Dimension |
| `dim_product` | one row per product | Dimension |
| `dim_date` | one row per calendar day | Dimension (mark as date table) |

**Relationships (all single-direction, one-to-many from dim → fact):**

```
dim_seller[seller_id]      1 --- *  fact_order_items[seller_id]
dim_customer[customer_id]  1 --- *  fact_order_items[customer_id]
dim_product[product_id]    1 --- *  fact_order_items[product_id]
dim_date[date_key]         1 --- *  fact_order_items[purchase_date_key]
```

Set cross-filter direction to **Single** (dim filters fact). Mark `dim_date` as a
date table on `date_key`. Keep `fact_order_items` as the only fact to avoid
ambiguous paths — this is a clean single-fact star, which is what you want to be
able to explain in an interview.

> If you prefer to skip SQL entirely: load the `/outputs/*.csv` files plus the
> nine raw CSVs, do the cleaning in Power Query (filter `order_status = "delivered"`,
> add the day-difference columns), and build the same star.

---

## 2. Core DAX measures

Create a dedicated `_Measures` table (Enter Data → blank table) and add these.

### Base counts & reliability
```DAX
Total Orders = DISTINCTCOUNT ( fact_order_items[order_id] )

Total Items = COUNTROWS ( fact_order_items )

Late Orders = CALCULATE ( [Total Orders], fact_order_items[is_late] = 1 )

Late Delivery % =
DIVIDE (
    CALCULATE ( COUNTROWS ( fact_order_items ), fact_order_items[is_late] = 1 ),
    COUNTROWS ( fact_order_items )
)

On-Time Delivery % = 1 - [Late Delivery %]
```

### Timing
```DAX
Avg Delivery Days   = AVERAGE ( fact_order_items[delivery_days] )
Avg Processing Days = AVERAGE ( fact_order_items[processing_days] )
Avg Transit Days    = AVERAGE ( fact_order_items[transit_days] )

Avg Delay When Late =
CALCULATE ( AVERAGE ( fact_order_items[delay_days] ), fact_order_items[is_late] = 1 )

Transit Share % =
DIVIDE ( [Avg Transit Days], [Avg Transit Days] + [Avg Processing Days] )
```

### Money & risk
```DAX
Total Revenue = SUM ( fact_order_items[revenue] )

Revenue At Risk =
CALCULATE ( SUM ( fact_order_items[revenue] ), fact_order_items[is_late] = 1 )

Revenue At Risk % = DIVIDE ( [Revenue At Risk], [Total Revenue] )

Avg Review Score = AVERAGE ( fact_order_items[review_score] )
```

### Customer impact (proves the delay → satisfaction link)
```DAX
Avg Review (Late) =
CALCULATE ( [Avg Review Score], fact_order_items[is_late] = 1 )

Avg Review (On-Time) =
CALCULATE ( [Avg Review Score], fact_order_items[is_late] = 0 )

Bad Review Rate =                      -- share of 1–2★
DIVIDE (
    CALCULATE ( COUNTROWS ( fact_order_items ), fact_order_items[review_score] <= 2 ),
    CALCULATE ( COUNTROWS ( fact_order_items ), NOT ISBLANK ( fact_order_items[review_score] ) )
)
```

### Seller risk score (0–100) — measure version
```DAX
Seller Risk Score =
VAR _late   = [Late Delivery %]
VAR _review = [Avg Review Score]
VAR _vol    = [Total Items]
RETURN
    0.45 * ( _late * 100 )                              -- reliability weight
  + 0.30 * ( ( 5 - _review ) / 5 * 100 )               -- dissatisfaction weight
  + 0.25 * ( DIVIDE ( _vol, 2000 ) * 100 )             -- exposure weight (cap ~2000)
```
> For the static, pre-computed score use the `risk_score` column already in
> `out_seller_scorecard`. The measure above is the dynamic version that responds
> to slicers — show both and explain the trade-off (pre-computed = stable league
> table; measure = drill-anywhere).

### Value-creation scenario (what-if)
```DAX
-- Add a What-If parameter "Target Late %" (0–8%, step 0.5)
Late Deliveries Avoided =
VAR _target = SELECTEDVALUE ( 'Target Late %'[Target Late % Value] )
VAR _now    = [Late Orders]
VAR _floor  = [Total Items] * _target
RETURN MAX ( _now - _floor, 0 )
```

---

## 3. Page 1 — Executive Overview

**Goal:** one screen a partner/operating-partner can read in 30 seconds.

**KPI cards (row across the top):**
`Total Orders` · `On-Time Delivery %` · `Avg Delivery Days` · `Revenue At Risk` · `Avg Review Score`

**Visuals:**
- **Brazil state map** (Filled/Shape map): location = `dim_seller[seller_state]`,
  colour saturation = `Late Delivery %` (red = worse). This is your "underperforming
  hubs" heatmap.
- **Line chart — delivery trend:** axis = `dim_date[year_month]`, value = `Late Delivery %`,
  with a constant line at the national 8.1% benchmark.
- **Histogram / column — delay distribution:** axis = binned `delay_days`, value = item count.

**Conditional formatting:** turn the `On-Time Delivery %` card green ≥ 92%, amber 88–92%, red < 88%.

---

## 4. Page 2 — Operations Performance

**Goal:** find *who* and *what* to fix.

- **Seller Performance Matrix** (scatter): X = `Total Items` (log), Y = `Late Delivery %`,
  size = `Total Revenue`, legend = `out_seller_scorecard[quadrant]`. Add gridlines at
  X = seller-volume median and Y = 8.1% to draw the four quadrants.
- **Top 10 worst sellers** (table/bar): filter to `quadrant = "2 Fix Immediately"`,
  sort by `Total Revenue` desc, show `Late Delivery %`, `Avg Review Score`, `Revenue`.
- **Volume vs delay scatter** by product: X = item volume, Y = `Late Delivery %`,
  legend = `dim_product[size_band]`.
- **Category delay bar:** axis = `dim_product[category_en]`, value = `Late Delivery %`,
  top-N filter = 10.

---

## 5. Page 3 — PMI Value-Creation Plan

**Goal:** turn the diagnosis into money and actions.

- **What-if slider** ("Target Late %") driving `Late Deliveries Avoided` and a
  before/after clustered column (`Late Delivery %` now vs target).
- **Cost-saving / opportunity table:** quadrant → sellers → revenue → avg late % →
  recommended action (text column you add).
- **Before vs after impact cards:** `Late Delivery %` before/after, `Late Deliveries Avoided`,
  `Revenue At Risk` recovered.
- **Recommendation callouts** (text boxes): consolidate hubs · renegotiate 3PL ·
  redesign delivery zones · seller incentive scheme.

---

## 6. Slicers / filters (put on every page)

- `dim_date[year_month]` — timeline slicer
- `dim_seller[seller_state]` — state
- `dim_product[category_en]` — category
- `dim_product[size_band]` — product size
- `out_seller_scorecard[quadrant]` — performance segment

Use a **sync-slicers** setup so state/date selections carry across pages. Add a
"Reset filters" bookmark button.

---

## 7. Formatting notes (make it look senior, not student)

- One accent colour for "good" (teal/green), one for "risk" (red), neutral grey for context. No rainbow.
- Right-align all numbers; show `%` to 1 decimal, money as `R$ #,0`.
- Titles state the *insight*, not the field name: "Late delivery halves review scores",
  not "Avg review by is_late".
- Keep ≤ 5 visuals per page. White space is a feature.
- Add a thin footer: data source (Olist 2016–2018), and "delivered orders only" caveat.
