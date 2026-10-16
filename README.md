# Olist E-Commerce Analytics & Data Warehouse Project

End-to-end analytics project based on the **Brazilian E-Commerce Public Dataset by Olist**.

Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

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

Stage 2 is rebuilt from the original Olist source data rather than from the Stage 1 cleaned analytical dataset. The Stage 1 RFM output is reused separately as customer-segmentation enrichment in the Mart.

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
- filtering to `order_status == 'delivered'` and `product_weight_g > 0`,
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

RFM is calculated at `customer_unique_id` level:

- **Recency** — days since the customer's latest purchase relative to one day after the latest dataset purchase date,
- **Frequency** — number of unique `order_id`,
- **Monetary** — sum of product `price`.

Scoring uses:

- `pd.qcut()` for Recency,
- `pd.qcut()` for Monetary,
- `pd.cut()` for Frequency with order-count boundaries `1`, `2`, `3`, `4+`.

Customers are assigned to:

```text
Champion
At risk
Sleeping
Newbies
Regulars
```

Final segment counts from the notebook:

```text
Regulars    46,849
Sleeping    22,721
Newbies     22,607
At risk      1,026
Champion       136
Total       93,339
```

The notebook also displays the Top 5 customers by Monetary value in each segment.

## Stage 1 outputs

```text
olist_cleaned_dataset_ground_truth.csv
olist_rfm_segmentation.csv
Brazilian_Ecomerce_report_final.html
```

The cleaned dataset is a reference / ground-truth analytical output. It is **not** the main Stage 2 pipeline source.

`olist_rfm_segmentation.csv` is loaded into `stage.rfm_temp` and later enriches the current customer version in `mart.dim_customer`.

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
- **SCD Type 1** — selected existing orders receive an updated `order_status`,
- **SCD Type 2** — selected existing customers receive changed location attributes,
- **exact duplicates** — selected initial-load rows are repeated to test idempotency.

No artificial new `order_id` is manufactured for the SCD2 test. Customer history changes are tied to real later order events.

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

A partial unique index ensures only one current version exists for each `customer_unique_id`.

`core.orders` keeps `customer_unique_id` rather than a physical foreign key to one customer version. The correct `customer_sk` is resolved later by the temporal join when the fact table is loaded.

### SCD Type 1

The incremental load applies `ON CONFLICT ... DO UPDATE` where the latest value should overwrite the existing value.

Examples include:

- order status / order milestone timestamps,
- product attributes,
- product-category translation.

Updates use `IS DISTINCT FROM` where relevant so unchanged records are not rewritten unnecessarily.

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
```

Responsibilities:

- `stage_create.sql` — creates Stage, Core and Mart schemas plus Stage tables.
- `data_to_stage.sql` — truncates and loads the initial batch and RFM segmentation into Stage.
- `core_create.sql` — creates the normalized Core model, constraints and indexes.
- `data_to_core.sql` — performs the initial Stage-to-Core load and builds initial SCD2 history.
- `mart_create.sql` — creates the reporting Star Schema.
- `data_to_mart.sql` — loads / upserts dimensions and fact data, resolves the temporal customer key and calculates delivery fields.
- `reset_stage.sql` — truncates only `stage.raw_orders` and loads `delta_load.csv`; `stage.rfm_temp` is retained.
- `delta_load.sql` — performs the incremental Core load, including new records, SCD1, SCD2 and duplicate-safe processing.

## Initial load order

Run manually in this order:

```text
1. stage_create.sql
2. data_to_stage.sql
3. core_create.sql
4. data_to_core.sql
5. mart_create.sql
6. data_to_mart.sql
```

`data_to_stage.sql` loads:

```text
/initial_load.csv
/olist_rfm_segmentation.csv
```

## Delta load order

After the initial load:

```text
1. reset_stage.sql
2. delta_load.sql
3. data_to_mart.sql
```

`reset_stage.sql` replaces only the current raw Stage batch:

```sql
TRUNCATE TABLE stage.raw_orders;

