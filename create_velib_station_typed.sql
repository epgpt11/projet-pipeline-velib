CREATE OR REPLACE VIEW velib_station_typed AS
SELECT
  try_cast(from_iso8601_timestamp(ingested_at) AS timestamp) AS ingested_ts,
  station_id,
  name,
  arrondissement,

  CASE
    -- if string
    WHEN upper(trim(is_installed)) = 'OUI' THEN 1
    WHEN upper(trim(is_installed)) = 'NON' THEN 0

    -- if boolean
    WHEN lower(trim(is_installed)) IN ('true', 't', 'yes', 'y') THEN 1
    WHEN lower(trim(is_installed)) IN ('false', 'f', 'no', 'n') THEN 0

    -- if number
    WHEN trim(is_installed) = '1' THEN 1
    WHEN trim(is_installed) = '0' THEN 0

    ELSE NULL
  END AS is_installed_i,

  try_cast(bikes AS integer) AS bikes_i,
  try_cast(docks AS integer) AS docks_i,

  try_cast(bikes AS double)
    / NULLIF(try_cast(bikes AS double) + try_cast(docks AS double), 0) AS fill_rate

FROM velib_station_flat;
