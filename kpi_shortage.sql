
-- shortage ==> bikes=0
CREATE OR REPLACE VIEW kpi_shortage AS
SELECT
  ingested_ts,
  station_id,
  name,
  arrondissement,
  bikes_i AS bikes,
  docks_i AS docks,
  fill_rate
FROM source_velib
WHERE is_installed_i = 1
  AND ingested_ts IS NOT NULL
  AND bikes_i = 0
ORDER BY ingested_ts DESC;
