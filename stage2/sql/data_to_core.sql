INSERT INTO core.sellers (
    seller_id
)
SELECT DISTINCT
    seller_id
FROM stage.raw_orders
WHERE seller_id IS NOT NULL

ON CONFLICT (seller_id)
DO NOTHING;


INSERT INTO core.product_categories (
    product_category_name,
    product_category_name_english
)
SELECT DISTINCT ON (product_category_name)
    product_category_name,
    product_category_name_english
FROM stage.raw_orders
WHERE product_category_name IS NOT NULL
ORDER by product_category_name, order_purchase_timestamp DESC NULLS LAST, order_id DESC
ON CONFLICT (product_category_name)
DO NOTHING;


INSERT INTO core.products (
    product_id,
    product_category_name,
    product_name_lenght,
    product_description_lenght,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT DISTINCT ON (product_id)
    product_id,
    product_category_name,
    product_name_lenght::INT,
    product_description_lenght::INT,
    product_photos_qty::INT,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM stage.raw_orders
WHERE product_id IS NOT NULL
ORDER by product_id, order_purchase_timestamp DESC NULLS LAST, order_id DESC
ON CONFLICT (product_id)
DO NOTHING;

WITH customer_events AS (

    SELECT DISTINCT ON (
        customer_unique_id,
        order_purchase_timestamp
    )
        customer_unique_id,
        order_id,
        order_purchase_timestamp AS event_timestamp,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    FROM stage.raw_orders
    WHERE customer_unique_id IS NOT NULL
      AND order_purchase_timestamp IS NOT NULL
    ORDER by customer_unique_id, order_purchase_timestamp, order_id DESC
),

ordered_events AS (

    select *,
		ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY event_timestamp, order_id
        ) AS rn,
        LAG(customer_zip_code_prefix) OVER (
            PARTITION BY customer_unique_id
            ORDER BY event_timestamp, order_id
        ) AS previous_zip,
        LAG(customer_city) OVER (
            PARTITION BY customer_unique_id
            ORDER BY event_timestamp, order_id
        ) AS previous_city,
       LAG(customer_state) OVER (
            PARTITION BY customer_unique_id
            ORDER BY event_timestamp, order_id
        ) AS previous_state
    FROM customer_events
),


changes AS (
    SELECT
        customer_unique_id,
        order_id,
        event_timestamp,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    FROM ordered_events
    where rn = 1
		OR customer_zip_code_prefix IS DISTINCT FROM previous_zip
        OR customer_city IS DISTINCT FROM previous_city
        OR customer_state IS DISTINCT FROM previous_state
),
versions AS (
    SELECT
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state,
        event_timestamp AS valid_from,
        LEAD(event_timestamp) OVER (
            PARTITION BY customer_unique_id
            ORDER BY event_timestamp, order_id
        ) AS next_valid_from
    FROM changes
)

INSERT INTO core.customers (
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state,
    valid_from,
    valid_to,
    is_current
)
SELECT
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state,
    valid_from,
    COALESCE(
        next_valid_from,
        '9999-12-31 23:59:59'::TIMESTAMP
    ),
    next_valid_from IS NULL
FROM versions
ON CONFLICT (
    customer_unique_id,
    valid_from
)
DO NOTHING;


INSERT INTO core.orders (
    order_id,
    customer_unique_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)
SELECT DISTINCT ON (order_id)
    order_id,
    customer_unique_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM stage.raw_orders
WHERE order_id IS NOT NULL
ORDER BY
    order_id,
    order_purchase_timestamp DESC NULLS LAST
ON CONFLICT (order_id)
DO NOTHING;


INSERT INTO core.order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT DISTINCT ON (
    order_id,
    order_item_id
)
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
FROM stage.raw_orders
WHERE order_id IS NOT NULL
  AND order_item_id IS NOT NULL
ORDER BY
    order_id,
    order_item_id,
    order_purchase_timestamp DESC NULLS LAST

ON CONFLICT (
    order_id,
    order_item_id
)
DO NOTHING;