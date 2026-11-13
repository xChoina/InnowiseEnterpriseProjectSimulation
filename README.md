# Olist E-Commerce Analytics & Data Warehouse Project

End-to-end analytics project based on the **Brazilian E-Commerce Public Dataset by Olist**.

Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Large project files (including the Power BI deliverable, where uploaded) are shared through the [project's Google Drive folder](https://drive.google.com/drive/folders/17D5ruFOP2abx_2WDHfSYO2Ie8TYE5-0n?usp=sharing). The folder link is a shared project location, not a verified direct link to a specific `.pbix` file.

The project covers three roles and stages:

- **Stage 1 — Junior Data Analyst:** data cleaning, profiling, EDA, feature engineering, customer analytics and RFM segmentation.
- **Stage 2 — Junior Data Engineer:** initial/delta simulation, PostgreSQL DWH architecture, incremental loading, SCD handling and Star Schema preparation.
- **Stage 3 — BI Developer:** Power BI semantic model and business dashboards for strategic and operational reporting.

---

## Project Flow

```text
Olist Raw CSV files
        |
        +--------------------------+
        |                          |
        v                          v
Stage 1 — Python analysis      Stage 2 — Python load simulation
        |                          |
        +--> Cleaned reference     +--> initial_load.csv
        |    dataset               +--> delta_load.csv
        |
        +--> RFM segmentation ---------> stage.rfm_temp
                                   |
                                   v
                              PostgreSQL
                         Stage -> Core -> Mart
                                   |
                                   v
                               Power BI
```

Stage 2 is rebuilt from the original Olist source data rather than from the Stage 1 cleaned analytical dataset. It also joins the Olist geolocation dataset using customer ZIP prefix and state, after aggregating duplicate geolocation points to median coordinates. Stage 1 produces a delivered-order/positive-weight dataset for EDA and a separate RFM table calculated from eligible purchase records. The RFM output is loaded into PostgreSQL and exposed by the customer Mart dimension.

Architecture diagrams are stored with the Stage 2 files:

- `flowchart_olist.png`
- `CORE_ERD_DIAG.png`
- `MART_ERD_DIAG.png`

---

# Stage 1 — Data Analysis

Main file:

```text
stage1.ipynb
```

## Source files

Stage 1 and Stage 2 use the following six original Olist CSV datasets:

```text
olist_order_items_dataset.csv
olist_orders_dataset.csv
olist_customers_dataset.csv
olist_products_dataset.csv
product_category_name_translation.csv
olist_geolocation_dataset.csv
```

The main analytical dataset is built with left merges of order items, orders, customers, products and the product-category translation table. Geolocation is also joined using customer ZIP-code prefix and state, after aggregating source coordinates by ZIP-code prefix and state (median latitude/longitude) to avoid duplicating transactions. Stage 1 additionally uses state-level geolocation averages for its exploratory map; Stage 2 carries the enriched customer coordinates into the warehouse.

The analysis runs on the full merged dataset; no artificial 10,000-row sample is applied before cleaning.

## Data preparation and feature engineering

The notebook performs:

- standardized column naming,
- duplicate detection and removal,
- datetime conversion,
- filtering the **cleaned EDA / ground-truth dataset** to `order_status == 'delivered'` and `product_weight_g > 0` (this filter is **not** used to define RFM eligibility),
- filling missing translated product categories with `Unknown`,
- customer-city standardization,
- categorical and time-based feature engineering.

Created analytical features include:

- `value_tier`,
- `purchase_day_of_week`,
- `category_keyword`,
- department grouping,
- `regional_manager` mapping.

### Simulated analytical fields

Some business attributes do not exist in the original Olist dataset and are generated only for analytical exercises:

- `product_cost` and `profit_margin` are simulated from a reproducible random cost multiplier (`np.random.seed(24)`),
- `loyalty_status` is simulated as `Standard` / `Premium`,
- `regional_manager` is assigned from customer state for hierarchical analysis.

These fields are illustrative only. In particular, simulated product cost and profit margin are **not** treated as real financial KPIs and are not propagated into the production Mart.

## Automated profiling

The cleaned analytical dataset is profiled with **Sweetviz**.

Generated report:

```text
Brazilian_Ecomerce_report_final.html
```

## Technical function coverage

Stage 1 explicitly demonstrates the required pandas / NumPy functionality, including:

```text
groupby / agg / nunique / transform
pivot_table / melt
merge / map
np.where
pd.qcut / pd.cut
pct_change / rolling / nlargest
query
.dt / .str
apply
```

Examples include a pivoted department comparison, melted rolling time-series data, `np.where()` for simulated loyalty status, `pct_change()` for monthly revenue dynamics and `pd.cut()` for frequency scoring.

## Exploratory Data Analysis

### Static analysis

The notebook includes:

- a 7-day rolling trend for product revenue and freight value,
- freight-value distribution for the Top 5 states,
- Revenue vs Freight Cost comparison by department using `pivot_table`,
- an illustrative simulated profit-margin analysis with an explicit limitation note.

### Interactive analysis

Plotly is used for:

- geographical analysis by Brazilian state,
- hierarchical analysis through:

```text
Regional Manager -> State -> Main Department
```

The hierarchy is used to identify operationally problematic category/region combinations, with the notebook highlighting Home & Living in the North-region manager group as the main example based on freight behavior.

## Customer analytics

### Monthly metrics

The notebook calculates:

- total revenue,
- total orders,
- unique customers,
- Average Order Value (AOV),
- Average Revenue Per User (ARPU),
- month-over-month revenue percentage change.

**Stage 1 revenue is defined as the sum of product `price` only.** Freight is analyzed separately.

### Cohort analysis

Customers are assigned to cohorts based on the month of their first purchase using `transform('min')`.

The retention matrix uses:

```text
cohort_month
cohort_index
```

The notebook identifies a strong post-purchase drop-off, with Month 1 retention typically around 0.1%–0.3% in this cleaned analytical population.

### RFM segmentation

RFM is calculated in a **separate pass over the original merged source data** (`df_raw`), rather than over the delivered-only/positive-weight cleaned EDA dataset. This preserves eligible purchases regardless of whether the order has already been delivered and regardless of product weight.

**RFM eligibility** requires:

- `order_status` in `approved`, `invoiced`, `processing`, `shipped`, `delivered`;
- non-null `customer_unique_id`, `order_purchase_timestamp`, and product `price`.

Orders with `canceled`, `unavailable`, or `created` status are not eligible. No `product_weight_g` condition is used for RFM.

The metrics are grouped by `customer_unique_id`:

- **Recency** — days between the customer's latest eligible **purchase timestamp** and a snapshot date calculated as `max(eligible order_purchase_timestamp) + 1 day` (not a fixed hard-coded date).
- **Frequency** — distinct count of `order_id`.
- **Monetary** — sum of product `price`, excluding freight.

RFM Monetary and Stage 1 product-only revenue differ from the Stage 3 reporting definition of revenue, where `total_value = price + freight_value`. This is an intentional metric-definition difference.

Scoring uses `pd.qcut()` for Recency and Monetary (four quantiles) and `pd.cut()` for Frequency with order-count groups `1`, `2`, `3`, and `4+`. The original five-segment business rules are retained:

- **Champion** — recent, frequent, high-monetary customers (`r >= 3`, `f >= 3`, `m >= 3`).
- **Newbies** — most recent recency group, one order (`r = 4`, `f = 1`).
- **At risk** — low recency, at least two orders and high monetary score (`r <= 2`, `f >= 2`, `m >= 3`).
- **Sleeping** — oldest recency group with one order (`r = 1`, `f = 1`).
- **Regulars** — all other eligible customers.

Final RFM customer distribution, verified against the refreshed PostgreSQL Mart:

| Segment | Customers |
|---|---:|
| Regulars | 47,681 |
| Sleeping | 23,137 |
| Newbies | 22,959 |
| At risk | 1,063 |
| Champion | 143 |
| **Total segmented** | **94,983** |

There are **95,420** distinct customers in the original merged source. **437** do not meet RFM eligibility: **431 canceled-only** and **6 unavailable-only** customers. Their RFM fields and segment remain `NULL`; they do **not** constitute a sixth behavioral segment named `Not Segmented`.

The revised logic segments **1,644 more customers** than the previous delivered-only/positive-weight method (93,339). The revised RFM table is the version exported to `olist_rfm_segmentation.csv` and loaded into `stage.rfm_temp`.

The notebook also displays the Top 5 customers by Monetary value in each segment.

## Stage 1 outputs

```text
olist_cleaned_dataset_ground_truth.csv
olist_rfm_segmentation.csv
Brazilian_Ecomerce_report_final.html
```

The cleaned dataset is a reference / ground-truth analytical output. It is **not** the main Stage 2 pipeline source.

`olist_rfm_segmentation.csv` is loaded into `stage.rfm_temp` and enriches `mart.dim_customer`: its main RFM metrics apply to current customer versions, while the SQL-derived `current_rfm_segment` is also available on historical SCD2 versions.

### Stage 1 Ground Truth vs Stage 2 Pipeline Data

The Stage 1 cleaned ground-truth dataset is not expected to have the same number of rows as the Stage 2 `initial_load.csv` + `delta_load.csv`.

Stage 1 is an analytical dataset and applies additional filtering, including:

- `order_status == 'delivered'`
- `product_weight_g > 0`

As a result, the Stage 1 ground-truth dataset contains approximately 110k analytical rows.

Stage 2 is built independently from the original Olist transactional source and preserves all order statuses before warehouse transformations. Therefore, the combined initial and delta datasets contain approximately 112k rows.

The difference is intentional and does not indicate missing data or a pipeline error. The cleaned Stage 1 output is used for EDA and ground-truth analytical exercises. **RFM is independently computed from eligible purchase records in `df_raw`**, while Stage 2 represents the broader transactional pipeline, including all order statuses.

---

# Stage 2 — Data Engineering

Main file:

```text
stage2.ipynb
```

Stage 2 simulates a production-style incremental pipeline from the original Olist transactional data.

## Initial and Delta simulation

The dataset is sorted by `order_purchase_timestamp` and split chronologically into:

```text
90% -> initial_load.csv
10% -> natural later-order delta
```
The delta is then enriched with controlled test cases for the required loading scenarios:

- **new records** — naturally later records from the 10% chronological delta,
- **SCD Type 1** — an existing product-category translation is manually changed from `health_beauty` to `health_and_beauty` while keeping the same `product_category_name` business key,
- **SCD Type 2** — in addition to natural customer address changes in the source, 10 existing customers with later orders are deliberately moved to `RJ / rio de janeiro / 20010`, including the matching geographic coordinates,
- **exact duplicates** — selected initial-load rows are repeated to test idempotency.

The SCD1 change is displayed in the notebook as a before/after comparison.

No artificial `order_id` is created for the SCD2 test. The manually injected location changes are attached to real later orders of existing customers. During the delta load, the previous customer version is closed and a new current version is created.

The notebook exports:

```text
initial_load.csv
delta_load.csv
```

### Geolocation enrichment

The additional source, `olist_geolocation_dataset.csv`, is merged using `customer_zip_code_prefix` + `customer_state` against the corresponding geolocation ZIP prefix and state. Geolocation points are first grouped by ZIP/state and summarized with median latitude and longitude to prevent one-to-many join duplication. ZIP prefixes are handled as strings.

The merged transactional dataset retains **112,650 order-item rows**. Four geolocation-related fields are exported in the CSVs: `geolocation_zip_code_prefix`, `geolocation_state`, `geolocation_lat`, and `geolocation_lng`. Coordinates continue through Stage and Core to `mart.dim_customer`; the two geolocation join keys are not duplicated as independent customer attributes in Core. Missing coordinates remain nullable. Known out-of-country coordinate outliers are documented under [Outstanding Items](#outstanding-items) and have not yet been cleaned from the ETL.

---

# PostgreSQL DWH Architecture

The warehouse follows:

```text
Source -> Stage -> Core -> Mart -> Power BI
```

## Stage layer

Tables:

```text
stage.raw_orders
stage.rfm_temp
```

`stage.raw_orders` is a flat landing table representing the current load batch. Keeping the Stage layer flat minimizes transformation at ingestion and preserves the source batch before normalization.

`stage.rfm_temp` stores the Stage 1 RFM result and is intentionally preserved when `stage.raw_orders` is reset for the delta batch. The Stage landing table includes the four additional geolocation CSV fields; its column order must match the generated CSV files when using PostgreSQL `COPY`.

## Core layer — 3NF

Core tables:

```text
core.customers
core.orders
core.order_items
core.products
core.product_categories
core.sellers
```

The Core layer separates transactional entities and product category translation instead of keeping the flat Stage structure.

### Customer SCD Type 2

`core.customers` contains:

```text
customer_sk
customer_unique_id
customer_zip_code_prefix
customer_city
customer_state
geolocation_lat
geolocation_lng
valid_from
valid_to
is_current
```

`customer_sk` is the surrogate primary key. Location changes in:

```text
customer_zip_code_prefix
customer_city
customer_state
```

create new SCD Type 2 versions.

The validity interval uses a half-open temporal model:

```text
valid_from <= order_purchase_timestamp < valid_to
```

The final current version ends at:

```text
9999-12-31 23:59:59
```

A partial unique index ensures only one current version exists for each `customer_unique_id`. In addition to natural address changes, the simulated delta manually changes 10 existing customers to `RJ / rio de janeiro / 20010`. The matching coordinates are stored on the new version; the previous version is closed by updating `valid_to` and `is_current = FALSE`. The SCD2 change detection is based on ZIP prefix, city and state; coordinates are carried as attributes of each version.

A post-load check confirmed an example transition from `SC / florianopolis / 88058` to `RJ / rio de janeiro / 20010`, with contiguous validity periods and one current version.

`core.orders` keeps `customer_unique_id` rather than a physical foreign key to one customer version. The correct `customer_sk` is resolved later by the temporal join when the fact table is loaded.

### SCD Type 1

SCD Type 1 is used for dimension attributes where the latest value should overwrite the previous value without preserving history.

The simulated delta manually changes an existing product-category translation:

```text
product_category_name: beleza_saude
before: health_beauty
after:  health_and_beauty
```

The business key `product_category_name` remains unchanged, while `product_category_name_english` is overwritten through `ON CONFLICT ... DO UPDATE`.

The notebook displays the manually injected value before and after the change. Product and product-category upserts use the same overwrite approach for changed dimension attributes.

### Deduplication and idempotency

Natural transaction keys and database constraints prevent duplicate insertion:

```text
orders             -> order_id
order_items        -> order_id + order_item_id
products           -> product_id
product_categories -> product_category_name
sellers            -> seller_id
customer version   -> customer_unique_id + valid_from
```

Exact duplicate rows in the delta therefore do not create duplicate Core transactions.

---

## Mart layer — Star Schema

The reporting layer contains:

```text
mart.fact_sales
mart.dim_customer
mart.dim_product
mart.dim_seller
mart.dim_date
mart.dim_security
```

`mart.dim_seller` intentionally contains only `seller_id` in the current implementation because the Stage 2 pipeline carries only the seller identifier into the warehouse. The dimension is kept as a separate star-schema entity and can be enriched in a future extension.

`mart.dim_security` is an **independent access-control mapping table**, not a transactional star-schema dimension linked by a foreign key. It stores a user identifier, access role and permitted state; Power BI's RLS expression uses this mapping to filter `mart.dim_customer`, with the customer-to-fact relationship propagating the security filter. The warehouse security table contains five configured users.

### Fact table

`mart.fact_sales` grain:

```text
one row per order_id + order_item_id
```

The fact contains:

- `customer_sk`,
- `product_id`,
- `seller_id`,
- five date keys,
- order status,
- `price`,
- `freight_value`,
- `total_value`,
- `delivery_days`,
- `delay_days`,
- `delayed_flag`.

Financial definition in the Mart:

```text
total_value = price + freight_value
```

Operational delivery fields are calculated in SQL:

```text
delivery_days = actual customer delivery date - purchase date

delay_days = actual customer delivery date - estimated delivery date

delayed_flag = 1 when actual delivery date > estimated delivery date
               0 when the order is on time
               NULL when the comparison cannot be evaluated
```

No synthetic margin is stored in the Mart because the original Olist source does not contain an actual product-cost field.

### Temporal customer lookup

The fact loader resolves the correct SCD2 customer version with:

```text
customer_unique_id
AND order_purchase_timestamp >= valid_from
AND order_purchase_timestamp < valid_to
```

The load uses a temporal `LEFT JOIN` and then explicitly raises an exception if any fact row has no valid `customer_sk`. This prevents silent row loss caused by an `INNER JOIN` and makes temporal data-quality issues visible.

### Customer dimension

`mart.dim_customer` preserves the SCD2 fields and adds:

```text
customer_region
geolocation_lat
geolocation_lng
recency
frequency
monetary
r_score
f_score
m_score
segment
current_rfm_segment
```

The **`segment` and core RFM scores** remain populated on the current SCD2 version for behavioral reporting. The new SQL-derived **`current_rfm_segment`** is intentionally available on **all customer SCD2 versions** to support report filtering and historical order joins without an expensive Power BI calculated column. It represents the customer's *current* RFM classification, **not** the segment at each historical purchase date.

Customers not eligible for RFM retain `NULL` segment attributes. The final segmentation covers **94,983 of 95,420** unique source customers. The other **437** are excluded by purchase-status eligibility (431 canceled-only and 6 unavailable-only), not by delivery completion or product weight. Source-to-Mart `current_rfm_segment` comparison yielded **zero mismatches** across all customer versions.

The Mart also carries customer geolocation (`geolocation_lat`, `geolocation_lng`) from Core for use in Power BI map visuals.

Brazilian states are grouped into:

```text
North
Northeast
Central-West
Southeast
South
```

### Date dimension

`mart.dim_date` contains one row per calendar date and is enriched with:

```text
date_id
full_date
year
quarter
month
month_name
year_month
day
day_of_week
```

The SQL generates the calendar from `2016-01-01` through `2025-12-31`.

### Mart idempotency

Dimension and fact loads use `ON CONFLICT` logic so `data_to_mart.sql` can be rerun after the initial or delta Core load.

For existing fact rows, only mutable reporting attributes are updated. The historical `customer_sk` is not repointed during the fact upsert.

---

# SQL Files

The following scripts implement the warehouse pipeline:

```text
stage_create.sql
data_to_stage.sql
core_create.sql
data_to_core.sql
mart_create.sql
data_to_mart.sql
data_to_security.sql
reset_stage.sql
delta_load.sql
checks.sql
```

Responsibilities:

- `stage_create.sql` — creates Stage, Core and Mart schemas plus Stage tables.
- `data_to_stage.sql` — truncates `stage.raw_orders` and `stage.rfm_temp` **and executes the two initial CSV `COPY` commands** (the files must already be accessible to PostgreSQL).
- `core_create.sql` — creates the normalized Core model, constraints and indexes.
- `data_to_core.sql` — performs the initial Stage-to-Core load and builds initial SCD2 history.
- `mart_create.sql` — creates the reporting Star Schema, including the independent `mart.dim_security` table.
- `data_to_mart.sql` — loads / upserts dimensions and fact data, resolves temporal customer keys, carries geolocation and populates SQL-derived `current_rfm_segment`.
- `data_to_security.sql` — populates the five Power BI RLS user mappings after the Mart tables are created; run it only once per fresh warehouse rebuild unless the script is made idempotent.
- `reset_stage.sql` — truncates only `stage.raw_orders` **and imports `/delta_load.csv` using `COPY`**; `stage.rfm_temp` is retained. Do not run another manual delta `COPY` after this script.
- `delta_load.sql` — performs the incremental Core load, including new records, SCD1, SCD2 and duplicate-safe processing.
- `checks.sql` — validates row counts, duplicates, orphan keys, SCD behavior, RFM coverage, revenue reconciliation, geolocation coverage/consistency and security-table contents.

CSV files are loaded into Stage using PostgreSQL `COPY`, with paths appropriate for the database server environment.

## Initial load order

For a fresh database, copy the generated initial and RFM CSVs to the PostgreSQL server/container first (see [Docker](#docker)). Then execute the SQL scripts **in the following order**:

```text
1. stage_create.sql
2. data_to_stage.sql         -- truncates Stage tables and COPY-loads both CSVs
3. core_create.sql
4. data_to_core.sql
5. mart_create.sql
6. data_to_mart.sql
7. data_to_security.sql    -- populate the warehouse RLS mapping once
```

The supplied `data_to_stage.sql` already contains:

```sql
TRUNCATE TABLE stage.raw_orders;
TRUNCATE TABLE stage.rfm_temp;

COPY stage.raw_orders
FROM '/initial_load.csv'
DELIMITER ','
CSV HEADER;

COPY stage.rfm_temp
FROM '/olist_rfm_segmentation.csv'
DELIMITER ','
CSV HEADER;
```

**Do not execute these `COPY` statements again manually after running `data_to_stage.sql`.** The shown file paths are the paths used by the supplied SQL script; update them if your PostgreSQL container/server uses different locations. Running this initial-load script again truncates and reloads both Stage tables, so it is **not** the procedure for the delta load.

## Delta load order

After the initial Mart load, verify that `/delta_load.csv` is available inside the PostgreSQL container, then run:

```text
1. reset_stage.sql        -- TRUNCATE stage.raw_orders + COPY /delta_load.csv
2. delta_load.sql         -- incrementally update the Core layer
3. data_to_mart.sql       -- refresh Mart dimensions and facts
4. checks.sql             -- run quality and reconciliation checks
```

**Important:** in `reset_stage.sql`, the delta `COPY` is **already included**, immediately after the Stage reset. Do **not** load `delta_load.csv` manually a second time. The script preserves `stage.rfm_temp` for RFM enrichment. PostgreSQL `COPY` reads from the database-server filesystem; adjust `/delta_load.csv` in the script only if your container path differs.

The incremental load uses natural keys, constraints and upsert logic to avoid duplicate transactional rows and customer versions.

---

# Docker

PostgreSQL runs inside Docker.

For the Docker setup used in this project, generated CSV files can be copied to the PostgreSQL container before running the corresponding `COPY` commands.

Check the PostgreSQL container name:

```bash
docker ps
```

Example:

```bash
docker cp initial_load.csv <postgres_container>:/initial_load.csv
docker cp delta_load.csv <postgres_container>:/delta_load.csv
docker cp olist_rfm_segmentation.csv <postgres_container>:/olist_rfm_segmentation.csv
```

These are the server-side paths referenced by the supplied `data_to_stage.sql` and the delta `COPY` example. Change the SQL file paths if you use a different container mount or server directory.

PostgreSQL `COPY` reads files from the database-server filesystem, so the path used in each `COPY` command must point to a file accessible by the PostgreSQL server. The account running PostgreSQL must also have permission to read the files.

---

# Stage 3 — BI Development

Stage 3 delivers the Power BI semantic model, strategic and operational dashboards, documented BI requirements, wireframes, data storytelling and SQL-to-Power-BI validation evidence.

Main deliverables:

```text
stage3.ipynb
Power BI report (.pbix)
```

Supporting Stage 3 evidence:

```text
Dashboard1.png          # Director — initial KPI Overview wireframe
Dashboard2.png          # Director — initial Map / Drill-down wireframe
Dashboard3.png          # Director — initial RFM Segmentation wireframe
Dashboard4.png          # Operations Manager initial wireframe
RevenueSQL.png          # Historical Total Revenue validation evidence
TotalOrdersSQL.png      # Historical Total Orders validation evidence
DelayedOrdersSQL.png    # Total Delayed Orders validation evidence
```

`stage3.ipynb` contains requirement gathering, the Business Requirements Document (BRD), wireframing notes, business storytelling and SQL validation. The final interactive deliverable is a Power BI report containing four main dashboard pages, supporting tooltip pages and two order-detail drill-through views.

## Requirement Gathering

The notebook defines five requirement-gathering principles:

1. Focus on the business problem rather than starting from chart selection.
2. Define the operational expectation and the action that should follow from the data.
3. Prototype the solution before building the final report.
4. Define the relevant timeframe and reporting frequency.
5. Prioritize a small set of important KPIs instead of overcrowding one page.

Eight stakeholder questions are split between:

- the **Executive Director**, focused on strategic goals, KPIs and decision-making,
- the **Operations Manager**, focused on daily monitoring, operational pain points and corrective actions.

The notebook also explains why placing all metrics on one screen reduces usability and distinguishes a simple metric from an actionable insight.

---

## Business Requirements Document

The BI solution provides strategic and operational reporting experiences. The BRD in `stage3.ipynb` covers the four-page report, SQL-based RFM enrichment, dynamic RLS, measures, connectivity parameters, date relationships, navigation and remaining delivery limitations.

### Executive Director

The strategic dashboard is designed to monitor:

- overall sales performance,
- revenue trends and month-over-month performance,
- geographical performance,
- product-category performance,
- customer value and RFM segmentation.

### Operations Manager

The operational dashboard is designed to monitor:

- delayed orders,
- delivery bottlenecks,
- delivery-time distribution,
- delay severity,
- states requiring operational intervention.

### Key metrics and definitions

The principal Stage 3 measures use the PostgreSQL Mart Star Schema. The warehouse retains all statuses, including canceled transactions, for data completeness and auditability. The former report-level `order_status <> 'canceled'` filter has been removed. Core sales, customer and delivery measures now **explicitly exclude canceled orders in DAX** rather than relying on a global page/report filter; the KPI definitions are documented with their relevant filter contexts.

- **Total Revenue** — sum of product price plus freight for non-canceled orders, based on `mart.fact_sales[total_value]`.
- **Total Orders** — distinct non-canceled `order_id`; distinct counting avoids double-counting multi-item orders.
- **Average Order Value (AOV)** — Total Revenue / Total Orders.
- **Total Customers** — distinct purchasing customer identities represented by qualifying non-canceled fact rows within the applicable filter context.
- **Orders per Customer** — Total Orders / Total Customers.
- **Revenue per Customer** — Total Revenue / Total Customers.
- **MoM Growth %** — change between completed reporting months for the selected performance metric, avoiding comparison with incomplete September 2018. At the reference reporting end date of September 3, 2018, the displayed **−4.12%** compares **August 2018 vs July 2018**; a dynamic comparison-period label displays the applicable months.
- **Average Freight** — mean total freight per distinct qualifying order, not a simple average across order-item rows.
- **Total Delayed Orders** — distinct non-canceled orders with `delayed_flag = 1`.
- **Average Delivery Days** — actual delivery duration averaged at order level.
- **Average Delay Days** — positive days overdue, averaged over delayed orders.
- **SLA Eligible Orders** — distinct non-canceled orders with a nonblank delivery-timeliness classification.
- **Delayed Order Rate %** — Total Delayed Orders / SLA Eligible Orders.
- **% On-Time Delivery** — strictly on-time (`delayed_flag == 0`) non-canceled orders / SLA Eligible Orders. The DAX `==` comparison prevents `BLANK()` from being treated as zero.
- **Regional Revenue Share %** — selected geographical revenue relative to the eligible geographical total while retaining the user's effective RLS scope.

The report also uses contextual share and ranking measures built with `CALCULATE`, `KEEPFILTERS`, `REMOVEFILTERS`, `ALLSELECTED`, `TREATAS`, `DIVIDE` and distinct-order logic.

The implemented growth metric is **MoM Growth %**. Prior-year and YoY measures are not represented as implemented features.

### Delivery SLA definition

An order is:

- **On-Time** when actual delivery date <= estimated delivery date,
- **Delayed** when actual delivery date > estimated delivery date,
- **SLA-eligible** only when both actual and estimated delivery dates are available.

**SLA eligibility validation (current full warehouse history):** of **96,478** orders with `delivered` status, **96,470** are SLA-eligible. The remaining **8** lack an actual customer delivery date; none of the delivered-status orders lack an estimated delivery date. Across all non-canceled statuses, **1,735** orders lack an actual customer delivery date (including these eight). Incomplete delivery records are excluded from the on-time and delayed-rate denominators because their timeliness cannot be established. These are full-history figures, not figures for the narrower dashboard date slicer.

```text
delivery_days = actual delivery date - order purchase date

delay_days = actual delivery date - estimated delivery date
```

### RFM segmentation

RFM is calculated in Python at `customer_unique_id` level for eligible order statuses (`approved`, `invoiced`, `processing`, `shipped`, `delivered`) and imported into the warehouse for customer-dimension enrichment. It uses:

- **Recency** — days since the latest purchase,
- **Frequency** — number of unique orders,
- **Monetary** — total product value purchased.

Customer segments:

```text
Champion
At risk
Newbies
Regulars
Sleeping
```

The five RFM segments contain **94,983** customers. Another 437 customers are not eligible for segmentation (431 canceled-only and six unavailable-only) and retain `NULL` segment values, rather than an artificial `Not Segmented` label.

For the RFM comparison chart, **Customer Share %** is the segment's purchasing customers divided by customers across the five eligible segments; **Revenue Share %** is the corresponding segment revenue divided by revenue across the five segments. The denominators remove the segment context while retaining applicable date and business selections. RFM Monetary sums product price only; Stage 3 Revenue includes freight. Both measures refer to the SQL-derived **current**, not historical-as-of-order, RFM classification.

**RFM filter scope:** the page-level filter excludes blank `current_rfm_segment` values by design, so the page focuses on customers assigned to one of the five RFM segments. Its KPI cards and segment visuals use that consistent population. Across the full history, **94,983** customers have an eligible segment versus **94,989** non-canceled purchasing customers (a six-customer difference). A previously observed **~93.98K** RFM card used a narrower purchase-date range; extending it to include earlier purchases increased the displayed count to **~94.98K**. Compare page KPIs only under matching date and business filters.

---

## Functional Requirements

The report contains four primary business pages, each with four KPI cards and supporting analytical visuals.

### Strategic dashboard — Executive Director

1. **KPI Overview** — Total Revenue, Total Orders, AOV and MoM Change; dynamic monthly Revenue / Orders / AOV trend; dynamic **Top 10 Customer States** by the selected metric, **without Others**, with order-detail drill-through.
2. **Geographic Sales Analysis** — Total Revenue, Total Orders, Average Freight and % On-Time Delivery; a Brazil map using customer coordinates, Region → State → City analysis, Revenue / Orders / AOV selection, Top 5 product categories and a contextual state tooltip including **Top City by Orders**.
3. **Customer Segmentation RFM** — Total Customers, AOV, Orders per Customer and Revenue per Customer; **Customers by RFM Segment**, **Customer Share % vs Revenue Share %** and an RFM Customer Behavior table showing **Total Revenue** alongside behavioral metrics, with an **Overall** row.

### Operational dashboard — Operations Manager

4. **Delivery Performance** — Total Delayed Orders, % On-Time Delivery, Avg Delay Days and Avg Delivery Days; **Delivery Risk & Impact by State**, delivery-time distribution, monthly Order Volume vs Delay Rate, plus an Order Status slicer.

### Navigation, filters and investigation

The report has a consistent left-side page navigator, Order Date range selection, shared **Customer State**, **City**, **Product Category** and **RFM Segment** slicers, page-specific Reset bookmarks, dynamic titles and contextual Help/tooltip features. Filter selections are synchronized across the four main business pages. KPI Overview includes a Revenue / Orders / AOV selector, while Delivery Performance additionally includes an Order Status slicer.

The report provides working `Order_Details` and `Order_Details Operations` drill-through pages for transaction-level investigation, alongside tooltip pages. The KPI Overview state ranking supports drill-through to underlying orders; the Delivery Risk & Impact table supports drill-through for an individual state or the **Others** group. The operations detail page also displays orders when opened directly with no selected state. The order-detail field formerly labeled **Delay Days** now appears as **Days vs Estimate**: a positive number means delivery after the estimate, a negative number means early delivery, and zero means delivery on the estimated date. Direct transfer of a selected map point to the Delivery page remains a potential enhancement.

### Delivery Risk & Impact ranking rule

The Delivery table ranks the **Top 10 states by highest delay rate**, subject to a minimum of **100 SLA-eligible orders per state**. Remaining states form an **Others** aggregate; its rate is total delayed / total eligible orders in that group, **not** the simple average of state-level percentages. The table includes State, Delayed Orders, Delay Rate and SLA Eligible Orders. Rates above the overall delay rate are red, while those at or below it are navy. The separate monthly rate trend suppresses values with fewer than 100 eligible orders, without suppressing order-count bars.

## Non-Functional & Technical Requirements

### Dynamic Row-Level Security

The `Dynamic_Security` role reads its user-to-state mapping from the **physical PostgreSQL table `mart.dim_security`**, which has replaced the former hard-coded Power BI table. Power BI imports it as `mart dim_security` and evaluates the signed-in identity using `USERPRINCIPALNAME()`.

The security table is intentionally **disconnected** from the star-schema relationships. The RLS filter is applied on `mart dim_customer`, allowing the existing customer-to-sales relationship to propagate state restrictions. Manager users can be assigned one state or `ALL`; Director users with `ALL` access can view all states. Users absent from the mapping are denied access to protected customer/fact data. The revised role was saved and tested interactively in Power BI Desktop.

**Deployment note:** Power BI Service user identities and role membership must also be verified before external sharing. The five entries are development/test mappings rather than a production identity-management integration.

### Advanced DAX

The report uses reusable DAX measures, dynamic metric-selection titles, context-aware revenue shares (respecting RLS) and time-based reporting through the active order-date relationship with `mart.dim_date`. Unused prior-year, YTD, duplicate share and other legacy measures were removed after reviewing their report dependencies. The revised core measures use explicit canceled exclusions and preserve applicable business selections with context-aware DAX.

`Current RFM Segment` is **no longer calculated row by row in DAX**; the model uses the SQL-derived `current_rfm_segment`. On-time classification uses strict `delayed_flag == 0` to avoid counting blanks as on-time.

The warehouse date dimension provides the reporting calendar. **Auto date/time is disabled for the current Power BI file**, so the report relies on `mart.dim_date` rather than automatic hidden date tables.

### Data model and performance

Power BI uses the Mart Star Schema as the reporting semantic model. Connection details are configurable via Power Query parameters **`pServer`** and **`pDatabase`**, replacing a hard-coded `localhost` connection in the Mart queries.

Five order-related date keys are retained in `mart.fact_sales`. The order-date relationship is active; the **four alternate date relationships are currently inactive** and have not yet been activated through dedicated measures. They are documented as a pending use-or-remove cleanup item rather than presented as completed.

Target refresh frequency is daily; in the local project environment, SQL and Power BI refreshes can be executed manually.

The model uses a Star Schema and reusable DAX measures to support responsive report interactions. No measured page-load-time benchmark is claimed.

---

## Power BI Report

The final interactive report connects to the PostgreSQL Mart layer using Power Query parameters `pServer` and `pDatabase`. The four main pages are supported by tooltip and order-detail drill-through pages. The most recent review of report layout and measures was based on the November 13 reporting definition and corroborating dashboard screenshots; the separately supplied earlier PBIX should not be treated as a final refreshed export.

### KPI Overview

Strategic overview containing:

- **Total Revenue**, **Total Orders**, **Average Order Value** and **Month-over-Month Change (%)** KPI cards.
- Monthly Trend with a Revenue / Total Orders / AOV selector and readable `MMM yyyy` month labels.
- **Dynamic Top 10 Customer States** table with metric-dependent ranking, data bars, dynamic title and state-level drill-through to `Order_Details`.
- Shared business slicers and order-date filtering.

The previous **Top 10 + Others** state table was replaced: the KPI Overview ranking now shows **only the ten leading states** for the selected metric. The rank responds to relevant slicers while preserving the authorized geography under RLS.

The monthly trend uses a **visual-level start cutoff of February 1, 2017** to avoid emphasizing low-volume early 2016 months and a visual-level end cutoff of **August 31, 2018** so that incomplete September 2018 does not distort month-to-month comparisons. These chart-level cutoffs do **not** redefine global KPI totals. A dynamic label accompanying the MoM KPI identifies the compared months; in the reference context, **−4.12% means August 2018 vs July 2018**, excluding the incomplete September 2018.

### Geographic Sales Analysis

Geographical and categorical analysis containing:

- Four KPI cards: **Total Revenue**, **Total Orders**, **Average Freight** and **% On-Time Delivery**.
- **Selected Metric by Location** with Revenue / Orders / AOV selection and drill-down through Country / Region / State / City (the report's location hierarchy can be used from Region onward).
- Geographic map using customer latitude/longitude propagated from PostgreSQL with state/city geographic context.
- **Top 5 Categories by Revenue**, excluding the earlier misleading subtotal row.
- A tooltip page showing Selected State, Selected City, Revenue, Orders, Customers, AOV, Regional Revenue Share, Delayed Orders, **Delayed Order Rate %**, and **Top City by Orders (with order count)** for the hovered state. A verified example for CE identifies **Fortaleza (636 orders)**.

The location chart retains its working hierarchy rather than introducing a synthetic geographic Others category. The existing synchronized Customer State slicer supports cross-page context; direct map-point-to-Delivery transfer remains a potential enhancement, **not** a verified feature.

The map requires validation in Power BI Service, and four customer coordinates outside approximate Brazil bounds still require upstream correction. On-time KPI colors use illustrative performance thresholds (green ≥95%, amber 90–<95%, red <90%), not published Olist performance targets.

### Customer Segmentation RFM

Customer segmentation analysis containing:

- Four KPI cards: **Total Customers**, **AOV**, **Orders / Customer** and **Revenue per Customer**.
- **Customers by RFM Segment** horizontal bar chart, with the small Champion group visible through its data label.
- **Customer Share % vs Revenue Share %** clustered-column comparison, replacing the older metric-switching revenue/RPC chart.
- **RFM Customer Behavior** table showing **Avg Recency (Days)**, **Orders / Customer**, **AOV**, **Avg RFM Monetary** and **Total Revenue**, with an **Overall** summary row. The indicators retain their appropriate average/ratio logic, while Total Revenue is additive across segments.

The current-share and revenue-share measures represent contributions to the **five-segment purchasing population** under the applicable date/geography/product filters. In the reference dashboard context, Regulars represented approximately 50.73% of customers and 49.94% of revenue; Champions 0.15% of customers and 0.50% of revenue; At risk 1.11% of customers and 2.32% of revenue. Revenue is price plus freight, while RFM Monetary is product price only.

The RFM page intentionally applies a **page-level filter** to omit `NULL` `current_rfm_segment` values, so its KPI cards and segment visuals consistently describe the eligible RFM population. The full segmentation contains **94,983** customers; the difference to the original **95,420**-customer source is explained by **437** ineligible customer identities (431 canceled-only and six unavailable-only). The broader **non-canceled** purchasing population has **94,989** customers (six without an RFM segment). The former **~93.98K** RFM value also reflected a narrower selected purchase-date range. The **Champion** segment contains only **143** customers (about **0.15%** of the segmented population), explaining its very small chart bar.

### Delivery Performance

Operational monitoring containing:

- Four KPI cards: **Total Delayed Orders**, **% On-Time Delivery**, **Avg Delay Days** and **Avg Delivery Days**.
- **Delivery Risk & Impact by State**, replacing the old Delayed Order Rate by State bar chart.
- **Delivery Time Distribution** with duration groups and data labels.
- **Order Volume vs Delay Rate** with order-count bars and monthly delay-rate line.
- An **Order Status** slicer in addition to the shared report filters.

The Delivery Risk & Impact table ranks Top 10 states by delay rate after applying the **100 SLA-eligible orders** qualification rule, and places the remaining states into a weighted **Others** aggregate. Its columns are State, Delayed Orders, Delay Rate and SLA Eligible Orders; conditional colors compare a state to the overall rate (red above overall; navy at/below).

At the reference dashboard dates, the results were **6,509 delayed orders**, **95,453 SLA-eligible orders**, **93.18% on-time delivery**, **10.58 average delay days** and **12.47 average delivery days**. The rebuilt table's delayed count reconciled to 6,509 at the default reference filters, and the operational state/Other drill-through was tested interactively.

The monthly delay-rate line suppresses percentages based on fewer than 100 eligible orders, including misleading very-small-sample peaks; order-volume bars remain visible. September 2018 is excluded at the trend visual level because the dataset contains only the first three days of that month. The **Operations — Methodology** Help explains SLA eligibility: non-canceled orders require both actual and estimated delivery dates; records without either cannot be classified for SLA rates.

## Wireframes

Low-fidelity wireframes were created before the final dashboard implementation for all four main business pages:

```text
Dashboard1.png — Director dashboard #1: KPI Overview
Dashboard2.png — Director dashboard #2: Map and Drill Down
Dashboard3.png — Director dashboard #3: RFM Segmentation
Dashboard4.png — Operations Manager dashboard
```

The wireframes define the **initial** placement of KPI cards, filters, navigation and main/supporting visuals. They intentionally use simple boxes and placeholder labels rather than final styling. The original **Map / Drill-down** concept became **Geographic Sales Analysis**, and **Operations Dashboard** became **Delivery Performance**; historical wireframe labels do not indicate additional final report pages.

The updated implementation adds a dynamic **Top 10 without Others** on KPI Overview, a **Customer Share vs Revenue Share** comparison on RFM, **Top City by Orders** in the map tooltip and **Delivery Risk & Impact** on the operational page. Updated wireframes should preserve the actual filter labels (**Customer State, City, Product Category, RFM Segment**) and separate four KPI cards; they should never depict KPI cards as slicer controls. The original wireframes remain valid as initial design evidence, but stylistic concept illustrations are not proof of the final layout.

---

## Data Storytelling

Two complementary business patterns are highlighted by the final report, with explicit use of the underlying definitions and filter context.

### Pattern 1 — Customer value is not proportional to segment size

The revised RFM page compares the share of purchasing customers with the share of revenue generated by each eligible segment in the reference reporting period:

| Segment | Customer Share | Revenue Share |
|---|---:|---:|
| Regulars | 50.73% | 49.94% |
| Newbies | 24.43% | 24.33% |
| Sleeping | 23.58% | 22.91% |
| At risk | 1.11% | 2.32% |
| Champion | 0.15% | 0.50% |

Regulars account for the largest absolute customer and revenue contributions. Champions represent a very small group but a proportionally higher revenue share; At-risk customers likewise contribute more revenue than their population share would suggest.

**Hypothesis:** customer count alone understates the commercial contribution of certain smaller, higher-value customer groups.

**Business action:** prioritize retention, customer experience and reactivation campaigns for valuable At-risk and Champion customers. Monitor both contribution percentages rather than relying on absolute customer counts.

### Pattern 2 — Delivery risk and delayed-order impact are distinct

The reference period contains **6,509 delayed orders among 95,453 SLA-eligible orders**, corresponding to approximately **6.82% delayed** and **93.18% on-time**. The delivery-duration histogram has its largest group in the **6–10 day** bucket. The updated state table compares delay rates, eligible order volumes and absolute delayed counts.

**Hypothesis:** some states have high relative delay risk but relatively few affected orders, while large-volume states can generate a substantial number of delays despite lower percentages. Seasonal or volume peaks can also contribute to logistics pressure, but the current charts do not establish causation.

**Business action:** prioritize states using both rates and affected order counts, monitor Order Volume vs Delay Rate, and evaluate logistics capacity before expected demand peaks. The monthly chart suppresses unreliable rate estimates based on fewer than 100 eligible orders.

## SQL vs Power BI Validation

Three principal aggregated dashboard metrics were independently checked against the PostgreSQL Mart layer using consistent date and state filters and non-canceled-order definitions. Screenshots and query evidence are retained among the Stage 3 materials. The validation distinguishes exact values from the rounded display shown on KPI cards.

### 1. Total Revenue

**Dashboard-period SQL:** **R$ 15,546,929.74** for February 1, 2017 – September 3, 2018. Power BI agreed in the same reporting context.

**Filtered SQL:** **R$ 436,641.43** for State SP during March 1–31, 2018. The KPI card displayed the corresponding rounded value, **R$ 436.64K**; a cent-level Power BI display was not captured in the comparison.

Previous full-history reference screenshot: **R$ 15,737,887.53**. Current full-history SQL: **R$ 15,737,667.52**. These are different snapshots and have an unresolved difference; see Historical Reconciliation below.

Historical validation evidence:

```text
RevenueSQL.png
```

### 2. Total Orders

**Dashboard-period SQL and Power BI:** **97,119** distinct orders.

**Filtered State SP / March 2018:** **3,007** distinct orders in both SQL and Power BI.

Earlier full-history reference: **98,208** orders; current full-history SQL: **98,205** orders. The three-order difference remains open.

Historical validation evidence:

```text
TotalOrdersSQL.png
```

### 3. Total Delayed Orders

**Dashboard-period SQL and Power BI:** **6,509** delayed orders.

**Filtered State SP / March 2018:** **280** delayed orders in both SQL and Power BI.

The full-history count was **6,534** in both earlier and current comparisons.

Historical validation evidence:

```text
DelayedOrdersSQL.png
```

### Reference dashboard validation table

| Metric | 2017-02-01 to 2018-09-03 | State SP, 2018-03-01 to 2018-03-31 |
|---|---:|---:|
| Total Revenue (SQL) | R$ 15,546,929.74 | R$ 436,641.43 |
| Total Orders | 97,119 | 3,007 |
| Total Delayed Orders | 6,509 | 280 |

For the dashboard period, SQL and Power BI agreed on all three KPI values. For the SP filter test, Orders and Delayed Orders matched exactly, and Revenue matched to the displayed KPI precision. The full-precision number should be displayed for an exact cent-level Power BI screenshot.

### Historical reconciliation — unresolved

| Metric | Earlier reference | Current SQL | Change |
|---|---:|---:|---:|
| Revenue | R$ 15,737,887.53 | R$ 15,737,667.52 | −R$ 220.01 |
| Orders | 98,208 | 98,205 | −3 |
| Delayed Orders | 6,534 | 6,534 | 0 |

The current fact-only SQL totals match the current totals using the tested dimension joins; those joins therefore do **not** explain the historical discrepancy. The cause of the difference between the older and current states remains unverified. The broader historical figures must not be mixed with the narrower dashboard reporting-period figures.

### Additional warehouse and RFM validation

The refreshed warehouse and RFM enrichment were checked after the simulated delta load:

| Validation | Verified result |
|---|---:|
| `mart.fact_sales` rows (order-item grain) | 112,650 |
| `core.orders` rows | 98,666 |
| `stage.rfm_temp` customers | 94,983 |
| Customers with no eligible RFM segment | 437 |
| RFM source-to-current-Mart segment mismatches | **0** |
| Fact / dimension orphan-key checks | **0** |
| Duplicate order-item / current-customer-version checks | **0** |
| Current customers with both geolocation coordinates | **95,156 / 95,420 (99.72%)** |
| Current customers without coordinates | **264** |
| Core-to-Mart coordinate mismatches | **0** |
| Invalid global lat/lon or half-null coordinate pairs | **0** |
| Current customers outside approximate Brazil bounds | **4** |
| Warehouse security mappings | **5** |

The SQL-derived `current_rfm_segment` was checked against the Python-produced RFM output across all customer SCD2 versions by `customer_unique_id` and returned zero mismatches. The source customer population was 95,420, and the five eligible segments summed to 94,983.

A separate full-status Mart reconciliation verified **R$ 15,843,553.24** in `price + freight_value` before applying the non-canceled status rule. This is a distinct population from the dashboard Revenue measure and from the unresolved historical comparison.

---

# Suggested Project Structure

```text
Project/
|
|-- Stage 1/
|   |-- stage1.ipynb
|   |-- olist_cleaned_dataset_ground_truth.csv
|   |-- olist_rfm_segmentation.csv
|   `-- Brazilian_Ecomerce_report_final.html
|
|-- Stage 2/
|   |-- stage2.ipynb
|   |
|   |-- sql/
|   |   |-- stage_create.sql
|   |   |-- data_to_stage.sql
|   |   |-- core_create.sql
|   |   |-- data_to_core.sql
|   |   |-- mart_create.sql
|   |   |-- data_to_mart.sql
|   |   |-- data_to_security.sql
|   |   |-- reset_stage.sql
|   |   |-- delta_load.sql
|   |   `-- checks.sql
|   |
|   |-- diagrams/
|   |   |-- flowchart_olist.png
|   |   |-- CORE_ERD_DIAG.png
|   |   `-- MART_ERD_DIAG.png
|   |
|   |-- initial_load.csv
|   `-- delta_load.csv
|
|-- Stage 3/
|   |-- stage3.ipynb
|   |-- Innowise_Project_Stage3.pbix
|   |-- Dashboard1.png
|   |-- Dashboard2.png
|   |-- Dashboard3.png
|   |-- Dashboard4.png
|   |-- RevenueSQL.png
|   |-- TotalOrdersSQL.png
|   `-- DelayedOrdersSQL.png
|
`-- README.md
```

---

# How to Run

## 1. Download the Olist source data

Download the Brazilian E-Commerce Public Dataset by Olist and place the required CSV files next to the Stage 1 / Stage 2 notebooks.

## 2. Run Stage 1

Execute:

```text
stage1.ipynb
```

This produces the cleaned reference dataset, Sweetviz report and RFM segmentation.

## 3. Run Stage 2 notebook

Execute the Stage 2 notebook:

```text
stage2.ipynb
```

The notebook merges the transactional sources with the Olist geolocation data and creates:

```text
initial_load.csv
delta_load.csv
```

## 4. Copy CSV files to PostgreSQL Docker container

```bash
docker cp initial_load.csv <postgres_container>:/initial_load.csv
docker cp delta_load.csv <postgres_container>:/delta_load.csv
docker cp olist_rfm_segmentation.csv <postgres_container>:/olist_rfm_segmentation.csv
```

## 5. Build the initial warehouse

After the two initial CSVs have been copied into the PostgreSQL container, execute these scripts in order:

```text
stage_create.sql
    ↓
data_to_stage.sql  (TRUNCATE + COPY of initial_load.csv and olist_rfm_segmentation.csv)
    ↓
core_create.sql
    ↓
data_to_core.sql
    ↓
mart_create.sql
    ↓
data_to_mart.sql
    ↓
data_to_security.sql  (populate the five RLS mappings once)
```

`data_to_stage.sql` already executes the CSV imports. Its `COPY` file paths assume `/initial_load.csv` and `/olist_rfm_segmentation.csv` exist on the database server/container. **Do not import the same files twice.**

## 6. Process the simulated incremental load

Run the following scripts in order, **without manually importing the delta CSV between steps**:

```text
reset_stage.sql        (includes COPY of /delta_load.csv)
delta_load.sql
data_to_mart.sql
checks.sql
```

The `reset_stage.sql` script both resets `stage.raw_orders` and loads the delta file. Running another `COPY` would duplicate the Stage batch. `checks.sql` validates row counts, duplicate and orphan-key checks, SCD behavior, RFM reconciliation, revenue totals, geolocation and security mappings.

## 7. Review Stage 3 requirements

Open:

```text
stage3.ipynb
```

This notebook contains the requirement-gathering principles, stakeholder interview questions, BRD, wireframing notes, data storytelling and SQL-vs-Power-BI validation documentation used to define and verify the Power BI solution.

## 8. Open Power BI

Open the final interactive Power BI report in Power BI Desktop:

```text
Innowise_Project_Stage3.pbix
```

Ensure that PostgreSQL is running and confirm the configured Power Query parameters `pServer` (for example, `localhost`) and `pDatabase` (for example, `olist_dwh`). Refresh the Mart data if necessary, verify the `Dynamic_Security` role and its permitted state access, and confirm that the four business pages and supporting order-detail drill-through pages work as documented. The original source dates extend through **2018-09-03**; the monthly trend charts omit the incomplete last month at visual level.

---

# Outstanding Items

The following data-quality, deployment and optional model enhancements remain open:

1. **Geolocation quality:** Four current customers across three ZIP prefixes (`46560` / BA, `68275` / PA and `83252` / PR) have coordinates outside approximate Brazil bounds despite valid local addresses. Correct or reject these outliers upstream before ZIP/state aggregation, refresh the warehouse and verify the map. The global coordinate range check did not detect these geographically misplaced but numerically valid coordinates.
2. **Power BI Service validation:** Validate the Brazil map rendering and Dynamic RLS role membership and identity mapping with appropriate non-admin users before report distribution.
3. **Inactive date relationships:** Four additional order milestone relationships (approval, carrier handoff, customer delivery and estimated delivery) remain inactive and are not currently used through dedicated `USERELATIONSHIP()` measures. Retain them for milestone reporting or remove them if outside the final scope.
4. **Geographic navigation:** The location drill-down and synchronized state slicers work. Direct transfer of a selected map point into Delivery Performance could be added as a dedicated cross-page interaction in a future iteration.

---

# Technologies

```text
Python
pandas
NumPy
Matplotlib
Seaborn
Plotly
Sweetviz
PostgreSQL
Docker
SQL
Power BI
DAX
```

---
