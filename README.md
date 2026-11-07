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

Main file (uploaded version: `stage1(9).ipynb`; rename to `stage1.ipynb` for the final repository):

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

Main file (uploaded version: `stage2(3).ipynb`; rename to `stage2.ipynb` for the final repository):

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

The repository-friendly names are shown below. The current uploaded versions have revision suffixes, for example `stage_create(6).sql`, `core_create(6).sql`, `mart_create(6).sql`, `data_to_stage(4).sql`, `data_to_core(6).sql`, `data_to_mart(4).sql`, `reset_stage(4).sql`, `delta_load(4).sql` and `checks(2).sql`. Rename the supplied revision files to the canonical names if preparing a clean repository.

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

**Important:** in the submitted `reset_stage(4).sql`, the delta `COPY` is **already included**, immediately after the Stage reset. Do **not** load `delta_load.csv` manually a second time. The script preserves `stage.rfm_temp` for RFM enrichment. PostgreSQL `COPY` reads from the database-server filesystem; adjust `/delta_load.csv` in the script only if your container path differs.

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

Stage 3 delivers the Power BI semantic model, strategic and operational dashboards, documented BI requirements, low-fidelity wireframes, data storytelling and SQL-to-Power-BI validation evidence.

Main files (uploaded versions):

```text
stage3(3).ipynb
Innowise_Project_Stage3_final_ver2910_final.pbit
```

The editable `.pbix` is produced by opening the template and saving the refreshed report in Power BI Desktop; the uploaded `.pbit` itself does not contain imported model data.

Supporting Stage 3 evidence:

```text
Dashboard1.png          # Director — KPI Overview wireframe
Dashboard2.png          # Director — Map / Drill-down wireframe
Dashboard3.png          # Director — RFM Segmentation wireframe
Dashboard4.png          # Operations Manager wireframe
RevenueSQL.png          # Total Revenue validation
TotalOrdersSQL.png      # Total Orders validation
DelayedOrdersSQL.png    # Total Delayed Orders validation
```

`stage3.ipynb` contains requirement gathering, the updated Business Requirements Document (BRD), initial wireframing notes, data storytelling and validation documentation. The revised notebook was supplied as `stage3(3).ipynb`. The `.pbit` contains the model and report definition; a refreshed `.pbix` contains the locally imported data.

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

The BI solution provides two complementary reporting experiences. The revised BRD in `stage3(3).ipynb` covers the current four-page report, its SQL-based RFM and RLS implementation, dynamic metrics, connectivity parameters, date model and the remaining delivery limitations.

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

The principal Stage 3 measures use the Mart model. A report-level order-status filter excludes `canceled` orders, and the core Revenue and Orders measures additionally enforce that exclusion. Other measures follow their own filter context and eligibility rules. The warehouse retains canceled transactions for auditability.

- **Total Revenue** — product price plus freight for non-canceled orders, calculated from `mart.fact_sales[total_value]`.

- **Total Orders** — distinct non-canceled `order_id`, returning zero instead of blank when there are no qualifying orders.

- **Average Order Value (AOV)** — Total Revenue / Total Orders.
- **Total Customers** — distinct purchasing customers represented by the fact rows in the active report, page and slicer filter context.
- **Orders per Customer** — Total Orders / Total Customers.
- **Revenue per Customer** — Total Revenue / Total Customers.
- **MoM Growth %** — compares the latest completed reporting month with the preceding month for the selected metric; avoids comparing an incomplete September 2018 with August 2018.
- **Average Freight** — mean total freight per distinct order in the selected context, rather than a simple order-item-row average.
- **Total Delayed Orders** — distinct non-canceled orders where `delayed_flag = 1`.
- **Average Delivery Days** — duration measured per order, not per order item.
- **Average Delay Days** — mean days beyond the expected delivery date for delayed orders.
- **SLA Eligible Orders** — orders for which actual and estimated delivery dates are both available.
- **Delayed Order Rate %** — delayed orders / SLA Eligible Orders.
- **% On-Time Delivery** — on-time orders / SLA Eligible Orders.
- **Regional Revenue Share %** — selected geographical revenue relative to total revenue within the user's effective RLS scope.

