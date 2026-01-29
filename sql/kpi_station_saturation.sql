-- station saturée == dock =0 ou fill_rate >=0.9
CREATE OR REPLACE VIEW kpi_station_saturation AS
SELECT
  ingested_ts,
  station_id,
  name,
  arrondissement,
  bikes_i AS bikes,
  docks_i AS docks,
  fill_rate,
  CASE
    WHEN docks_i = 0 THEN 'DOCKS_0'
    WHEN fill_rate >= 0.9 THEN 'FILLRATE_>=_0.9'
    ELSE 'OK'
  END AS saturation_reason
FROM source_velib
WHERE is_installed_i = 1
  AND ingested_ts IS NOT NULL
  AND (docks_i = 0 OR fill_rate >= 0.9)
ORDER BY ingested_ts DESC;
