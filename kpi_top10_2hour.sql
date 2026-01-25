-- 10 stations en critique pour 2 dernieres heures

WITH recent AS (
  SELECT
    station_id,
    name,
    arrondissement,
    bikes_i,
    docks_i,
    fill_rate
  FROM velib_station_typed
  WHERE is_installed_i = 1
    AND ingested_ts >= date_add('hour', -2, current_timestamp)
    AND bikes_i IS NOT NULL
    AND docks_i IS NOT NULL
)
SELECT
  station_id,
  max(name) AS name,
  max(arrondissement) AS arrondissement,

  avg(fill_rate) AS avg_fill_rate,
  sum(CASE WHEN bikes_i = 0 THEN 1 ELSE 0 END) AS shortage_hits,
  sum(CASE WHEN docks_i = 0 THEN 1 ELSE 0 END) AS saturated_hits,
  sum(CASE WHEN fill_rate >= 0.9 THEN 1 ELSE 0 END) AS high_fill_hits,

  sum(CASE WHEN bikes_i = 0 THEN 2 ELSE 0 END)
+ sum(CASE WHEN docks_i = 0 THEN 2 ELSE 0 END)
+ sum(CASE WHEN fill_rate >= 0.9 THEN 1 ELSE 0 END) AS critical_score
FROM recent
GROUP BY station_id
ORDER BY critical_score DESC, shortage_hits DESC, saturated_hits DESC
LIMIT 10;
