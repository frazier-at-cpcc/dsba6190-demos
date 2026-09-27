-- =====================================================================
-- Session 7 · demonstration · make the cost visible
--
-- Run each query with the editor open so you can read the
-- "This query will process N when run" estimate BEFORE you run it.
-- The estimator is free; you never need to press Run at all.
--
-- Every figure below was measured on 15 August 2026 against
-- bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022
-- (36,256,539 rows, 6.97 GB). Re-verify them before you rely on them.
-- The public dataset gains a table most years.
--
--
-- The numbers ARE the demonstration. Note each one before moving on.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1.  SELECT *                                            → 6.97 GB
--     Start here so the rest has something to beat.
-- ---------------------------------------------------------------------
SELECT *
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;


-- ---------------------------------------------------------------------
-- 2.  SELECT * ... LIMIT 10                               → 6.97 GB
--     UNCHANGED. This is the one that surprises people.
--     LIMIT bounds the rows RETURNED, not the bytes SCANNED. Columnar
--     storage has already been read by the time LIMIT applies.
--     Predict the number before you run it.
-- ---------------------------------------------------------------------
SELECT *
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
LIMIT 10;


-- ---------------------------------------------------------------------
-- 3.  Three named columns                                 → 1.07 GB
--     6.5x less, for a one-line edit.
-- ---------------------------------------------------------------------
SELECT pickup_datetime, passenger_count, fare_amount
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;


-- ---------------------------------------------------------------------
-- 4.  One column, aggregated                              → 0.54 GB
--     Half again. The aggregate is free; the column choice is not.
-- ---------------------------------------------------------------------
SELECT AVG(fare_amount)
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;


-- ---------------------------------------------------------------------
-- 5.  COUNT(*)                                            → 0.00 GB
--     Free. BigQuery answers from table metadata without scanning.
--     DuckDB applies the same optimization to count(*) over Parquet.
-- ---------------------------------------------------------------------
SELECT COUNT(*)
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;


-- =====================================================================
-- Pruning: the wildcard table
--
-- tlc_yellow_trips_* spans 2011-2023, about 46 GB. _TABLE_SUFFIX is the
-- part of the table name the * matched, so filtering on it eliminates
-- whole tables at planning time.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 6.  Wildcard, filtered on _TABLE_SUFFIX                 → 1.07 GB
-- ---------------------------------------------------------------------
SELECT pickup_datetime, passenger_count, fare_amount
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_*`
WHERE _TABLE_SUFFIX = '2022';


-- ---------------------------------------------------------------------
-- 7.  Wildcard, filtered on the COLUMN instead           → 46.61 GB
--     *** THE KEY COMPARISON ***
--     43.5x more than query 6, and it returns EXACTLY THE SAME ROWS.
--
--     Put 6 and 7 side by side. Work out why before you read on.
--
--     The answer: _TABLE_SUFFIX is part of the table NAME, so the planner
--     can drop twelve tables before reading anything. pickup_datetime is
--     a COLUMN, so the planner must read every table to discover which
--     rows qualify. Semantically identical, architecturally opposite.
--
--     At $6.25/TiB that is about $0.28 a run versus $0.0065, and a
--     dashboard on a five-minute refresh turns that into roughly
--     $2,400 a month for the same answer.
-- ---------------------------------------------------------------------
SELECT pickup_datetime, passenger_count, fare_amount
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_*`
WHERE EXTRACT(YEAR FROM pickup_datetime) = 2022;


-- ---------------------------------------------------------------------
-- 8.  Show the execution details for query 3.
--     Run it, open Execution Details, and connect stages, slot time and
--     shuffle bytes to the Dremel model.
--     This is the only query in the demo you actually need to run.
-- ---------------------------------------------------------------------


-- =====================================================================
-- These three variants look as if they defeat pruning:
--
--   * CONCAT(_TABLE_SUFFIX, '') = '2022'
--   * CAST(_TABLE_SUFFIX AS INT64) = 2022
--   * _TABLE_SUFFIX LIKE '2022'
--
-- All three still prune (1.07 GB). BigQuery folds them at plan time.
-- They look like they should defeat pruning and they do not, which makes
-- them a confusing detour rather than a lesson. Query 7 is the honest
-- version because it is the mistake a real person actually makes.
-- =====================================================================
