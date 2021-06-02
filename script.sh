#!/bin/bash

influx_health=`curl localhost:8086`
status=$?

while [[ $status -ne 0 ]]
do
    echo "Waiting for influx starting at port 8086"
    sleep 15
    influx_health=`curl localhost:8086`
    status=$?
done

influx setup -f \
  -o RadioAktywne \
  -u ra-stats \
  -p $RASSWORD \
  -t $INFLUX_TOKEN \
  -b ra-stats

influx config create --config-name ra-stats \
  --host-url http://localhost:8086 \
  --org RadioAktywne \
  --token $INFLUX_TOKEN \
  --active

RA_SHOW=""

while true
do
RA_SHOW_OLD=$RA_SHOW_ID
RAOGG_LISTENERS=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg").listeners'`
RAMP3_LISTENERS=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/ramp3").listeners'`
RA_LISTENERS=$(expr $RAOGG_LISTENERS + $RAMP3_LISTENERS)

RA_SHOW_ID=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .id" | sed 's/\"//g'`
RA_SHOW_LIVE=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .live" | sed 's/\"//g'`
RA_SHOW_NAME=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .name" | sed 's/\"//g'`

RA_TAG=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg") | if .artist == "" or .artist == null then .title else .artist + " - "  + .title end' | sed 's/\"//g'`

if [[ "$RA_TAG" != *"$RA_SHOW_NAME"* ]]; then
  RA_SHOW_ID="playlista"
fi

if [ -z "$RA_SHOW_ID" ]; then
  RA_SHOW_ID="playlista"
fi

if [ "$RA_SHOW_OLD" -ne "$RA_SHOW_ID" ]; then
  /stats/pdf-generation.sh & #dodaj parametry
fi

DATE_IN_NANOS=$(date +%s)

influx write \
    -b ra-stats \
    -o RadioAktywne \
    -p s \
    'listeners,show='${RA_SHOW_ID}' live='${RA_LIVE}' listeners='${RA_LISTENERS}' '$DATE_IN_NANOS

sleep 10

done