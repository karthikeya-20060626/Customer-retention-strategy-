# Olist Supply Chain & Delivery Performance Analysis

An end-to-end analytics project on the [Brazilian E-Commerce Public Dataset by
Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), framed as a
**post-acquisition supply-chain diagnostic**: a private-equity firm has rolled up
several small Brazilian logistics partners and wants to find the underperforming
hubs, quantify the value at stake, and lay out the fix.

The project takes raw transactional CSVs all the way to a costed, board-ready
recommendation — through SQL modelling, Python analysis, a Power BI dashboard
spec, and a consulting-style slide deck.

---

## Headline findings

| Metric | Value |
|---|---|
| Delivered orders analysed | **96,469** (110,188 order-items) |
| On-time delivery | **92.1%** (7.9% late) |
| Transit share of lead time | **74%** — the last mile is the bottleneck |
| Review score, on-time vs late | **4.29 → 2.57** |
| 1–2★ review share, on-time vs late | **9% → 54%** |
| "Fix Immediately" sellers | **609 sellers holding 40.7% of revenue at 15.9% late** |
| Modelled upside of closing the gap | **~23% fewer late deliveries**, ~R$280K exposure protected |

**The story:** the network looks healthy on average, but lateness is concentrated
in a small set of high-volume sellers and a few weak regions. Because late
delivery roughly halves customer reviews, that concentrated tail is the main
driver of dissatisfaction — and the highest-leverage place to act.

---

## Repository structure

```
Olist_PMI_Project/
├── data/                     # raw Olist CSVs (9 tables)
├── sql/                      # PostgreSQL pipeline (run in order 01 → 05)
│   ├── 01_create_tables.sql  # staging + star-schema (dims + fact)
│   ├── 02_load_data.sql      # \copy bulk loads
│   ├── 03_cleaning.sql       # clean, derive KPIs, populate fact
│   ├── 04_analysis_queries.sql # KPIs, seller matrix, risk score, root cause
│   └── 05_final_output.sql   # BI summary tables + impact scenario
├── notebooks/
│   └── analysis.ipynb        # full Python/pandas analysis (runs end-to-end)
├── powerbi/
│   └── PowerBI_Dashboard_Guide.md  # model, DAX, 3-page dashboard spec
├── presentation/
│   ├── Olist_Consulting_Deck.pptx  # 12-slide consulting deck
│   └── build_deck.js         # PptxGenJS source for the deck
├── outputs/                  # generated charts + CSV extracts
└── README.md
```

---

## How to run

### SQL track (PostgreSQL)
```bash
psql -d olist -f sql/01_create_tables.sql
psql -d olist -f sql/02_load_data.sql      # edit the \copy paths first
psql -d olist -f sql/03_cleaning.sql
psql -d olist -f sql/04_analysis_queries.sql
psql -d olist -f sql/05_final_output.sql
```

### Python track
```bash
pip install pandas numpy matplotlib jupyter
jupyter notebook notebooks/analysis.ipynb   # Cell → Run All
```

### Dashboard
Open `powerbi/PowerBI_Dashboard_Guide.md` and build against the `mart.out_*`
tables (or the CSVs in `/outputs`).

---

## Method notes

- **Grain.** The fact table is one row per *order item*. Olist records delivery
  timestamps at the order level, so for multi-seller orders the delivery outcome
  is attributed to each item/seller on the order — a documented simplification.
- **Late, not delay.** The raw mean of `delay_days` is *negative* because Olist
  pads its delivery estimates, so orders usually arrive early. **Late %** (delivered
  after the estimate) is therefore the honest reliability KPI, not average delay.
- **Scope.** Analysis is restricted to `delivered` orders with a complete
  timestamp chain. Payments and geolocation tables are included in the repo and
  reserved for extensions (distance modelling, hub-location optimisation).

## Tech stack
PostgreSQL · Python (pandas, matplotlib) · Power BI (DAX) · PptxGenJS

> Data source: Olist, *Brazilian E-Commerce Public Dataset* (2016–2018), via Kaggle.
> This is an independent portfolio project and is not affiliated with Olist.