The revised Stage 3 BRD documents the implemented **MoM Growth %** analysis. Previous-year and YoY measures were removed from the final semantic model, so they are not presented as implemented features.

### Delivery SLA definition

An order is:

- **On-Time** when actual delivery date <= estimated delivery date,
- **Delayed** when actual delivery date > estimated delivery date,
- **SLA-eligible** only when both actual and estimated delivery dates are available.

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

The five RFM segments contain **94,983** customers. Customers without an eligible RFM purchase remain `NULL` rather than being assigned an artificial `Not Segmented` label. Segmented visualizations exclude null segments at the **visual level**; global KPI cards are not filtered by the same exclusion.

---

## Functional Requirements

The report contains four main business pages.

### Strategic dashboard — Executive Director

1. **KPI Overview**
2. **Geographic Sales Analysis**
3. **Customer Segmentation RFM**

### Operational dashboard — Operations Manager

4. **Delivery Performance**

The report also contains supporting tooltip pages, an `Order_Details` drill-through page and methodology / FAQ content. Supporting pages are not counted as main dashboard pages.

The experience supports navigation buttons and shared report filters, with business-friendly slicer labels and dynamic titles. The KPI Overview's Select Metric control switches Revenue, Orders and AOV. Customer State, City, Product Category and RFM Segment slicers are arranged above the KPI cards. Contextual information icons or existing report tooltips explain non-obvious KPI and chart definitions.

Geographic Sales Analysis supports **Region -> State -> City** drill-down on the location bar chart and a dynamic title based on Revenue, Orders or AOV. The map uses customer latitude/longitude in addition to location fields.

Delivery Performance shows delivery-time distribution, geographical delivery issues, a combined order-volume/delay-rate trend and an **Order Status** slicer. Each main report page retains four KPI cards.

---

## Non-Functional & Technical Requirements

### Dynamic Row-Level Security

The `Dynamic_Security` role reads its user-to-state mapping from the **physical PostgreSQL table `mart.dim_security`**, which has replaced the former hard-coded Power BI table. Power BI imports it as `mart dim_security` and evaluates the signed-in identity using `USERPRINCIPALNAME()`.

The security table is intentionally **disconnected** from the star-schema relationships. The RLS filter is applied on `mart dim_customer`, allowing the existing customer-to-sales relationship to propagate state restrictions. Manager users can be assigned one state or `ALL`; Director users with `ALL` access can view all states. Users absent from the mapping are denied access to protected customer/fact data. The revised role was saved and tested interactively in Power BI Desktop.

**Deployment note:** Power BI Service user identities and role membership must also be verified before external sharing. The five entries are development/test mappings rather than a production identity-management integration.

### Advanced DAX

The report uses reusable DAX measures, dynamic metric-selection titles, context-aware revenue shares (respecting RLS) and time-based reporting through the active order-date relationship with `mart.dim_date`. Unused prior-year, YTD, duplicate share and other legacy measures were removed after reviewing their report dependencies.

`Current RFM Segment` is **no longer calculated row by row in DAX**; the model uses the `current_rfm_segment` field imported from SQL.

The warehouse date dimension provides the reporting calendar. **Auto date/time is disabled for the current Power BI file**, so the report relies on `mart.dim_date` rather than automatic hidden date tables.

### Data model and performance

Power BI uses the Mart Star Schema as the reporting semantic model. Connection details are configurable via Power Query parameters **`pServer`** and **`pDatabase`**, replacing a hard-coded `localhost` connection in the Mart queries.

Five order-related date keys are retained in `mart.fact_sales`. The order-date relationship is active; the **four alternate date relationships are currently inactive** and have not yet been activated through dedicated measures. They are documented as a pending use-or-remove cleanup item rather than presented as completed.