COPY stage.raw_orders
FROM '/delta_load.csv'
DELIMITER ','
CSV HEADER;
```

`stage.rfm_temp` remains available for customer enrichment.

Re-running the same delta is designed not to create duplicate transaction rows or duplicate customer versions.

---

# Docker

PostgreSQL runs inside Docker.

Docker is used only to make generated CSV files available on the PostgreSQL server filesystem. SQL scripts are executed manually in the database client.

Check the PostgreSQL container name:

```bash
docker ps
```

Copy the generated files into the container:

```bash
docker cp initial_load.csv <postgres_container>:/initial_load.csv
docker cp delta_load.csv <postgres_container>:/delta_load.csv
docker cp olist_rfm_segmentation.csv <postgres_container>:/olist_rfm_segmentation.csv
```

The SQL scripts expect:

```text
/initial_load.csv
/delta_load.csv
/olist_rfm_segmentation.csv
```

Because PostgreSQL `COPY` reads from the database-server filesystem, the CSV files must exist inside the container before the related SQL scripts are executed.

No `docker cp` commands are stored inside the SQL scripts.

---

# Stage 3 — BI Development

Stage 3 contains two main deliverables:

```text
stage3.ipynb
Innowise_Project_Stage3.pbix
```

`stage3.ipynb` documents the requirement-gathering process and the Business Requirements Document (BRD), while the `.pbix` file contains the implemented Power BI report.

## Requirement Gathering

The Stage 3 notebook defines five core requirement-gathering principles:

1. Focus on the business problem rather than asking stakeholders which charts they want.
2. Define the operational expectation and the action users should take after seeing the data.
3. Prototype the solution before building the final report.
4. Define the relevant timeframe and reporting frequency.
5. Prioritize a small set of important KPIs instead of placing every metric on one screen.

The notebook also contains eight stakeholder questions divided between:

- the **Executive Director**, focused on strategic goals, KPIs and decision-making,
- the **Operations Manager**, focused on operational pain points, daily monitoring and corrective actions.

It also explains why an overloaded dashboard reduces usability and distinguishes a simple metric from an actionable insight.

---

## Business Requirements Document

The BRD defines two main audiences.

### Executive Director

The strategic reporting experience focuses on:

- YoY growth,
- overall sales performance,
- geographical / categorical analysis,
- customer value and segmentation.

### Operations Manager

The operational dashboard focuses on:

- delivery bottlenecks,
- delayed orders,
- delivery timelines,
- anomalies requiring action.

### Stage 3 KPI definitions

The BRD defines the main Stage 3 measures as:

- **Total Revenue** — row-by-row calculation of product sales plus freight,
- **Market / Regional Share %** — selected branch or regional revenue compared with the overall company total,
- **YoY Growth** — sales compared with the same period in the previous year,
- **Delivery SLA metrics** — time differences between order checkpoints used to identify logistics bottlenecks.

This Stage 3 revenue definition is intentionally broader than the Stage 1 analytical revenue definition: Stage 1 uses product `price`, while the Mart also stores `freight_value` and `total_value = price + freight_value`.

### Functional requirements

The BRD defines:

- a **3-page strategic dashboard** for the Director:
  - KPI Overview,
  - Map / geographical analysis with drill-down,
  - RFM segmentation,
- a **single-page operational dashboard** for the Operations Manager,
- navigation through interactive buttons / bookmarks,
- visual highlighting of delayed or anomalous shipments.

### Non-functional and technical requirements

The Stage 3 notebook defines:

- **Row-Level Security (RLS)** restricting Regional Managers to their assigned region,
- a reporting model based on the Mart Star Schema,
- a target of daily data refresh,
- a target report load time below 3 seconds.

These are documented business / technical requirements for the BI solution. The local project workflow still uses manual SQL execution and manual refresh where required.

### Dynamic Row-Level Security

Power BI uses Dynamic RLS based on `mart.dim_security`.

The table maps users to allowed Brazilian states. `USERPRINCIPALNAME()` or `USERNAME()` identifies the logged-in user, and the security filter is propagated through the model to `mart.fact_sales`.

This allows one Power BI report and one dynamic role to serve multiple Regional Managers, while access can be managed by updating the security table instead of creating separate reports or roles.

---

## Power BI report

Main report file:

```text
Innowise_Project_Stage3.pbix
```

Power BI connects to the reporting-ready Mart layer.

The final report contains four main report pages: three strategic pages plus one operational page.

## KPI Overview

Strategic overview containing:

- Total Revenue,
- Total Orders,
- Revenue YoY %,
- Average Order Value,
- monthly trend,
- state-level summary,
- date filtering,
- metric navigation / selection.

## Map

Geographical and category analysis containing:

- **Revenue by Location**,
- **Top 5 Category Revenue**,
- **Revenue vs Freight Cost**,
- geographical drill-down through the location hierarchy.

## RFM

Customer segmentation analysis containing:

- **Revenue by RFM Segment**,
- customer-segment summary,
- customer distribution by segment,
- **Revenue per Customer by Segment**.

## Operations

Operational delivery monitoring containing:

- **Total Delayed Orders**,
- **Avg Delivery Days**,
- **Avg Delay Days**,
- **Delivery Bottlenecks by Region / State**,
- **Delivery Time Distribution**,
- **Delayed Orders Trend** and delayed-order rate.

The report also contains supporting tooltip pages, an `Order_Details` page and a methodology / FAQ view.

Navigation and date filtering are available throughout the report.

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
|   |   `-- delta_load.sql
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
|   `-- Innowise_Project_Stage3.pbix
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

Run manually:

```text
stage_create.sql
data_to_stage.sql
core_create.sql
data_to_core.sql
mart_create.sql
data_to_mart.sql
```

## 6. Process the simulated incremental load

Run manually:

```text
reset_stage.sql
delta_load.sql
data_to_mart.sql
```

## 7. Review Stage 3 requirements

Open:

```text
stage3.ipynb
```

This notebook contains the requirement-gathering principles, stakeholder interview questions, business reflection and BRD used to define the Power BI solution.

## 8. Open Power BI

Open:

```text
Innowise_Project_Stage3.pbix
```

and connect / refresh against the PostgreSQL Mart layer if required by the local environment.

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
