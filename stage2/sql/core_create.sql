DROP TABLE IF EXISTS core.order_items CASCADE;
DROP TABLE IF EXISTS core.orders CASCADE;
DROP TABLE IF EXISTS core.customers CASCADE;
DROP TABLE IF EXISTS core.sellers CASCADE;
DROP TABLE IF EXISTS core.products CASCADE;

CREATE TABLE core.customers (
    customer_sk SERIAL PRIMARY KEY,
    customer_unique_id VARCHAR,
    customer_zip_code_prefix VARCHAR,
    customer_city VARCHAR,
    customer_state VARCHAR,
    valid_from TIMESTAMP,
    valid_to TIMESTAMP,
    is_current BOOLEAN
);

CREATE TABLE core.sellers (
    seller_id VARCHAR PRIMARY KEY
);

CREATE TABLE core.products (
    product_id VARCHAR PRIMARY KEY,
    product_category_name VARCHAR,
    product_category_name_english VARCHAR,
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g DECIMAL(10,2),
    product_length_cm DECIMAL(10,2),
    product_height_cm DECIMAL(10,2),
    product_width_cm DECIMAL(10,2)
);

CREATE TABLE core.orders (
    order_id VARCHAR PRIMARY KEY,
    customer_unique_id VARCHAR,
    order_status VARCHAR,
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE core.order_items (
    order_id VARCHAR,
    order_item_id INT,
    product_id VARCHAR,
    seller_id VARCHAR,
    shipping_limit_date TIMESTAMP,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id) REFERENCES core.orders(order_id),
    FOREIGN KEY (product_id) REFERENCES core.products(product_id),
    FOREIGN KEY (seller_id) REFERENCES core.sellers(seller_id)
);