Target refresh frequency is daily; in the local project environment, SQL and Power BI refreshes can be executed manually.

The model uses a Star Schema and reusable DAX measures to support responsive report interactions. No measured page-load-time benchmark is claimed.

---

## Power BI Report

Final report template reviewed for this README:

```text
Innowise_Project_Stage3_final_ver2910_final.pbit
```

Power BI connects to the reporting-ready Mart layer. Open and refresh the template to save a `.pbix` with locally imported data.

### KPI Overview

Strategic overview containing:

- Total Revenue, Total Orders and Average Order Value,
- **Month-over-Month Change (%)** based on completed months,
- Monthly Trend with a Revenue / Total Orders / AOV selector and readable `MMM yyyy` month labels,
- a **Top 10 customer states + Others** table with data bars, responsive values and a dynamic state-table title,
- shared business filters and date-range filtering.

The Monthly Trend uses a **visual-level start date of February 1, 2017** to avoid emphasizing the unusually low-volume early months of 2016. The partial **September 2018** (data only through September 3) is also excluded from monthly trend presentation with a visual-level end cutoff of August 31, 2018. Neither cutoff changes global KPI totals. The Top 10 table is a single visual; **Others is included but sorts by its value rather than remaining permanently last** to avoid an extra visible sorting column and horizontal scrolling.

### Geographic Sales Analysis

Geographical and categorical analysis containing:

- **Selected Metric by Location** with drill-down through **Region -> State -> City**; the submitted `.pbit` still also includes **Country as the first drill level**,
- dynamic visual title: **Revenue by Location / Orders by Location / AOV by Location**,
- geographic map using **average customer latitude/longitude** from the warehouse, plus state/city fields,
- **Top 5 Categories by Revenue** (misleading subtotal row removed),
- supporting state-level metric visualization.

The geography analysis focuses on Brazil and includes a fallback state view for locations where the map is unavailable. The current chart retains `Country` above `customer_region`; it can be removed from the axis later if the drill-down is intended to start immediately at Region. The location bar chart currently retains its working drill-down rather than adding an `Others` group; **Top 10 + Others remains pending on this visual**. Map display still needs validation in Power BI Service, and four customer coordinates outside the expected Brazil region need correction in the ETL. Operational context, including the on-time delivery KPI, uses an **illustrative** color convention (green >= 95%, amber >= 90% and < 95%, red < 90%); these thresholds are not an official published Olist SLA.

### Customer Segmentation RFM

Customer segmentation analysis containing:

- **Total Customers**, **AOV**, **Orders / Customer**, **Revenue per Customer** KPI cards,
- **RFM Segment Value** metric-switching chart (Total Revenue or Revenue per Customer), with a dynamic title,
- **Customers by RFM Segment** horizontal bar chart with consistent segment colors and data labels, making the small Champion group (143 customers) visible,
- **RFM Customer Behavior** table with a title and Total row, showing **Avg Recency (Days)**, **Orders / Customer**, **AOV**, and **Avg RFM Monetary**. The extra Monetary measure is present in the submitted final `.pbit`; the table does not repeat Total Customers from the segment-count chart.

The submitted `.pbit` applies a **page-level filter** excluding `NULL` `current_rfm_segment` values on Customer Segmentation RFM. This affects the KPI cards on that page as well as its segment visuals. Under the unfiltered state/date selection, **94,983** customers have one of the five RFM segments. Across the wider non-canceled report scope, **94,989** customers have visible orders: the additional **6** have unavailable-only orders and therefore lack an eligible RFM segment. The **431** canceled-only customers are excluded by the report-level order-status filter. The full original source population is **95,420** unique customers.

### Delivery Performance

Operational delivery monitoring containing:

- four KPI cards: **Total Delayed Orders**, **% On-Time Delivery**, **Avg Delay Days** and **Avg Delivery Days**,
- **Delayed Order Rate by State**,
- **Delivery Time Distribution** with data labels,
- **Order Volume vs Delay Rate** (order counts and delayed-order-rate line),
- an **Order Status** slicer and business-oriented order-date/axis labels.

