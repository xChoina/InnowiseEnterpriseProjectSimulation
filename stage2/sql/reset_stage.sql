BEGIN;

TRUNCATE TABLE stage.raw_orders;


COMMIT;

COPY stage.raw_orders
FROM '/delta_load.csv'
DELIMITER ','
CSV HEADER;
