BEGIN;

INSERT INTO mart.dim_date (
    date_id,
    full_date,
    year,
    quarter,
    month,
    month_name,
    year_month,
    day,
    day_of_week
)
SELECT
    TO_CHAR(datum, 'YYYYMMDD')::INT AS date_id,
    datum AS full_date,
    EXTRACT(YEAR FROM datum)::INT AS year,
    EXTRACT(QUARTER FROM datum)::INT AS quarter,
    EXTRACT(MONTH FROM datum)::INT AS month,
    TO_CHAR(datum, 'FMMonth') AS month_name,
    TO_CHAR(datum, 'YYYY-MM') AS year_month,
    EXTRACT(DAY FROM datum)::INT AS day,
    TO_CHAR(datum, 'FMDay') AS day_of_week
FROM (
    SELECT generate_series(
        '2016-01-01'::DATE,
        '2025-12-31'::DATE,
        '1 day'::INTERVAL
    )::DATE AS datum
) d

ON CONFLICT (date_id) DO NOTHING;


INSERT INTO mart.dim_seller (
    seller_id
)
select seller_id
FROM core.sellers
ON CONFLICT (seller_id) DO NOTHING;


INSERT INTO mart.dim_product (
    product_id,
    category_name,
    weight_g,
    photos_qty
)
SELECT
    p.product_id,
    pc.product_category_name_english,
    p.product_weight_g,
    p.product_photos_qty

FROM core.products p

LEFT JOIN core.product_categories pc
    ON p.product_category_name =
       pc.product_category_name

ON CONFLICT (product_id) DO UPDATE SET
    category_name = EXCLUDED.category_name,
    weight_g = EXCLUDED.weight_g,
    photos_qty = EXCLUDED.photos_qty

WHERE ROW(
    mart.dim_product.category_name,
    mart.dim_product.weight_g,
    mart.dim_product.photos_qty
)
IS DISTINCT FROM ROW(
    EXCLUDED.category_name,
    EXCLUDED.weight_g,
    EXCLUDED.photos_qty
);


INSERT INTO mart.dim_customer (
    customer_sk,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state,
    customer_region,
    valid_from,
    valid_to,
    is_current,
    recency,
    frequency,
    monetary,
    m_score,
    r_score,
    f_score,
    segment
)
SELECT
    c.customer_sk,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,

    CASE
        WHEN c.customer_state IN (
            'AC', 'AP', 'AM', 'PA', 'RO', 'RR', 'TO'
        )
            THEN 'North'

        WHEN c.customer_state IN (
            'AL', 'BA', 'CE', 'MA', 'PB',
            'PE', 'PI', 'RN', 'SE'
        )
            THEN 'Northeast'

        WHEN c.customer_state IN (
            'DF', 'GO', 'MT', 'MS'
        )
            THEN 'Central-West'

        WHEN c.customer_state IN (
            'ES', 'MG', 'RJ', 'SP'
        )
            THEN 'Southeast'

        WHEN c.customer_state IN (
            'PR', 'RS', 'SC'
        )
            THEN 'South'

        ELSE NULL
    END AS customer_region,

    c.valid_from,
    c.valid_to,
    c.is_current,

    CASE WHEN c.is_current THEN r.recency END,
    CASE WHEN c.is_current THEN r.frequency END,
    CASE WHEN c.is_current THEN r.monetary END,
    CASE WHEN c.is_current THEN r.m_score END,
    CASE WHEN c.is_current THEN r.r_score END,
    CASE WHEN c.is_current THEN r.f_score END,
    CASE WHEN c.is_current THEN r.segment END

FROM core.customers c

LEFT JOIN stage.rfm_temp r
    ON c.customer_unique_id = r.customer_unique_id
   AND c.is_current = TRUE

ON CONFLICT (customer_sk) DO UPDATE SET
    customer_unique_id = EXCLUDED.customer_unique_id,
    customer_zip_code_prefix =EXCLUDED.customer_zip_code_prefix,
    customer_city = EXCLUDED.customer_city,
    customer_state = EXCLUDED.customer_state,
    customer_region = EXCLUDED.customer_region,
    valid_from = EXCLUDED.valid_from,
    valid_to = EXCLUDED.valid_to,
    is_current = EXCLUDED.is_current,
    recency = EXCLUDED.recency,
    frequency = EXCLUDED.frequency,
    monetary = EXCLUDED.monetary,
    m_score = EXCLUDED.m_score,
    r_score = EXCLUDED.r_score,
    f_score = EXCLUDED.f_score,
    segment = EXCLUDED.segment;


