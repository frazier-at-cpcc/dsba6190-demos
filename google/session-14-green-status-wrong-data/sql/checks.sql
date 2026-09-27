-- Four data checks on last night's partition of store_sales. One row each.
-- "Last night" is yesterday in Charlotte, which is when the dashboard expects it.
WITH daily AS (
  SELECT sale_date,
         COUNT(*) AS n,
         COUNTIF(basket_value IS NULL) / COUNT(*) AS null_rate,
         AVG(basket_value) AS mean_basket
  FROM `@@DS@@.store_sales`
  WHERE sale_date BETWEEN DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 8 DAY)
                      AND DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY)
  GROUP BY sale_date),
last_night AS (
  SELECT IFNULL(MAX(n), 0) AS n, MAX(null_rate) AS null_rate, MAX(mean_basket) AS mean_basket
  FROM daily WHERE sale_date = DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY)),
trailing AS (
  SELECT AVG(n) AS n, AVG(null_rate) AS null_rate, AVG(mean_basket) AS mean_basket
  FROM daily WHERE sale_date < DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY)),
freshness AS (
  SELECT MAX(PARSE_DATE('%Y%m%d', partition_id)) AS newest,
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_modified_time), HOUR) AS hours_old
  FROM `@@DS@@.INFORMATION_SCHEMA.PARTITIONS`
  WHERE table_name = 'store_sales' AND total_rows > 0 AND STARTS_WITH(partition_id, '2')),
contract AS (
  SELECT * FROM UNNEST([
    STRUCT('sale_date' AS column_name, 'DATE' AS data_type),
    ('store_id', 'STRING'), ('region', 'STRING'), ('neighborhood', 'STRING'),
    ('register_id', 'STRING'), ('basket_id', 'STRING'), ('items', 'INT64'),
    ('basket_value', 'FLOAT64'), ('payment_type', 'STRING')])),
actual AS (
  SELECT column_name, data_type FROM `@@DS@@.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'store_sales'),
drift AS (
  SELECT STRING_AGG(CASE WHEN a.column_name IS NULL THEN 'missing ' || c.column_name
                         WHEN c.column_name IS NULL THEN 'extra ' || a.column_name
                         WHEN a.data_type != c.data_type THEN 'type ' || a.column_name END, ', ') AS diff
  FROM contract AS c FULL JOIN actual AS a ON a.column_name = c.column_name)

SELECT signal, observed, expected, status FROM (
  SELECT 1 AS ord, 'freshness' AS signal,
         FORMAT('newest %t, %d h old', newest, hours_old) AS observed,
         'yesterday, < 26 h' AS expected,
         IF(newest >= DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 1 DAY) AND hours_old < 26,
            'GREEN', 'RED') AS status
  FROM freshness
  UNION ALL
  SELECT 2, 'volume',
         FORMAT('%d rows, %.0f%% of 7-day mean', l.n, 100 * l.n / t.n),
         '80 to 120%',
         IF(l.n / t.n BETWEEN 0.8 AND 1.2, 'GREEN', 'RED')
  FROM last_night AS l, trailing AS t
  UNION ALL
  SELECT 3, 'schema', IFNULL(diff, 'matches contract'), '9 columns, typed', IF(diff IS NULL, 'GREEN', 'RED')
  FROM drift
  UNION ALL
  SELECT 4, 'distribution',
         FORMAT('null %.1f%%, mean $%.2f', 100 * IFNULL(l.null_rate, 0), IFNULL(l.mean_basket, 0)),
         FORMAT('null < %.1f%%, $%.2f ± 10%%', 100 * t.null_rate + 1, t.mean_basket),
         IF(IFNULL(l.null_rate, 1) < t.null_rate + 0.01
            AND ABS(SAFE_DIVIDE(l.mean_basket, t.mean_basket) - 1) <= 0.10, 'GREEN', 'RED')
  FROM last_night AS l, trailing AS t)
ORDER BY ord
