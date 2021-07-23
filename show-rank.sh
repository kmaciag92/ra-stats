#!/bin/bash

INFLUX_ORGANIZATION=RadioAktywne
INFLUX_TOKEN= #FILL

curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket: "ra-stats-per-show")
  |> range(start: -duration(v: 365d))
  |> filter(fn: (r) =>
    r._field == "mean"
    )
  |> group(columns: ["_show"])
  |> sort(desc: true)
  |> unique(column: "show")
  |> keep(columns: ["_time", "show", "_value", "live"])'