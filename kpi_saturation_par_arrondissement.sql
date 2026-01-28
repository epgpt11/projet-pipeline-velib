CREATE OR REPLACE VIEW kpi_saturation_par_arrondissement AS
SELECT
  arrondissement,
  count(*) AS station_rows,
  avg(fill_rate) AS avg_fill_rate,
  sum(CASE WHEN bikes_i = 0 THEN 1 ELSE 0 END) AS shortage_count,
  sum(CASE WHEN docks_i = 0 OR fill_rate >= 0.9 THEN 1 ELSE 0 END) AS saturation_count
FROM source_velib
WHERE is_installed_i = 1
  AND arrondissement IS NOT NULL
  AND ingested_ts IS NOT NULL
  AND bikes_i IS NOT NULL
  AND docks_i IS NOT NULL
GROUP BY arrondissement
ORDER BY shortage_count DESC, saturation_count DESC;
