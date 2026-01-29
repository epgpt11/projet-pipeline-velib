CREATE OR REPLACE VIEW velib_station_flat AS
SELECT
  -- metadata
  s.source,
  s.ingested_at,           
  s.record_count,
  s.date,
  s.hour,

  -- station fields
  r.stationcode AS station_id,
  r.name,
  r.is_installed,
  r.is_renting,
  r.is_returning,

  -- availability
  CAST(r.numbikesavailable AS integer) AS bikes,
  CAST(r.numdocksavailable AS integer) AS docks,
  CAST(r.mechanical AS integer) AS mechanical,
  CAST(r.ebike AS integer) AS ebike,

  -- due date: 
  r.duedate AS due_date,

  -- geo
  CAST(r.coordonnees_geo.lon AS double) AS lon,
  CAST(r.coordonnees_geo.lat AS double) AS lat,

  -- location fields
  r.nom_arrondissement_communes AS arrondissement,
  r.code_insee_commune,
  r.station_opening_hours

FROM source_velib s
CROSS JOIN UNNEST(s.results) AS t(r);
