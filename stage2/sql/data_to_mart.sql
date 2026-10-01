INSERT INTO mart.dim_date (date_id, full_date, year, month, day)
SELECT 
    TO_CHAR(datum, 'YYYYMMDD')::INT, datum, EXTRACT(YEAR FROM datum), 
    EXTRACT(MONTH FROM datum), EXTRACT(DAY FROM datum)
FROM (SELECT generate_series('2016-01-01'::DATE, '2025-12-31'::DATE, '1 day'::interval)::DATE AS datum) d
ON CONFLICT (date_id) DO NOTHING;

INSERT INTO mart.dim_seller (seller_id)
SELECT seller_id FROM core.sellers
ON CONFLICT (seller_id) DO NOTHING;

INSERT INTO mart.dim_product (product_id, category_name, weight_g, photos_qty)
SELECT 
    product_id, 
    COALESCE(product_category_name_english, 'Unknown Category'), 
    product_weight_g, 
    product_photos_qty 
FROM core.products
ON CONFLICT (product_id) DO UPDATE SET 
    category_name = EXCLUDED.category_name, 
    weight_g = EXCLUDED.weight_g, 
    photos_qty = EXCLUDED.photos_qty;

INSERT INTO mart.dim_customer (
    customer_sk, customer_unique_id, customer_zip_code_prefix, 
    customer_city, customer_state, is_current,
    recency, frequency, monetary, m_score, r_score, f_score, segment
)
SELECT 
    c.customer_sk, c.customer_unique_id, c.customer_zip_code_prefix, 
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        INITCAP(TRIM(c.customer_city)), 
        ' De ', ' de '), 
        ' Da ', ' da '), 
        ' Do ', ' do '), 
        ' Das ', ' das '), 
        ' Dos ', ' dos '), 
    UPPER(TRIM(c.customer_state)), 
    c.is_current,
    r.recency, r.frequency, r.monetary, r.m_score, r.r_score, r.f_score, 
    COALESCE(r.segment, 'New / Unsegmented')
FROM core.customers c
LEFT JOIN stage.rfm_temp r ON c.customer_unique_id = r.customer_unique_id
ON CONFLICT (customer_sk) DO UPDATE SET 
    is_current = EXCLUDED.is_current, 
    customer_city = EXCLUDED.customer_city, 
    customer_state = EXCLUDED.customer_state, 
    customer_zip_code_prefix = EXCLUDED.customer_zip_code_prefix,
    recency = EXCLUDED.recency,
    frequency = EXCLUDED.frequency,
    monetary = EXCLUDED.monetary,
    m_score = EXCLUDED.m_score,
    r_score = EXCLUDED.r_score,
    f_score = EXCLUDED.f_score,
    segment = EXCLUDED.segment;

INSERT INTO mart.fact_sales (
    order_id, order_item_id, customer_sk, product_id, seller_id,
    order_date_id, approved_date_id, delivered_carrier_date_id, 
    delivered_customer_date_id, estimated_delivery_date_id,
    order_status, price, freight_value, total_value
)
SELECT 
    oi.order_id, oi.order_item_id, c.customer_sk, oi.product_id, oi.seller_id,
    TO_CHAR(o.order_purchase_timestamp, 'YYYYMMDD')::INT,
    TO_CHAR(o.order_approved_at, 'YYYYMMDD')::INT,
    TO_CHAR(o.order_delivered_carrier_date, 'YYYYMMDD')::INT,
    TO_CHAR(o.order_delivered_customer_date, 'YYYYMMDD')::INT,
    TO_CHAR(o.order_estimated_delivery_date, 'YYYYMMDD')::INT,
    o.order_status, oi.price, oi.freight_value, (oi.price + oi.freight_value)
FROM core.order_items oi
JOIN core.orders o ON oi.order_id = o.order_id
JOIN core.customers c ON o.customer_unique_id = c.customer_unique_id 
  AND o.order_purchase_timestamp >= c.valid_from 
  AND o.order_purchase_timestamp < c.valid_to
ON CONFLICT (order_id, order_item_id) DO UPDATE SET 
    order_status = EXCLUDED.order_status, 
    customer_sk = EXCLUDED.customer_sk;