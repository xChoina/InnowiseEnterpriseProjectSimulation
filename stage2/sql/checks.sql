SELECT
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,
    c.valid_from,
    c.valid_to,
    c.is_current
FROM core.customers c
WHERE c.customer_unique_id = (
    SELECT cur.customer_unique_id
    FROM core.customers cur
    WHERE cur.is_current = TRUE
      AND cur.customer_state = 'RJ'
      AND cur.customer_city = 'rio de janeiro'
      AND cur.customer_zip_code_prefix = '20000'
      AND EXISTS (
          SELECT 1
          FROM core.customers old
          WHERE old.customer_unique_id = cur.customer_unique_id
            AND old.is_current = FALSE
            AND (
                old.customer_state IS DISTINCT FROM 'RJ'
                OR old.customer_city IS DISTINCT FROM 'rio de janeiro'
                OR old.customer_zip_code_prefix IS DISTINCT FROM '20000'
            )
      )
    LIMIT 1
)
ORDER BY c.valid_from;


-- SCD1 check: dimension attribute was overwritten

SELECT
    product_category_name,
    product_category_name_english
FROM core.product_categories
WHERE product_category_name = 'beleza_saude';


-- Row counts by layer

SELECT 'stage.raw_orders' AS table_name, COUNT(*) AS row_count
FROM stage.raw_orders

UNION ALL

SELECT 'stage.rfm_temp', COUNT(*)
FROM stage.rfm_temp

UNION ALL

SELECT 'core.customers', COUNT(*)
FROM core.customers

UNION ALL

SELECT 'core.sellers', COUNT(*)
FROM core.sellers

UNION ALL

SELECT 'core.product_categories', COUNT(*)
FROM core.product_categories

UNION ALL

SELECT 'core.products', COUNT(*)
FROM core.products

UNION ALL

SELECT 'core.orders', COUNT(*)
FROM core.orders

UNION ALL

SELECT 'core.order_items', COUNT(*)
FROM core.order_items

UNION ALL

SELECT 'mart.dim_customer', COUNT(*)
FROM mart.dim_customer

UNION ALL

SELECT 'mart.dim_product', COUNT(*)
FROM mart.dim_product

UNION ALL

SELECT 'mart.dim_seller', COUNT(*)
FROM mart.dim_seller

UNION ALL

SELECT 'mart.dim_date', COUNT(*)
FROM mart.dim_date

UNION ALL

SELECT 'mart.fact_sales', COUNT(*)
FROM mart.fact_sales;

-- Duplicate checks

-- Core: duplicate orders
SELECT
    order_id,
    COUNT(*) AS duplicate_count
FROM core.orders
GROUP BY order_id
HAVING COUNT(*) > 1;


-- Core: duplicate order items
SELECT
    order_id,
    order_item_id,
    COUNT(*) AS duplicate_count
FROM core.order_items
GROUP BY
    order_id,
    order_item_id
HAVING COUNT(*) > 1;


-- Core: duplicate customer versions
SELECT
    customer_unique_id,
    valid_from,
    COUNT(*) AS duplicate_count
FROM core.customers
GROUP BY
    customer_unique_id,
    valid_from
HAVING COUNT(*) > 1;


-- Core: more than one current customer version
SELECT
    customer_unique_id,
    COUNT(*) AS current_versions
FROM core.customers
WHERE is_current = TRUE
GROUP BY customer_unique_id
HAVING COUNT(*) > 1;


-- Mart: duplicate fact rows
SELECT
    order_id,
    order_item_id,
    COUNT(*) AS duplicate_count
FROM mart.fact_sales
GROUP BY
    order_id,
    order_item_id
HAVING COUNT(*) > 1;


-- Orphan key checks

-- Core order_items -> orders
SELECT COUNT(*) AS orphan_order_items_orders
FROM core.order_items oi
LEFT JOIN core.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;


-- Core order_items -> products
SELECT COUNT(*) AS orphan_order_items_products
FROM core.order_items oi
LEFT JOIN core.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


-- Core order_items -> sellers
SELECT COUNT(*) AS orphan_order_items_sellers
FROM core.order_items oi
LEFT JOIN core.sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


-- Mart fact -> customer
SELECT COUNT(*) AS orphan_fact_customer
FROM mart.fact_sales f
LEFT JOIN mart.dim_customer c
    ON f.customer_sk = c.customer_sk
WHERE c.customer_sk IS NULL;


-- Mart fact -> product
SELECT COUNT(*) AS orphan_fact_product
FROM mart.fact_sales f
LEFT JOIN mart.dim_product p
    ON f.product_id = p.product_id
WHERE p.product_id IS NULL;


-- Mart fact -> seller
SELECT COUNT(*) AS orphan_fact_seller
FROM mart.fact_sales f
LEFT JOIN mart.dim_seller s
    ON f.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- Revenue reconciliation

WITH core_totals AS (
    SELECT
        SUM(price) AS core_price,
        SUM(freight_value) AS core_freight,
        SUM(price + freight_value) AS core_total
    FROM core.order_items
),
mart_totals AS (
    SELECT
        SUM(price) AS mart_price,
        SUM(freight_value) AS mart_freight,
        SUM(total_value) AS mart_total
    FROM mart.fact_sales
)
SELECT
    core_price,
    mart_price,
    core_freight,
    mart_freight,
    core_total,
    mart_total,
    core_total - mart_total AS total_difference
FROM core_totals
CROSS JOIN mart_totals;
-- Mart fact -> order date
SELECT COUNT(*) AS orphan_fact_order_date
FROM mart.fact_sales f
LEFT JOIN mart.dim_date d
    ON f.order_date_id = d.date_id
WHERE d.date_id IS NULL;

SELECT
    (SELECT COUNT(*)
     FROM mart.dim_customer
     WHERE is_current = TRUE
       AND segment IS NULL) AS mart_null_segment,

    (SELECT COUNT(*)
     FROM core.customers c
     LEFT JOIN stage.rfm_temp r
         ON c.customer_unique_id = r.customer_unique_id
     WHERE c.is_current = TRUE
       AND r.customer_unique_id IS NULL) AS missing_in_rfm;
    
    
    SELECT
    LENGTH(customer_zip_code_prefix) AS zip_length,
    COUNT(*) AS row_count
FROM mart.dim_customer
WHERE customer_zip_code_prefix IS NOT NULL
GROUP BY LENGTH(customer_zip_code_prefix)
ORDER BY zip_length;

SELECT
    full_date,
    month_name,
    day_of_week
FROM mart.dim_date
WHERE full_date IN (
    '2024-01-15',
    '2024-02-20'
)
ORDER BY full_date;