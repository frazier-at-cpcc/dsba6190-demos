-- Thirty nights of the store_sales load against a 99 per cent SLO.
-- The dashboard refreshes at 06:00 in Charlotte, so a minute after 06:00
-- without last night's data is a bad minute. Thirty days hold 43,200 minutes,
-- and 1 per cent of them, 432 minutes, is the error budget.
WITH nights AS (
  SELECT sale_date, state, rows_loaded,
         GREATEST(0, DATETIME_DIFF(finished_at,
                  DATETIME(DATE_ADD(sale_date, INTERVAL 1 DAY), TIME '06:00:00'), MINUTE)) AS late_min,
         IFNULL(DATETIME_DIFF(corrected_at,
                  GREATEST(finished_at, DATETIME(DATE_ADD(sale_date, INTERVAL 1 DAY), TIME '06:00:00')),
                  MINUTE), 0) AS wrong_min
  FROM `@@DS@@.load_runs`),
measured AS (
  SELECT 'job DONE by 06:00' AS sli, COUNTIF(state = 'DONE') AS done, SUM(late_min) AS bad_min FROM nights
  UNION ALL
  SELECT 'data fresh and complete', COUNTIF(state = 'DONE'), SUM(late_min + wrong_min) FROM nights)
SELECT sli, done AS nights_done, bad_min,
       30 * 1440 * 0.01 AS budget_min,
       ROUND(100 * (1 - bad_min / (30 * 1440)), 2) AS sli_pct,
       ROUND(100 * bad_min / (30 * 1440 * 0.01), 1) AS budget_used_pct
FROM measured
ORDER BY bad_min
