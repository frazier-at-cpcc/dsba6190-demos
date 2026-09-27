-- =====================================================================
-- Session 7 · live demo — make the cost visible
--
-- Run each query with the editor open so the class can read the
-- "This query will process N when run" estimate BEFORE you run it.
-- The estimator is free; you never need to press Run at all.
--
-- Every figure below was measured on 15 August 2026 against
-- bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022
-- (36,256,539 rows, 6.97 GB). Re-verify before class — the public
-- dataset gains a table most years.
--
--
-- The numbers ARE the demo. Say each one out loud before moving on.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1.  SELECT *                                            → 6.97 GB
--     Start here so the rest has something to beat.
-- ---------------------------------------------------------------------
SELECT *
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`;


-- ---------------------------------------------------------------------
-- 2.  SELECT * ... LIMIT 10                               → 6.97 GB
--     UNCHANGED. This is the one that surprises people, so pause here.
--     LIMIT bounds the rows RETURNED, not the bytes SCANNED. Columnar
--     storage has already been read by the time LIMIT applies.
--     Ask the room to predict the number before you show it.
-- ---------------------------------------------------------------------
SELECT *
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
LIMIT 10;


-- ---------------------------------------------------------------------
-- 3.  Three named columns                                 → 1.07 GB
--     6.5x less, for a one-line edit. Say the ratio aloud.
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
--     Worth naming: DuckDB does exactly the same thing over Parquet in
--     A9 Part B — students measure count(*) at ~1 ms there. Two engines,
--     same optimization, one week apart.
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
--     *** THE MOMENT OF THE DEMO ***
--     43.5x more than query 6, and it returns EXACTLY THE SAME ROWS.
--
--     Put 6 and 7 side by side on screen. Ask why before you explain.
--
--     The answer: _TABLE_SUFFIX is part of the table NAME, so the planner
--     can drop twelve tables before reading anything. pickup_datetime is
--     a COLUMN, so the planner must read every table to discover which
--     rows qualify. Semantically identical, architecturally opposite.
--
--     At $6.25/TiB that is about $0.28 a run versus $0.0065 — and a
--     dashboard on a five-minute refresh turns that into roughly
--     $2,400 a month for the same answer.
-- ---------------------------------------------------------------------
SELECT pickup_datetime, passenger_count, fare_amount
FROM `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_*`
WHERE EXTRACT(YEAR FROM pickup_datetime) = 2022;


-- ---------------------------------------------------------------------
-- 8.  Show the execution details for query 3.
--     Run it, open Execution Details, and connect stages, slot time and
--     shuffle bytes back to the Dremel model from Hour 1.
--     This is the only query in the demo you actually need to run.
-- ---------------------------------------------------------------------


-- =====================================================================
-- Do NOT try to demo these three variants live:
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
