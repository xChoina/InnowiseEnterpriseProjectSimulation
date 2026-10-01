TRUNCATE TABLE stage.raw_orders;

COPY stage.raw_orders
FROM '/delta_load.csv'
DELIMITER ','
CSV HEADER;
