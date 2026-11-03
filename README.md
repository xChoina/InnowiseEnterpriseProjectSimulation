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

Stage 2 is rebuilt from the original Olist source data rather than from the Stage 1 cleaned analytical dataset. Stage 1 generates two separate analytical outputs: the delivered-order/positive-weight dataset for EDA, and an RFM table calculated independently from eligible purchase records (without a delivery-status or product-weight restriction). The RFM output enriches current customer records in the Mart.

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

The notebook uses the following Olist datasets:

```text
olist_order_items_dataset.csv
olist_orders_dataset.csv
olist_customers_dataset.csv
olist_products_dataset.csv
product_category_name_translation.csv
```

The main analytical dataset is built with left merges of order items, orders, customers, products and the product-category translation table.

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

`olist_rfm_segmentation.csv` is loaded into `stage.rfm_temp` and later enriches the current customer version in `mart.dim_customer`.

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
- **SCD Type 2** — in addition to natural customer address changes present in the source data, 10 existing customers with later orders are deliberately selected and their location is manually changed to `RJ / rio de janeiro / 20000`,
- **exact duplicates** — selected initial-load rows are repeated to test idempotency.

The SCD1 change is displayed in the notebook as a before/after comparison.

No artificial `order_id` is created for the SCD2 test. The manually injected location changes are attached to real later orders of existing customers. During the delta load, the previous customer version is closed and a new current version is created.

The notebook exports:

```text
initial_load.csv
delta_load.csv
```

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

`stage.rfm_temp` stores the Stage 1 RFM result and is intentionally preserved when `stage.raw_orders` is reset for the delta batch.

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

A partial unique index ensures only one current version exists for each `customer_unique_id`. In addition to natural address changes present in the source data, the simulated delta manually changes the location of 10 existing customers to `RJ / rio de janeiro / 20000`. This provides explicit SCD2 test cases: the previous version is closed by setting its `valid_to` and `is_current = FALSE`, while the new location becomes the current version.

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
```

`mart.dim_seller` intentionally contains only `seller_id` in the current implementation because the Stage 2 pipeline carries only the seller identifier into the warehouse. The dimension is kept as a separate star-schema entity and can be enriched with additional seller attributes in a future extension.

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
recency
frequency
monetary
r_score
f_score
m_score
segment
```

RFM values are populated only on the **current SCD2 customer version**. Historical versions retain their location history without duplicating a stale RFM snapshot.

Customers not eligible for RFM intentionally retain `NULL` RFM attributes and `NULL` segment in `mart.dim_customer`. The final segmentation covers **94,983 of 95,420** unique source customers. The other **437** are excluded by purchase-status eligibility (431 canceled-only and 6 unavailable-only), not by delivery completion or product weight.


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

```text
stage_create.sql
data_to_stage.sql
core_create.sql
data_to_core.sql
mart_create.sql
data_to_mart.sql
reset_stage.sql
delta_load.sql
checks.sql
```

Responsibilities:

- `stage_create.sql` — creates Stage, Core and Mart schemas plus Stage tables.
- `data_to_stage.sql` — truncates `stage.raw_orders` and `stage.rfm_temp` **and executes the two initial CSV `COPY` commands** (the files must already be accessible to PostgreSQL).
- `core_create.sql` — creates the normalized Core model, constraints and indexes.
- `data_to_core.sql` — performs the initial Stage-to-Core load and builds initial SCD2 history.
- `mart_create.sql` — creates the reporting Star Schema.
- `data_to_mart.sql` — loads / upserts dimensions and fact data, resolves the temporal customer key and calculates reporting fields.
- `reset_stage.sql` — truncates only `stage.raw_orders` before the simulated delta load; `stage.rfm_temp` is retained.
- `delta_load.sql` — performs the incremental Core load, including new records, SCD1, SCD2 and duplicate-safe processing.
- `checks.sql` — contains validation queries for row counts, duplicate detection, orphan keys, SCD behavior, RFM coverage and revenue reconciliation.

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

After the initial load:

```text
1. reset_stage.sql
2. load delta_load.csv into stage.raw_orders
3. delta_load.sql
4. data_to_mart.sql
```

`reset_stage.sql` clears only the current raw Stage batch. Load the simulated delta with:

```sql
COPY stage.raw_orders
FROM '/delta_load.csv'
DELIMITER ','
CSV HEADER;
```

The path shown above is an example and can be changed according to the PostgreSQL server environment.

`stage.rfm_temp` remains available for customer enrichment.

Re-running the same delta is designed not to create duplicate transaction rows or duplicate customer versions.

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

Main files:

```text
stage3.ipynb
Innowise_Project_Stage3.pbix
```

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