Numeric formats were refined, including two decimals for Avg Delay Days (for example 10.62), two decimals for Avg Delivery Days (for example 12.50) and a readable thousands separator for delayed order counts. The delayed-rate metric remains available in the report even though its redundant top-row KPI card was replaced by Avg Delivery Days.

The delayed-rate line uses a separate chart measure to suppress percentages based on fewer than **100 SLA-eligible orders** in a month. This avoids misleading values such as the original 100% rate for September 2016, which had only two eligible orders. Order-volume bars are not suppressed by this rule, and zero-order months can remain on the time axis.

The incomplete September 2018 is excluded from this monthly trend at the **visual level** (through August 31, 2018), while the original measures and report-wide KPIs remain unchanged. Tooltip icons clarify the operational definitions.

---

## Wireframes

Low-fidelity wireframes were created before the final dashboard implementation for all four main business pages:

```text
Dashboard1.png — Director dashboard #1: KPI Overview
Dashboard2.png — Director dashboard #2: Map and Drill Down
Dashboard3.png — Director dashboard #3: RFM Segmentation
Dashboard4.png — Operations Manager dashboard
```

The wireframes define the **initial** placement of KPI cards, filters, navigation and main/supporting visuals. They intentionally use simple boxes and placeholder labels rather than final styling. The original **Map / Drill-down** concept became **Geographic Sales Analysis**, and **Operations Dashboard** became **Delivery Performance**; historical wireframe labels do not indicate additional final report pages.

---

## Data Storytelling

Two business patterns were identified from the final report.

### Pattern 1 — Customer value is concentrated in the Regulars segment

The Regulars segment contains the largest number of customers and generates the highest total revenue. Champions represent only a very small part of the customer base but generate substantially higher revenue per customer.

**Hypothesis:** most customers make only a limited number of repeat purchases, while a small group of highly engaged customers generates significantly more value per customer.

**Business action:** focus retention and repeat-purchase campaigns on high-value Regulars and At-risk customers. Converting even a small share of these customers into Champions could increase customer lifetime value without relying only on new customer acquisition.

### Pattern 2 — Delivery delays show visible peaks during periods of higher activity

The delivery-time distribution has its largest group in the **6–10 day** bucket. In the reference report context, the delayed-order rate is approximately **6.77%**. Delayed-order-rate patterns show noticeable peaks during late 2017 and early 2018; the report suppresses monthly percentages for periods with fewer than 100 SLA-eligible orders to avoid drawing conclusions from a very small sample.

**Hypothesis:** periods with higher order activity may put additional pressure on fulfillment and logistics capacity, contributing to more delayed deliveries.

**Business action:** monitor delayed-order rate together with order volume and prepare additional logistics capacity before expected demand peaks. State-level monitoring can then identify locations requiring operational intervention.

---

## SQL vs Power BI Validation

Three aggregated dashboard metrics were independently validated against the Mart layer. Validation results and screenshots are included in the Stage 3 deliverables; query code remains in the project SQL files rather than in this README.

### 1. Total Revenue

Power BI result: approximately **R$ 15.74M**  
SQL result: **15,737,887.53**

Validation screenshot:

```text
RevenueSQL.png
```

### 2. Total Orders

Power BI result: **98,208**  
SQL result: **98,208**

Validation screenshot:

```text
TotalOrdersSQL.png
```

### 3. Total Delayed Orders

Power BI result: **6,534**  
SQL result: **6,534**

Validation screenshot:

```text
DelayedOrdersSQL.png
```

The three validation checks confirm that the selected aggregated Power BI values match the corresponding Mart-level SQL results.

### Additional warehouse and RFM validation

The rebuilt warehouse and refreshed RFM enrichment were checked after the simulated delta load:

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
| Invalid global latitude/longitude or half-null coordinate pairs | **0** |
| Current customers with coordinates outside the approximate Brazil bounds | **4** |
| Warehouse security mappings | **5** |

