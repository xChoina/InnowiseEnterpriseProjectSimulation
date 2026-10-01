TRUNCATE TABLE stage.raw_orders;
COPY stage.raw_orders FROM '/delta_load.csv' DELIMITER ',' CSV HEADER;

docker cp "C:\Users\Administrator\code\innowise\project_stage_2\initial_load.csv" olist_postgres:/initial_load.csv