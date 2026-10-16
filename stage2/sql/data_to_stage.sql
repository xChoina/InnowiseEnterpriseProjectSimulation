TRUNCATE TABLE stage.raw_orders;
TRUNCATE TABLE stage.rfm_temp;

COPY stage.raw_orders
FROM '/initial_load.csv'
DELIMITER ','
CSV HEADER;

COPY stage.rfm_temp
FROM '/olist_rfm_segmentation.csv'
DELIMITER ','
CSV HEADER;
