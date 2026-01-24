CREATE OR REPLACE VIEW velib_station_typed AS
SELECT
  try_cast(from_iso8601_timestamp(ingested_at) AS timestamp) AS ingested_ts,
  station_id,
  name,
  arrondissement,
  try_cast(is_installed AS integer) AS is_installed_i,
  try_cast(bikes AS integer) AS bikes_i,
  try_cast(docks AS integer) AS docks_i,
  try_cast(bikes AS double) / NULLIF(try_cast(bikes AS double) + try_cast(docks AS double), 0) AS fill_rate
FROM velib_station_flat;
