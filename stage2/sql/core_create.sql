CREATE SCHEMA IF NOT EXISTS core;

CREATE TABLE IF NOT EXISTS core.customers (
    customer_sk SERIAL PRIMARY KEY,
    customer_unique_id VARCHAR NOT NULL,
    customer_zip_code_prefix VARCHAR,
    customer_city VARCHAR,
    customer_state VARCHAR,
    valid_from TIMESTAMP NOT NULL,
    valid_to TIMESTAMP NOT NULL,
    is_current BOOLEAN NOT NULL,

    CONSTRAINT chk_customer_validity
        CHECK (valid_to > valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_core_customers_version
    ON core.customers (
        customer_unique_id,
        valid_from
    );

CREATE UNIQUE INDEX IF NOT EXISTS ux_core_customers_current
    ON core.customers (customer_unique_id)
    WHERE is_current = TRUE;


CREATE TABLE IF NOT EXISTS core.sellers (
    seller_id VARCHAR PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS core.product_categories (
    product_category_name VARCHAR PRIMARY KEY,
    product_category_name_english VARCHAR
);

CREATE TABLE IF NOT EXISTS core.products (
    product_id VARCHAR PRIMARY KEY,
    product_category_name VARCHAR,
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g DECIMAL(10,2),
    product_length_cm DECIMAL(10,2),
    product_height_cm DECIMAL(10,2),
    product_width_cm DECIMAL(10,2),

    FOREIGN KEY (product_category_name)
        REFERENCES core.product_categories(product_category_name)
);


CREATE TABLE IF NOT EXISTS core.orders (
    order_id VARCHAR PRIMARY KEY,
    customer_unique_id VARCHAR NOT NULL,
    order_status VARCHAR,
    order_purchase_timestamp TIMESTAMP NOT NULL,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);


CREATE INDEX IF NOT EXISTS idx_core_orders_customer_date
    ON core.orders (
        customer_unique_id,
        order_purchase_timestamp
    );


CREATE TABLE IF NOT EXISTS core.order_items (
    order_id VARCHAR,
    order_item_id INT,
    product_id VARCHAR,
    seller_id VARCHAR,
    shipping_limit_date TIMESTAMP,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),

    PRIMARY KEY (
        order_id,
        order_item_id
    ),

    FOREIGN KEY (order_id)
        REFERENCES core.orders(order_id),

    FOREIGN KEY (product_id)
        REFERENCES core.products(product_id),

    FOREIGN KEY (seller_id)
        REFERENCES core.sellers(seller_id),

    CONSTRAINT chk_order_item_price
        CHECK (price IS NULL OR price >= 0),

    CONSTRAINT chk_order_item_freight
        CHECK (freight_value IS NULL OR freight_value >= 0)
);