`stage3.ipynb` contains requirement gathering, the Business Requirements Document (BRD), wireframing notes, data storytelling and validation documentation. The `.pbix` file contains the implemented Power BI report.

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

The BI solution provides two complementary reporting experiences.

### Executive Director

The strategic dashboard is designed to monitor:

- overall sales performance,
- revenue growth and YoY change,
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

The principal Stage 3 measures use the Mart model. Unless stated otherwise, dashboard-wide sales measures **exclude `canceled` orders**; the warehouse retains these transactions for auditability.

- **Total Revenue** — product price plus freight for non-canceled orders, calculated from `mart.fact_sales[total_value]`.

- **Total Orders** — distinct non-canceled `order_id`, returning zero instead of blank when there are no qualifying orders.

- **Average Order Value (AOV)** — Total Revenue / Total Orders.
- **Total Customers** — distinct customers in the applicable non-canceled reporting context.
- **Orders per Customer** — Total Orders / Total Customers.
- **Revenue per Customer** — Total Revenue / Total Customers.
- **Month-over-Month Change (%)** — compares the latest completed reporting month with the preceding month; avoids comparing an incomplete September 2018 with August 2018.
- **Average Freight** — average freight per relevant fact row.
- **Total Delayed Orders** — distinct non-canceled orders where `delayed_flag = 1`.
- **Average Delivery Days** — duration measured per order, not per order item.
- **Average Delay Days** — mean days beyond the expected delivery date for delayed orders.
- **SLA Eligible Orders** — orders for which actual and estimated delivery dates are both available.
- **Delayed Order Rate %** — delayed orders / SLA Eligible Orders.
- **% On-Time Delivery** — on-time orders / SLA Eligible Orders.
- **Regional Revenue Share %** — selected geographical revenue relative to total revenue within the user's effective RLS scope.

Prior-year comparison and `SAMEPERIODLASTYEAR()` are discussed in the Stage 3 BI requirements / DAX context; the final KPI Overview emphasizes **MoM Change (%)**, not a YoY card.

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

RFM is calculated in Python at `customer_unique_id` level for eligible order statuses (`approved`, `invoiced`, `processing`, `shipped`, `delivered`) and loaded into the current Mart customer version. It uses:

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

The experience supports navigation buttons and shared report filters. Customer State, City, Product Category and Current RFM Segment slicers are arranged together above the KPI cards. Date-range filtering is also provided. Contextual information icons explain non-obvious KPI and visualization definitions.

The geographical page provides **State -> City** drill-down, a dynamic location chart title based on the selected metric (Revenue, Orders, AOV), and supporting state-level analysis.

The Delivery Performance page shows delivery-time distribution, geographical delivery issues and a combined order-volume / delayed-rate trend.

---

## Non-Functional & Technical Requirements

### Dynamic Row-Level Security

The report's dynamic-security design uses the `Dynamic_Security` role and a security mapping table in the Power BI model (referred to as `mart dim_security` in the model). The signed-in user is identified using `USERPRINCIPALNAME()`; regional-manager users are restricted to assigned customer states, while Director access spans all states.

**Deployment note:** the security mapping was maintained in the Power BI model in this project iteration. It should not be confused with a verified physical `mart.dim_security` table in PostgreSQL. For a production deployment, this mapping would need a governed warehouse or identity-management source, and any redundant test roles should be reviewed before publishing.

### Advanced DAX

The report includes the required advanced DAX patterns:

- `SUMX` for row-by-row Total Revenue calculation,
- `REMOVEFILTERS` for revenue-share / total-context calculations while respecting RLS,
- a prior-year comparison pattern with `SAMEPERIODLASTYEAR` documented in the BI analytical work (the KPI Overview itself presents MoM Change),
- time intelligence through the active order-date relationship with `mart.dim_date`.

The date dimension is marked as the model's Date Table.

### Data model and performance

Power BI uses the Mart Star Schema as the reporting semantic model.

Target refresh frequency is daily; in the local project environment, SQL and Power BI refreshes can be executed manually.

The model uses an optimized star-schema structure and reusable DAX measures, with a target page load time below 3 seconds.

---

## Power BI Report

Main report file:

```text
Innowise_Project_Stage3.pbix
```

Power BI connects to the reporting-ready Mart layer.

### KPI Overview

Strategic overview containing:

- Total Revenue, Total Orders and Average Order Value,
- **Month-over-Month Change (%)** based on completed months,
- Monthly Trend with a Revenue / Total Orders / AOV metric selector,
- a state-level Total Orders table with data bars,
- shared business filters and date-range filtering.

