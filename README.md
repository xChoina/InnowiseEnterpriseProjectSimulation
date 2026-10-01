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
Stage 3 requirements / BRD
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
stage2.ipynb
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
data_to_stage.sql
core_create.sql
data_to_core.sql
mart_create.sql
data_to_mart.sql
reset_stage.sql
delta_load.sql
```

The SQL files are intentionally separated by responsibility:

- `stage_create.sql` — creates the Stage schemas and Stage tables.
- `data_to_stage.sql` — loads the initial dataset and the RFM segmentation into Stage.
- `core_create.sql` — creates the normalized Core tables.
- `data_to_core.sql` — loads the initial Stage data into Core.
- `mart_create.sql` — creates the reporting Star Schema.
- `data_to_mart.sql` — loads / refreshes Mart dimensions and the fact table from Core.
- `reset_stage.sql` — clears `stage.raw_orders` and loads the simulated delta batch.
- `delta_load.sql` — applies the incremental-load, deduplication, SCD Type 1 and SCD Type 2 logic to Core.

## Initial load order

Run the SQL scripts manually in the following order:

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

At the end of the initial process, the historical dataset is available in:

```text
Stage -> Core -> Mart
```

---

## Delta load order

After the initial load has been completed, run:

```text
1. reset_stage.sql
2. delta_load.sql
3. data_to_mart.sql
```

`reset_stage.sql` replaces the previous Stage batch:

```sql
TRUNCATE TABLE stage.raw_orders;

COPY stage.raw_orders
FROM '/delta_load.csv'
DELIMITER ','
CSV HEADER;
```

`stage.rfm_temp` is intentionally preserved because the Stage 1 RFM segmentation is reused when the customer dimension is loaded into the Mart.

`delta_load.sql` then processes the delta batch and demonstrates:

- insertion of new records,
- duplicate handling / idempotency,
- SCD Type 1 overwrite logic,
- SCD Type 2 customer-history logic.

Finally:

```text
data_to_mart.sql
```

is executed again so the reporting layer receives the updated Core data.

---


# Docker

PostgreSQL runs inside Docker.

Docker is used only to make the generated CSV files available inside the PostgreSQL container. The SQL scripts themselves are executed manually in the database client.

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

The SQL scripts expect the following paths inside the PostgreSQL container:

```text
/initial_load.csv
/delta_load.csv
/olist_rfm_segmentation.csv
```

Because PostgreSQL `COPY` reads files from the database-server filesystem, these CSV files must exist inside the container before the related SQL scripts are executed.

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
|   |   |-- FlowChart.png
|   |   |-- Core_erd.png
|   |   `-- Mart_erd.png
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
