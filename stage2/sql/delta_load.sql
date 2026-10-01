INSERT INTO core.sellers (seller_id)
SELECT DISTINCT seller_id FROM stage.raw_orders WHERE seller_id IS NOT NULL
ON CONFLICT (seller_id) DO NOTHING;

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
WHERE product_id IS NOT NULL
ORDER BY product_id, order_purchase_timestamp DESC
ON CONFLICT (product_id) DO UPDATE SET
    product_category_name = EXCLUDED.product_category_name,
    product_category_name_english = EXCLUDED.product_category_name_english,
    product_weight_g = EXCLUDED.product_weight_g,
    product_length_cm = EXCLUDED.product_length_cm,
    product_height_cm = EXCLUDED.product_height_cm,
    product_width_cm = EXCLUDED.product_width_cm;



UPDATE core.customers c
SET valid_to = delta.min_order_date, is_current = FALSE
FROM (
    
    SELECT customer_unique_id, MIN(order_purchase_timestamp) AS min_order_date,
           MAX(customer_city) AS customer_city, 
           MAX(customer_state) AS customer_state, 
           MAX(customer_zip_code_prefix) AS customer_zip_code_prefix
    FROM stage.raw_orders
    GROUP BY customer_unique_id
) delta
WHERE c.customer_unique_id = delta.customer_unique_id
  AND c.is_current = TRUE
  AND (
       c.customer_city IS DISTINCT FROM delta.customer_city 
    OR c.customer_state IS DISTINCT FROM delta.customer_state 
    OR c.customer_zip_code_prefix IS DISTINCT FROM delta.customer_zip_code_prefix
  );


INSERT INTO core.customers (
    customer_unique_id, customer_zip_code_prefix, customer_city, customer_state,
    valid_from, valid_to, is_current
)
SELECT DISTINCT ON (customer_unique_id)
    customer_unique_id, customer_zip_code_prefix, customer_city, customer_state,
    order_purchase_timestamp AS valid_from,
    '9999-12-31 23:59:59'::TIMESTAMP AS valid_to,
    TRUE AS is_current
FROM stage.raw_orders s
WHERE customer_unique_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM core.customers c
      WHERE c.customer_unique_id = s.customer_unique_id
        AND c.is_current = TRUE
        AND c.customer_city IS NOT DISTINCT FROM s.customer_city
        AND c.customer_state IS NOT DISTINCT FROM s.customer_state
        AND c.customer_zip_code_prefix IS NOT DISTINCT FROM s.customer_zip_code_prefix
  )
ORDER BY customer_unique_id, order_purchase_timestamp DESC;


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
WHERE order_id IS NOT NULL
ORDER BY order_id, order_purchase_timestamp DESC
ON CONFLICT (order_id) DO UPDATE SET
    order_status = EXCLUDED.order_status,
    order_approved_at = EXCLUDED.order_approved_at,
    order_delivered_carrier_date = EXCLUDED.order_delivered_carrier_date,
    order_delivered_customer_date = EXCLUDED.order_delivered_customer_date;



INSERT INTO core.order_items (
    order_id, order_item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value
)
SELECT DISTINCT ON (order_id, order_item_id)
    order_id, order_item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value
FROM stage.raw_orders 
WHERE order_id IS NOT NULL AND order_item_id IS NOT NULL
ORDER BY order_id, order_item_id, order_purchase_timestamp DESC
ON CONFLICT (order_id, order_item_id) DO NOTHING;