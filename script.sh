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

RA_SHOW_ID=""
RA_SHOW_LIVE=""

while true
do
RA_SHOW_OLD=$RA_SHOW_ID_PLANNED
RA_LIVE_OLD=$RA_SHOW_LIVE_PLANNED
RAOGG_LISTENERS=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg").listeners'`
RAMP3_LISTENERS=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/ramp3").listeners'`
RA_LISTENERS=$(expr $RAOGG_LISTENERS + $RAMP3_LISTENERS)

RA_SHOW_ID=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .id" | sed 's/\"//g'`
RA_SHOW_ID_PLANNED=$RA_SHOW_ID
RA_SHOW_LIVE=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .live" | sed 's/\"//g'`
RA_SHOW_LIVE_PLANNED=$RA_SHOW_LIVE
RA_SHOW_NAME=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .name" | sed 's/\"//g'`

RA_SHOW_ID=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .id" | sed 's/\"//g'`
RA_SHOW_ID_PLANNED=$RA_SHOW_ID
RA_SHOW_LIVE=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .live" | sed 's/\"//g'`
RA_SHOW_LIVE_PLANNED=$RA_SHOW_LIVE
RA_SHOW_NAME=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .name" | sed 's/\"//g'`

RA_SHOW_PREVIOUS_ID=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.endHour*60+.endMinutes <= $(expr $(date +%H) \* 60 + $(date +%M))) | .id" | sed 's/\"//g'`
RA_SHOW_PREVIOUS_ID_PLANNED=$RA_SHOW_PREVIOUS_ID
RA_SHOW_PREVIOUS_LIVE=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .live" | sed 's/\"//g'`
RA_SHOW_PREVIOUS_LIVE_PLANNED=$RA_SHOW_PREVIOUS_LIVE
RA_SHOW_PREVIOUS_NAME=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .name" | sed 's/\"//g'`

RA_TAG=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg") | if .artist == "" or .artist == null then .title else .artist + " - "  + .title end' | sed 's/\"//g'`
RA_TAG_COMPRESSED=`echo ${RA_TAG,,} | sed -e 's/[ |'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g' | cut -b -5`
RA_SHOW_NAME_COMPRESSED=`echo ${RA_SHOW_NAME,,} | sed -e 's/[ |'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g' | cut -b -5`

if [[ "$RA_TAG_COMPRESSED" != "$RA_SHOW_NAME_COMPRESSED" ]]; then
  RA_SHOW_ID="playlista"
  RA_SHOW_LIVE="false"
fi

if [ -z "$RA_SHOW_ID" ]; then
  RA_SHOW_ID="playlista"
  RA_SHOW_LIVE="false"
fi

if [ -z "$RA_SHOW_ID_PLANNED" ]; then
  RA_SHOW_ID_PLANNED="playlista"
  RA_SHOW_LIVE_PLANNED="false"
fi

echo $(date) ${RA_SHOW_OLD,,} ${RA_SHOW_ID_PLANNED,,}
if [[ "${RA_SHOW_OLD,,}" != "${RA_SHOW_ID_PLANNED,,}" && "${RA_SHOW_OLD,,}" != "playlista" ]]; then
  NOW_WEEKDAY=`date +%w`
  SHOW_WEEKDAY=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.id==\"$RA_SHOW_OLD\") | select(.live==${RA_LIVE_OLD}) | .weekDay"`
  if [ "$NOW_WEEKDAY" != "$SHOW_WEEKDAY" ]; then
    case $SHOW_WEEKDAY in
      0 )
        RA_SHOW_DATE=`date -d "Last Sunday" +%Y-%m-%d`
        ;;
      1 )
        RA_SHOW_DATE=`date -d "Last Monday" +%Y-%m-%d`
        ;;
      2 )
        RA_SHOW_DATE=`date -d "Last Tuesday" +%Y-%m-%d`
        ;;
      3 )
        RA_SHOW_DATE=`date -d "Last Wednesday" +%Y-%m-%d`
        ;;
      4 )
        RA_SHOW_DATE=`date -d "Last Thursday" +%Y-%m-%d`
        ;;
      5 )
        RA_SHOW_DATE=`date -d "Last Friday" +%Y-%m-%d`
        ;;
      6 )
        RA_SHOW_DATE=`date -d "Last Saturday" +%Y-%m-%d`
        ;;
    esac
  else
    RA_SHOW_DATE=`date +%Y-%m-%d`
  fi
  echo "/stats/pdf-generation.sh --show-code $RA_SHOW_OLD --show-date $RA_SHOW_DATE --show-live $RA_LIVE_OLD &"
  /stats/pdf-generation.sh --show-code $RA_SHOW_OLD --show-date $RA_SHOW_DATE --show-live $RA_LIVE_OLD &
fi

DATE_IN_NANOS=$(date +%s)

influx write \
    -b ra-stats \
    -o RadioAktywne \
    -p s \
    'listeners,show='${RA_SHOW_ID}',live='${RA_SHOW_LIVE}' listeners='${RA_LISTENERS}' '$DATE_IN_NANOS

sleep 10

done