The partial **September 2018** (data only through September 3) is excluded from monthly trend presentation using a **visual-level date cutoff of August 31, 2018**, so it does not create a misleading apparent monthly collapse. Global report data and other KPI contexts retain their normal date coverage.

### Geographic Sales Analysis

Geographical and categorical analysis containing:

- **Selected Metric by Location** with **State -> City** drill-down,
- dynamic visual title: **Revenue by Location / Orders by Location / AOV by Location**,
- **Top 5 Categories by Revenue**,
- supporting state-level metric visualization.

The geography analysis focuses on Brazil and includes a fallback state view for locations where map visuals are unavailable. Operational context, including the on-time delivery KPI, uses an **illustrative** color convention (green >= 95%, amber >= 90% and < 95%, red < 90%); these thresholds are not an official published Olist SLA.

### Customer Segmentation RFM

Customer segmentation analysis containing:

- **Total Customers**, **AOV**, **Orders / Customer**, **Revenue per Customer** KPI cards,
- **RFM Segment Value** metric-switching chart (Total Revenue or Revenue per Customer),
- **Customers by RFM Segment** donut chart showing the five real segment names and proportions,
- behavioral segment table with **Total Customers**, **Avg Recency (Days)**, **Orders / Customer**, and **AOV**.

RFM charts and the segment table filter out `NULL` segment values **at the visual level**, not at page level. This keeps the global customer KPI intact. For the full non-canceled report scope, **94,989** customers appear in the global KPI, while **94,983** appear in the five RFM segments; the difference is **6 unavailable-only customers** without an eligible RFM status. The 431 canceled-only source customers are excluded from the non-canceled KPI scope.

### Delivery Performance

Operational delivery monitoring containing:

- **Total Delayed Orders**, **% On-Time Delivery**, **Avg Delay Days**, **Delayed Order Rate %**,
- **Delayed Orders by State**,
- **Delivery Time Distribution** with data labels,
- **Order Volume vs Delay Rate** (order counts and delayed-order-rate line).

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

The wireframes define the initial placement of KPI cards, filters, navigation and main/supporting visuals. They intentionally use simple boxes and placeholder labels rather than final styling.

---

## Data Storytelling

Two business patterns were identified from the final report.

### Pattern 1 — Customer value is concentrated in the Regulars segment

The Regulars segment contains the largest number of customers and generates the highest total revenue. Champions represent only a very small part of the customer base but generate substantially higher revenue per customer.

**Hypothesis:** most customers make only a limited number of repeat purchases, while a small group of highly engaged customers generates significantly more value per customer.

**Business action:** focus retention and repeat-purchase campaigns on high-value Regulars and At-risk customers. Converting even a small share of these customers into Champions could increase customer lifetime value without relying only on new customer acquisition.

### Pattern 2 — Delivery delays show visible peaks during periods of higher activity

The delivery-time distribution has its largest group in the **6–10 day** bucket. Delayed-order-rate patterns show noticeable peaks during late 2017 and early 2018; the report now suppresses monthly percentages for periods with fewer than 100 SLA-eligible orders to avoid drawing conclusions from a very small sample.

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

The RFM source-to-Mart validation joins by `customer_unique_id` and `is_current = TRUE`. All five segments matched exactly, with no missing or mismatched current customer assignments.

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

Execute:

```text
stage2.ipynb
```

This creates:

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
```

`data_to_stage.sql` already executes the CSV imports. Its `COPY` file paths assume `/initial_load.csv` and `/olist_rfm_segmentation.csv` exist on the database server/container. **Do not import the same files twice.**

## 6. Process the simulated incremental load

Run:

```text
reset_stage.sql
```

Load the simulated delta:

```sql
COPY stage.raw_orders
FROM '/delta_load.csv'
DELIMITER ','
CSV HEADER;
```

Then run:

```text
delta_load.sql
data_to_mart.sql
checks.sql
```

`checks.sql` validates the final warehouse using row-count, duplicate, orphan-key, SCD, RFM-coverage and revenue-reconciliation checks. A separate RFM source-to-Mart comparison confirmed zero mismatches across all five segments.

## 7. Review Stage 3 requirements

Open:

```text
stage3.ipynb
```

This notebook contains the requirement-gathering principles, stakeholder interview questions, BRD, wireframing notes, data storytelling and SQL-vs-Power-BI validation documentation used to define and verify the Power BI solution.

## 8. Open Power BI

Open:

```text
Innowise_Project_Stage3.pbix
```

and connect / refresh against the PostgreSQL Mart layer if required by the local environment. Review the PostgreSQL server/database connection settings, the loaded security mapping and the `Dynamic_Security` role before sharing the report. The available data extends to **2018-09-03**; the monthly charts exclude the incomplete September 2018 as described above.

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