CREATE TEMP TABLE tmp_fact_sales
ON COMMIT DROP
AS

SELECT
    o.order_id,
    oi.order_item_id,
    c.customer_sk,
    oi.product_id,
    oi.seller_id,

    CASE
        WHEN o.order_purchase_timestamp IS NOT NULL
        THEN TO_CHAR(
            o.order_purchase_timestamp,
            'YYYYMMDD'
        )::INT
    END AS order_date_id,

    CASE
        WHEN o.order_approved_at IS NOT NULL
        THEN TO_CHAR(
            o.order_approved_at,
            'YYYYMMDD'
        )::INT
    END AS approved_date_id,

    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
        THEN TO_CHAR(
            o.order_delivered_carrier_date,
            'YYYYMMDD'
        )::INT
    END AS delivered_carrier_date_id,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN TO_CHAR(
            o.order_delivered_customer_date,
            'YYYYMMDD'
        )::INT
    END AS delivered_customer_date_id,

    CASE
        WHEN o.order_estimated_delivery_date IS NOT NULL
        THEN TO_CHAR(
            o.order_estimated_delivery_date,
            'YYYYMMDD'
        )::INT
    END AS estimated_delivery_date_id,

    o.order_status,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value
        AS total_value,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_purchase_timestamp IS NOT NULL
        THEN
            o.order_delivered_customer_date::DATE - o.order_purchase_timestamp::DATE
    END AS delivery_days,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN
            o.order_delivered_customer_date::DATE - o.order_estimated_delivery_date::DATE
    END AS delay_days,

    CASE
        WHEN o.order_delivered_customer_date IS NULL
          OR o.order_estimated_delivery_date IS NULL
        THEN NULL

        WHEN o.order_delivered_customer_date::DATE > o.order_estimated_delivery_date::DATE
        THEN 1
        ELSE 0
    END AS delayed_flag


FROM core.order_items oi

JOIN core.orders o
    ON oi.order_id = o.order_id

LEFT JOIN core.customers c
    ON c.customer_unique_id = o.customer_unique_id
   AND o.order_purchase_timestamp >=
       c.valid_from
   AND o.order_purchase_timestamp <
       c.valid_to;


DO $$
DECLARE
    missing_customer_versions INT;
BEGIN

    SELECT COUNT(*)
    INTO missing_customer_versions
    FROM tmp_fact_sales
    WHERE customer_sk IS NULL;

    IF missing_customer_versions > 0 THEN

        RAISE EXCEPTION
            'Fact load rejected: % rows have no valid temporal customer version',
            missing_customer_versions;

    END IF;

END $$;


INSERT INTO mart.fact_sales (
    order_id,
    order_item_id,
    customer_sk,
    product_id,
    seller_id,
    order_date_id,
    approved_date_id,
    delivered_carrier_date_id,
    delivered_customer_date_id,
    estimated_delivery_date_id,
    order_status,
    price,
    freight_value,
    total_value,
    delivery_days,
    delay_days,
    delayed_flag
)

SELECT
    order_id,
    order_item_id,
    customer_sk,
    product_id,
    seller_id,
    order_date_id,
    approved_date_id,
    delivered_carrier_date_id,
    delivered_customer_date_id,
    estimated_delivery_date_id,
    order_status,
    price,
    freight_value,
    total_value,
    delivery_days,
    delay_days,
    delayed_flag
FROM tmp_fact_sales

ON CONFLICT (
    order_id,
    order_item_id
)
DO UPDATE SET

    order_status = EXCLUDED.order_status,
    price = EXCLUDED.price,
    freight_value = EXCLUDED.freight_value,
    total_value = EXCLUDED.total_value,
    delivery_days = EXCLUDED.delivery_days,
    delay_days = EXCLUDED.delay_days,
    delayed_flag = EXCLUDED.delayed_flag

WHERE ROW(
    mart.fact_sales.order_status,
    mart.fact_sales.price,
    mart.fact_sales.freight_value,
    mart.fact_sales.total_value,
    mart.fact_sales.delivery_days,
    mart.fact_sales.delay_days,
    mart.fact_sales.delayed_flag
)

IS DISTINCT FROM ROW(
    EXCLUDED.order_status,
    EXCLUDED.price,
    EXCLUDED.freight_value,
    EXCLUDED.total_value,
    EXCLUDED.delivery_days,
    EXCLUDED.delay_days,
    EXCLUDED.delayed_flag
);


COMMIT;