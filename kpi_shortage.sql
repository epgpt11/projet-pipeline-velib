
-- shortage ==> bikes=0
SELECT
  ingested_ts,
  station_id,
  name,
  arrondissement,
  bikes_i AS bikes,
  docks_i AS docks,
  fill_rate
FROM velib_station_typed
WHERE is_installed_i = 1
  AND ingested_ts IS NOT NULL
  AND bikes_i = 0
ORDER BY ingested_ts DESC;
