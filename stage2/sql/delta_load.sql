begin;
INSERT INTO core.sellers (seller_id)
SELECT DISTINCT seller_id
FROM stage.raw_orders
WHERE seller_id IS NOT NULL
ON CONFLICT (seller_id) DO NOTHING;


INSERT INTO core.product_categories (
    product_category_name,
    product_category_name_english
)
SELECT DISTINCT ON (product_category_name)
    product_category_name,
    product_category_name_english
FROM stage.raw_orders
WHERE product_category_name IS NOT NULL
ORDER BY
    product_category_name,
    order_purchase_timestamp DESC

ON CONFLICT (product_category_name) DO UPDATE SET
    product_category_name_english =
        EXCLUDED.product_category_name_english;

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
ORDER BY
    product_id,
    order_purchase_timestamp DESC

ON CONFLICT (product_id) DO UPDATE SET
    product_category_name = EXCLUDED.product_category_name,
    product_name_lenght = EXCLUDED.product_name_lenght,
    product_description_lenght = EXCLUDED.product_description_lenght,
    product_photos_qty = EXCLUDED.product_photos_qty,
    product_weight_g = EXCLUDED.product_weight_g,
    product_length_cm = EXCLUDED.product_length_cm,
    product_height_cm = EXCLUDED.product_height_cm,
    product_width_cm = EXCLUDED.product_width_cm;


CREATE TEMP TABLE tmp_customer_changes
ON COMMIT DROP
AS

WITH current_customer AS (
    SELECT DISTINCT ON (customer_unique_id)
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state,
        valid_from
    FROM core.customers
    WHERE is_current = TRUE
    ORDER BY
        customer_unique_id,
        valid_from DESC,
        customer_sk DESC
),

events AS (
    SELECT DISTINCT
        s.customer_unique_id,
        s.order_id,
        s.order_purchase_timestamp AS event_timestamp,
        s.customer_zip_code_prefix,
        s.customer_city,
        s.customer_state,
        c.customer_unique_id AS existing_customer,
        c.customer_zip_code_prefix AS current_zip,
        c.customer_city AS current_city,
        c.customer_state AS current_state

    FROM stage.raw_orders s
    LEFT JOIN current_customer c
        ON s.customer_unique_id = c.customer_unique_id
    WHERE s.customer_unique_id IS NOT NULL
      AND s.order_purchase_timestamp IS NOT NULL
      AND (
          c.customer_unique_id IS NULL
          OR s.order_purchase_timestamp > c.valid_from
      )
),

ordered AS (
    SELECT
        *,

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

    FROM events
),

changes AS (
    SELECT
        customer_unique_id,
        order_id,
        event_timestamp,
        customer_zip_code_prefix,
        customer_city,
        customer_state

    FROM ordered

    WHERE
        (
            rn = 1
            AND existing_customer IS NULL
        )

        OR

        (
            rn = 1
            AND existing_customer IS NOT NULL
            AND (
                customer_zip_code_prefix IS DISTINCT FROM current_zip
                OR customer_city IS DISTINCT FROM current_city
                OR customer_state IS DISTINCT FROM current_state
            )
        )

        OR

        (
            rn > 1
            AND (
                customer_zip_code_prefix IS DISTINCT FROM previous_zip
                OR customer_city IS DISTINCT FROM previous_city
                OR customer_state IS DISTINCT FROM previous_state
            )
        )
)

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

FROM changes;

UPDATE core.customers c
SET
    valid_to = x.first_change,
    is_current = FALSE
FROM (
    SELECT
        customer_unique_id,
        MIN(valid_from) AS first_change
    FROM tmp_customer_changes
    GROUP BY customer_unique_id
) x
WHERE c.customer_unique_id = x.customer_unique_id
  AND c.is_current = TRUE
  AND c.valid_from < x.first_change;

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
    ) AS valid_to,

    next_valid_from IS NULL AS is_current

FROM tmp_customer_changes t

WHERE NOT EXISTS (
    SELECT 1
    FROM core.customers c
    WHERE c.customer_unique_id = t.customer_unique_id
      AND c.valid_from = t.valid_from
);


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
    order_purchase_timestamp DESC

ON CONFLICT (order_id) DO UPDATE SET
    order_status = EXCLUDED.order_status,
    order_approved_at = EXCLUDED.order_approved_at,
    order_delivered_carrier_date =
        EXCLUDED.order_delivered_carrier_date,
    order_delivered_customer_date =
        EXCLUDED.order_delivered_customer_date,
    order_estimated_delivery_date =
        EXCLUDED.order_estimated_delivery_date

WHERE ROW(
    core.orders.order_status,
    core.orders.order_approved_at,
    core.orders.order_delivered_carrier_date,
    core.orders.order_delivered_customer_date,
    core.orders.order_estimated_delivery_date
)
IS DISTINCT FROM ROW(
    EXCLUDED.order_status,
    EXCLUDED.order_approved_at,
    EXCLUDED.order_delivered_carrier_date,
    EXCLUDED.order_delivered_customer_date,
    EXCLUDED.order_estimated_delivery_date
);

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
    order_purchase_timestamp DESC

ON CONFLICT (
    order_id,
    order_item_id
) DO NOTHING;
commit;
