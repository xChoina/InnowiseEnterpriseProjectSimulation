CREATE SCHEMA IF NOT EXISTS mart;


CREATE TABLE IF NOT EXISTS mart.dim_customer (
    customer_sk INT PRIMARY KEY,
    customer_unique_id VARCHAR NOT NULL,
    customer_zip_code_prefix VARCHAR,
    customer_city VARCHAR,
    customer_state VARCHAR,
    customer_region VARCHAR,
    valid_from TIMESTAMP NOT NULL,
    valid_to TIMESTAMP NOT NULL,
    is_current BOOLEAN NOT NULL,
    recency INT,
    frequency INT,
    monetary DECIMAL(10,2),
    m_score INT,
    r_score INT,
    f_score INT,
    segment VARCHAR
);

CREATE TABLE IF NOT EXISTS mart.dim_product (
    product_id VARCHAR PRIMARY KEY,
    category_name VARCHAR,
    weight_g DECIMAL(10,2),
    photos_qty INT
);

CREATE TABLE IF NOT EXISTS mart.dim_seller (
    seller_id VARCHAR PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS mart.dim_date (
    date_id INT PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    year INT,
    quarter INT,
    month INT,
    month_name VARCHAR,
    year_month VARCHAR,
    day INT,
    day_of_week VARCHAR
);


CREATE TABLE IF NOT EXISTS mart.fact_sales (
    order_id VARCHAR,
    order_item_id INT,
    customer_sk INT,
    product_id VARCHAR,
    seller_id VARCHAR,
    order_date_id INT,
    approved_date_id INT,
    delivered_carrier_date_id INT,
    delivered_customer_date_id INT,
    estimated_delivery_date_id INT,
    order_status VARCHAR,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    total_value DECIMAL(10,2),
    delivery_days INT,
    delay_days INT,
    delayed_flag INT,
    PRIMARY KEY (
        order_id,
        order_item_id
    ),

    FOREIGN KEY (customer_sk)
        REFERENCES mart.dim_customer(customer_sk),

    FOREIGN KEY (product_id)
        REFERENCES mart.dim_product(product_id),

    FOREIGN KEY (seller_id)
        REFERENCES mart.dim_seller(seller_id),

    FOREIGN KEY (order_date_id)
        REFERENCES mart.dim_date(date_id),

    FOREIGN KEY (approved_date_id)
        REFERENCES mart.dim_date(date_id),

    FOREIGN KEY (delivered_carrier_date_id)
        REFERENCES mart.dim_date(date_id),

    FOREIGN KEY (delivered_customer_date_id)
        REFERENCES mart.dim_date(date_id),

    FOREIGN KEY (estimated_delivery_date_id)
        REFERENCES mart.dim_date(date_id),

    CONSTRAINT chk_fact_delayed_flag
        CHECK (
            delayed_flag IS NULL
            OR delayed_flag IN (0, 1)
        )
);