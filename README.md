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

The main Stage 3 metrics include:

- **Total Revenue** — total customer charge including product price and freight.

```text
Total Revenue = SUMX(fact_sales, price + freight_value)
```

- **Total Orders** — unique number of orders.

```text
Total Orders = DISTINCTCOUNT(fact_sales[order_id])
```

- **Average Order Value (AOV)** — revenue per unique order.

```text
AOV = Total Revenue / Total Orders
```

- **Revenue Last Year** — revenue for the equivalent period in the previous year.

```DAX
Revenue Last Year =
CALCULATE(
    [Total Revenue],
    SAMEPERIODLASTYEAR(dim_date[full_date])
)
```

- **Revenue YoY %** — percentage change against the equivalent period in the previous year.

```text
Revenue YoY % = (Total Revenue - Revenue Last Year) / Revenue Last Year
```

- **Total Customers** — unique customers in the current filter context.
- **Orders per Customer** — Total Orders / Total Customers.
- **Revenue per Customer** — Total Revenue / Total Customers.
- **Average Freight** — average `freight_value`.
- **Total Delayed Orders** — unique orders where `delayed_flag = 1`.
- **Average Delivery Days** — average delivery duration calculated once per order.
- **Average Delay Days** — average number of days past the estimated delivery date for delayed orders.
- **Delayed Order Rate %** — delayed orders divided by SLA-eligible orders.
- **% On-Time Delivery** — on-time orders divided by SLA-eligible orders.
- **Regional Revenue Share %** — selected geographical revenue divided by the total revenue available within the user's authorized RLS scope.

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

RFM is calculated at `customer_unique_id` level using:

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

---

## Functional Requirements

The report contains four main business pages.

### Strategic dashboard — Executive Director

1. **KPI Overview**
2. **Map / Geographical Analysis**
3. **RFM Segmentation**

### Operational dashboard — Operations Manager

4. **Operations**

The report also contains supporting tooltip pages, an `Order_Details` drill-through page and methodology / FAQ content. Supporting pages are not counted as main dashboard pages.

The strategic experience supports navigation through interactive buttons and bookmarks. The Map page provides State -> City drill-down and a state-level fallback visual if map visuals are unavailable.

The Operations page shows delivery-time distribution, delivery bottlenecks, delayed-order trends and visually highlights delayed or anomalous records.

---

## Non-Functional & Technical Requirements

### Dynamic Row-Level Security

Power BI uses Dynamic RLS based on `mart.dim_security`.

- Regional / Operations Managers are restricted to their assigned Brazilian state or states through `customer_state`.
- The logged-in user is identified with `USERPRINCIPALNAME()`.
- The Executive Director has unrestricted access to all states.
- Security is applied through the data model rather than being embedded inside revenue measures.

### Advanced DAX

The report includes the required advanced DAX patterns:

- `SUMX` for row-by-row Total Revenue calculation,
- `REMOVEFILTERS` for revenue-share / total-context calculations while respecting RLS,
- `SAMEPERIODLASTYEAR` for previous-year comparison,
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

- Total Revenue,
- Total Orders,
- Revenue YoY %,
- Average Order Value,
- Monthly Trend,
- state-level summary with conditional data bars,
- date filtering,
- metric selection.

### Map

Geographical and categorical analysis containing:

- **Selected Metric by Location** with State -> City drill-down,
- **Top 5 Category Revenue**,
- **Selected Metric by State** fallback visual.

The map is focused on Brazil and the supporting state visual allows analysis even when map visuals are unavailable.

### RFM

Customer segmentation analysis containing:

- Total Customers,
- AOV,
- Orders per Customer,
- Revenue per Customer,
- **Revenue by RFM Segment**,
- **Revenue per Customer by Segment**,
- customer distribution by segment,
- segment-level detail table.

### Operations

Operational delivery monitoring containing:

- **Total Delayed Orders**,
- **Avg Delivery Days**,
- **Avg Delay Days**,
- **Delayed Order Rate %**,
- **Delivery Bottlenecks by Region / State**,
- **Delivery Time Distribution**,
- **Delayed Orders Trend**.

The operational page is designed to surface delivery exceptions and geographical bottlenecks for day-to-day action.

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

Most deliveries are completed within the 6-10 day delivery-time bucket, while the overall delayed-order rate is approximately **6.77%**. The delayed-order trend shows visible peaks, particularly during late 2017 and early 2018.

**Hypothesis:** periods with higher order activity may put additional pressure on fulfillment and logistics capacity, contributing to more delayed deliveries.

**Business action:** monitor delayed-order rate together with order volume and prepare additional logistics capacity before expected demand peaks. State-level monitoring can then identify locations requiring operational intervention.

---

## SQL vs Power BI Validation

Three aggregated dashboard metrics were independently validated against raw SQL queries executed on the Mart layer. Side-by-side screenshots are included in the Stage 3 deliverables.

### 1. Total Revenue

Power BI result: approximately **R$ 15.74M**  
SQL result: **15,737,887.53**

```sql
SELECT
    ROUND(
        SUM(COALESCE(price, 0) + COALESCE(freight_value, 0))::numeric,
        2
    ) AS total_revenue
FROM mart.fact_sales
WHERE order_status <> 'canceled';
```

Validation screenshot:

```text
RevenueSQL.png
```

### 2. Total Orders

Power BI result: **98,208**  
SQL result: **98,208**

```sql
SELECT
    COUNT(DISTINCT order_id) AS total_orders
FROM mart.fact_sales
WHERE order_status <> 'canceled';
```

Validation screenshot:

```text
TotalOrdersSQL.png
```

### 3. Total Delayed Orders

Power BI result: **6,534**  
SQL result: **6,534**

```sql
SELECT
    COUNT(DISTINCT order_id) AS total_delayed_orders
FROM mart.fact_sales
WHERE delayed_flag = 1
  AND order_status <> 'canceled';
```

Validation screenshot:

```text
DelayedOrdersSQL.png
```

The three validation checks confirm that the selected aggregated Power BI values match the corresponding Mart-level SQL results.

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

This notebook contains the requirement-gathering principles, stakeholder interview questions, BRD, wireframing notes, data storytelling and SQL-vs-Power-BI validation documentation used to define and verify the Power BI solution.

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
