
CREATE OR REPLACE VIEW kpi_taux_remplissage AS
SELECT
  ingested_ts,
  station_id,
  name,
  arrondissement,
  bikes_i AS bikes,
  docks_i AS docks,
  (bikes_i + docks_i) AS capacity_calc,
  fill_rate
FROM source_velib
WHERE is_installed_i = 1
  AND ingested_ts IS NOT NULL
  AND bikes_i IS NOT NULL
  AND docks_i IS NOT NULL;
