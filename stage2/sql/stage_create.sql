create schema if not exists stage;
create schema if not exists core;
create schema if not exists mart;

drop table if exists stage.raw_orders cascade;
create table stage.raw_orders(
    order_id VARCHAR,
    order_item_id INT,
    product_id VARCHAR,
    seller_id VARCHAR,
    shipping_limit_date TIMESTAMP,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    customer_id VARCHAR,
    order_status VARCHAR,
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP,
    customer_unique_id VARCHAR,
    customer_zip_code_prefix VARCHAR,
    customer_city VARCHAR,
    customer_state VARCHAR,
    product_category_name VARCHAR,
    product_name_lenght NUMERIC,        
    product_description_lenght NUMERIC,  
    product_photos_qty NUMERIC,          
    product_weight_g DECIMAL(10,2),
    product_length_cm DECIMAL(10,2),
    product_height_cm DECIMAL(10,2),
    product_width_cm DECIMAL(10,2),
    product_category_name_english VARCHAR
);

drop table if exists stage.rfm_temp cascade;
create table stage.rfm_temp (
    customer_unique_id VARCHAR PRIMARY KEY,
    recency INT,
    frequency INT,
    monetary DECIMAL(10,2),
    m_score INT,
    r_score INT,
    f_score INT,
    segment VARCHAR
);

-- Od razu ładujemy dane z kontenera
COPY stage.raw_orders FROM '/initial_load.csv' DELIMITER ',' CSV HEADER;
COPY stage.rfm_temp FROM '/olist_rfm_segmentation.csv' DELIMITER ',' CSV HEADER;