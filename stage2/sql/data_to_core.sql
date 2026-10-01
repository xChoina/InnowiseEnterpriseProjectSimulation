INSERT INTO core.sellers (seller_id)
SELECT DISTINCT seller_id
FROM stage.raw_orders
WHERE seller_id IS NOT NULL;

INSERT INTO core.products (
    product_id, product_category_name, product_category_name_english,
    product_name_lenght, product_description_lenght, product_photos_qty,
    product_weight_g, product_length_cm, product_height_cm, product_width_cm
)
SELECT DISTINCT ON (product_id)
    product_id, product_category_name, product_category_name_english,
    product_name_lenght::INT,       
    product_description_lenght::INT, 
    product_photos_qty::INT,         
    product_weight_g, product_length_cm, product_height_cm, product_width_cm
FROM stage.raw_orders
WHERE product_id IS NOT NULL;

INSERT INTO core.customers (
    customer_unique_id, customer_zip_code_prefix, customer_city, customer_state,
    valid_from, valid_to, is_current
)
SELECT DISTINCT ON (customer_unique_id)
    customer_unique_id, customer_zip_code_prefix, customer_city, customer_state,
    '1900-01-01 00:00:00'::TIMESTAMP AS valid_from,
    '9999-12-31 23:59:59'::TIMESTAMP AS valid_to,
    TRUE AS is_current
FROM stage.raw_orders
WHERE customer_unique_id IS NOT NULL;

INSERT INTO core.orders (
    order_id, customer_unique_id, order_status, order_purchase_timestamp,
    order_approved_at, order_delivered_carrier_date,
    order_delivered_customer_date, order_estimated_delivery_date
)
SELECT DISTINCT ON (order_id)
    order_id, customer_unique_id, order_status, order_purchase_timestamp,
    order_approved_at, order_delivered_carrier_date,
    order_delivered_customer_date, order_estimated_delivery_date
FROM stage.raw_orders
WHERE order_id IS NOT NULL;

INSERT INTO core.order_items (
    order_id, order_item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value
)
SELECT DISTINCT ON (order_id, order_item_id)
    order_id, order_item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value
FROM stage.raw_orders
WHERE order_id IS NOT NULL AND order_item_id IS NOT NULL;