The validation compares the SQL-derived `current_rfm_segment` with the Python-produced RFM segment across **all Mart SCD2 customer versions** by `customer_unique_id`; it returned zero mismatches. The current customer population is 95,420 and the five segments sum to 94,983.

An additional full-status Mart reconciliation verified `SUM(price + freight_value)` = **R$ 15,843,553.24** without a difference; this is distinct from the non-canceled Power BI Total Revenue result of **R$ 15,737,887.53**. Both values are valid for their respective order-status populations.

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
|   |-- Innowise_Project_Stage3.pbit
|   |-- Innowise_Project_Stage3.pbix    (saved locally after refresh, if distributed)
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

Execute the Stage 2 notebook (uploaded as `stage2(3).ipynb`; it can be renamed `stage2.ipynb` for the repository):

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

The provided `reset_stage(4).sql` both resets `stage.raw_orders` and loads the delta file. Running another `COPY` would duplicate the Stage batch. `checks.sql` validates row counts, duplicate and orphan-key checks, SCD behavior, RFM reconciliation, revenue totals, geolocation and security mappings.

## 7. Review Stage 3 requirements

Open:

```text
stage3.ipynb
```

This notebook contains the requirement-gathering principles, stakeholder interview questions, BRD, wireframing notes, data storytelling and SQL-vs-Power-BI validation documentation used to define and verify the Power BI solution.

## 8. Open Power BI

The uploaded final Power BI artifact is a template:

```text
Innowise_Project_Stage3_final_ver2910_final.pbit
```

Open the `.pbit` in Power BI Desktop and supply the PostgreSQL connection parameters `pServer` (server name, for example `localhost`) and `pDatabase` (for example `olist_dwh`). A Power BI template holds the semantic model and report definition but **does not include imported data**. Refresh the Mart tables with PostgreSQL running, verify the `Dynamic_Security` role and save a local `.pbix` if an interactive report with imported data is needed. The available source dates extend to **2018-09-03**; selected monthly visuals exclude the incomplete September 2018 as described above.

---

# Outstanding Items

The following items were deliberately left open; they are **not** described as completed work:

1. **Geolocation quality:** four current customers (three ZIP prefixes: `46560` / BA, `68275` / PA and `83252` / PR) have coordinates outside approximate Brazil bounds despite having Brazilian addresses. The next ETL revision should reject or correct out-of-country geolocation outliers before ZIP/state aggregation, then regenerate and reload the affected warehouse data. The global coordinate-validity check returned zero invalid values, but that check cannot detect geographically misplaced yet numerically valid coordinates; the separate Brazil-bounds check identified these four exceptions. This correction has **not** been applied yet.
2. **Power BI map validation:** the map uses PostgreSQL latitude/longitude, but the outlier points still need to be fixed and map rendering verified in **Power BI Service** before the next demo. Desktop output alone is not sufficient confirmation.
3. **Inactive date relationships:** the four alternate date relationships (approval, carrier handoff, customer delivery, estimated delivery) are currently unused in measures with `USERELATIONSHIP()`. They have been retained for potential milestone-date analysis, but must eventually be used or removed.
4. **Geographic location bar chart:** Region -> State -> City drill-down works. Its Top 10 + Others grouping has **not** been implemented so that the working hierarchy and presentation were not disturbed. The KPI Overview **does** show Top 10 + Others, with the documented value-sort limitation for the Others row.
5. **Notebook version synchronization:** the originally uploaded `stage1(9).ipynb` predates the Stage 1 Markdown corrections made during the documentation review; make sure the edited notebook is saved as the final `stage1.ipynb` before submission. The uploaded `stage3(3).ipynb` contains the revised BRD without obsolete YoY requirements. Its wireframe note still uses the original design names (Map / Drill-down and Operations Dashboard), which are correctly distinguished from the final report pages in this README.

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
