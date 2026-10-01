# Olist E-Commerce Analytics & Data Warehouse Project

End-to-end analytics project based on the **Brazilian E-Commerce Public Dataset by Olist**.

Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

The project covers three roles and stages:

- **Stage 1 — Junior Data Analyst:** data cleaning, EDA, feature engineering, customer analytics and RFM segmentation.
- **Stage 2 — Junior Data Engineer:** incremental-load simulation, PostgreSQL DWH architecture, SCD handling and Star Schema preparation.
- **Stage 3 — BI Developer:** Power BI semantic model and business dashboards for strategic and operational reporting.

---

## Project Flow

```text
Raw Olist CSV files
        |
        v
Stage 1 — Python analysis
        |
        +--> Cleaned ground-truth CSV
        +--> RFM segmentation CSV
        |
        v
Stage 2 — Initial / Delta simulation
        |
        +--> initial_load.csv
        +--> delta_load.csv
        |
        v
PostgreSQL
Stage -> Core -> Mart
        |
        v
Power BI
```

Architecture diagrams are included with the Stage 2 files:

- `FlowChart.png`
- `Core_erd.png`
- `Mart_erd.png`

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
olist_geolocation_dataset.csv
```

The main analytical dataset is created by merging order items, orders, customers, products and translated product categories.

## Data preparation

The notebook performs data cleaning and preparation including:

- standardizing column names,
- duplicate checks and removal,
- datetime conversion,
- filtering to delivered orders with positive product weight,
- handling missing product categories,
- customer-city standardization,
- categorical feature engineering.

Created analytical features include:

- `value_tier`,
- `purchase_day_of_week`,
- `category_keyword`,
- department grouping,
- regional manager mapping.

## Simulated analytical fields

Some fields are intentionally created for analytical exercises and do not come from the original Olist source data.

### Product cost and margin

A reproducible random cost multiplier is generated with:

```python
np.random.seed(24)
```

and used to create:

```text
product_cost
profit_margin
```

### Loyalty status

A simulated loyalty attribute is created for a subset of customers:

```text
Standard
Premium
```

with Premium status applied after `2018-01-01` for the selected customers.

### Regional managers

Brazilian states are mapped to supplementary regional managers for hierarchical analysis.

---

## Automated profiling

The cleaned analytical dataset is profiled with **Sweetviz**.

Generated report:

```text
Brazilian_Ecomerce_report_final.html
```

---

## Exploratory Data Analysis

Stage 1 contains static and interactive analysis.

### Static analysis

The notebook includes:

- smoothed revenue and freight trends using a 7-day rolling average,
- freight-value distribution with a boxplot,
- Revenue vs Freight Cost comparison by department.

### Interactive analysis

Plotly is used for:

- geographical analysis of revenue and freight value by Brazilian state,
- hierarchical drill-down:

```text
Regional Manager -> State -> Main Department
```

---

## Customer analytics

### Monthly metrics

The notebook calculates:

- total revenue,
- total orders,
- unique customers,
- Average Order Value (AOV),
- Average Revenue Per User (ARPU).

Stage 1 revenue calculations use the `price` field.

### Cohort analysis

Customers are assigned to cohorts based on the month of their first purchase.

A retention matrix is created using:

```text
cohort_month
cohort_index
```

### RFM segmentation

RFM is calculated for each `customer_unique_id`:

- **Recency** — days since the latest purchase,
- **Frequency** — number of unique orders,
- **Monetary** — sum of product `price`.

Quantile-based R, F and M scores are created and customers are assigned to:

```text
Champion
At risk
Regulars
```

The notebook also displays the Top 5 customers in each segment.

---

## Stage 1 outputs

```text
olist_cleaned_dataset_ground_truth.csv
olist_rfm_segmentation.csv
Brazilian_Ecomerce_report_final.html
```

The cleaned dataset acts as a reference output for later pipeline validation.

The RFM result is loaded into the Stage layer in Stage 2 and later enriches the customer dimension in the Mart.

---

# Stage 2 — Data Engineering

Main file:

```text
stage2_new.ipynb
```

Stage 2 rebuilds the data pipeline from the original Olist source files rather than using the cleaned Stage 1 dataset as the primary source.

## Initial and Delta simulation

The source data is sorted by `order_purchase_timestamp` and split into:

```text
90% -> initial_load.csv
10% -> delta batch
```

The final delta dataset also contains intentionally injected test cases:

- SCD Type 1 case,
- SCD Type 2 case,
- duplicated rows.

The notebook exports:

```text
initial_load.csv
delta_load.csv
```

---

# PostgreSQL DWH Architecture

The warehouse follows:

```text
Stage -> Core -> Mart
```

## Stage layer

Tables:

```text
stage.raw_orders
stage.rfm_temp
```

`stage.raw_orders` contains the current load batch.

`stage.rfm_temp` stores the RFM segmentation created in Stage 1.

## Core layer

The Core layer contains:

```text
core.customers
core.orders
core.order_items
core.products
core.sellers
```

The Core model is normalized and keeps customer history.

### SCD Type 2

`core.customers` contains:

```text
customer_sk
customer_unique_id
valid_from
valid_to
is_current
```

`customer_sk` is the surrogate primary key.

Changes in customer location attributes are versioned using SCD Type 2 logic:

```text
customer_city
customer_state
customer_zip_code_prefix
```

The old record is expired and a new current customer version is inserted.

### SCD Type 1 / overwrite logic

The incremental SQL uses `ON CONFLICT ... DO UPDATE` for attributes that should be overwritten with their latest value, including selected product and order attributes.

### Deduplication / idempotency

Natural transaction keys and database constraints are used to prevent duplicate inserts.

Examples:

```text
orders      -> order_id
order_items -> order_id + order_item_id
products    -> product_id
sellers     -> seller_id
```

---

## Mart layer

The reporting layer uses a Star Schema.

### Fact table

```text
mart.fact_sales
```

Grain:

```text
one row per order_id + order_item_id
```

The fact contains:

- customer surrogate key,
- product,
- seller,
- order / approval / delivery date keys,
- order status,
- price,
- freight value,
- `total_value`.

In SQL:

```text
total_value = price + freight_value
```

### Dimensions

```text
mart.dim_customer
mart.dim_product
mart.dim_seller
mart.dim_date
```

`mart.dim_customer` is additionally enriched with the Stage 1 RFM metrics and segment.

---

# SQL Files

```text
stage_create.sql
core_create.sql
data_to_core.sql
mart_create.sql
core_to_mart.sql
reset_stage.sql
elt_delta_scd1_scd2.sql
```

## Initial load order

Run the SQL scripts manually in the following order:

```text
1. stage_create.sql
2. core_create.sql
3. data_to_core.sql
4. mart_create.sql
5. core_to_mart.sql
```

`stage_create.sql` creates the schemas / Stage tables and loads:

```text
/initial_load.csv
/olist_rfm_segmentation.csv
```

---

## Delta load order

After the initial load has been completed:

```text
1. reset_stage.sql
2. elt_delta_scd1_scd2.sql
3. core_to_mart.sql
```

`reset_stage.sql` performs:

```sql
TRUNCATE TABLE stage.raw_orders;
```

and loads:

```text
/delta_load.csv
```

The incremental script then updates the Core layer, handles SCD logic and inserts new records.

Finally, `core_to_mart.sql` propagates the updated warehouse data into the Mart.

---

# Docker

PostgreSQL runs in Docker.

Docker is used only to place the generated CSV files inside the PostgreSQL container. SQL scripts are executed manually in the database client.

First check the PostgreSQL container name:

```bash
docker ps
```

Copy the generated files into the container:

```bash
docker cp initial_load.csv <postgres_container>:/initial_load.csv
docker cp delta_load.csv <postgres_container>:/delta_load.csv
docker cp olist_rfm_segmentation.csv <postgres_container>:/olist_rfm_segmentation.csv
```

The SQL scripts use these paths:

```text
/initial_load.csv
/delta_load.csv
/olist_rfm_segmentation.csv
```

Because PostgreSQL `COPY` reads from the database server filesystem, these files must exist inside the PostgreSQL container before the related SQL scripts are executed.

---

# Stage 3 — Power BI

Main file:

```text
Innowise_Project_Stage3.pbix
```

Power BI connects to the reporting-ready Mart layer.

The final report contains four main pages.

## KPI Overview

Strategic overview containing:

- KPI cards,
- monthly trend,
- state-level summary,
- date filtering,
- metric navigation / selection.

## Map

Geographical and category analysis containing:

- **Revenue by Location**,
- **Top 5 Category Revenue**,
- **Revenue vs Freight Cost**.

## RFM

Customer segmentation analysis containing:

- **Revenue by RFM Segment**,
- customer-segment summary,
- customer distribution by segment,
- **Revenue per Customer by Segment**.

## Operations

Operational delivery monitoring containing:

- delivery KPI cards,
- **Delivery Bottlenecks by Region**,
- **Delivery Time Distribution**,
- **Delayed Orders Trend**.

The report also contains supporting tooltip pages and an `Order_Details` page.

Navigation and date filtering are available throughout the report.

---

# Suggested Project Structure

```text
Project/
|
|-- Stage 1/
|   |-- stage1_new.ipynb
|   |-- olist_cleaned_dataset_ground_truth.csv
|   |-- olist_rfm_segmentation.csv
|   `-- Brazilian_Ecomerce_report_final.html
|
|-- Stage 2/
|   |-- stage2_new.ipynb
|   |
|   |-- sql/
|   |   |-- stage_create.sql
|   |   |-- core_create.sql
|   |   |-- data_to_core.sql
|   |   |-- mart_create.sql
|   |   |-- core_to_mart.sql
|   |   |-- reset_stage.sql
|   |   `-- elt_delta_scd1_scd2.sql
|   |
|   |-- diagrams/
|   |   |-- FlowChart.png
|   |   |-- Core_erd.png
|   |   `-- Mart_erd.png
|   |
|   |-- initial_load.csv
|   `-- delta_load.csv
|
|-- Stage 3/
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
stage1_new.ipynb
```

This produces the cleaned reference dataset, Sweetviz report and RFM segmentation.

## 3. Run Stage 2 notebook

Execute:

```text
stage2_new.ipynb
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
core_create.sql
data_to_core.sql
mart_create.sql
core_to_mart.sql
```

## 6. Process the simulated incremental load

Run manually:

```text
reset_stage.sql
elt_delta_scd1_scd2.sql
core_to_mart.sql
```

## 7. Open Power BI

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
