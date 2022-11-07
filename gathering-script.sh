#!/bin/bash
# To jest główny skrypt, który steruje całym kontenerem. Jego zadania to:
# - Sprawdzanie, jaka audycja jest teraz emitowana na antenie,
# - Sprawdzanie ile osób na chwilę obecną słucha naszego radia
# - Wysłanie tych informacji do bazy danych
# - Po zakończeniu emisji audycji - wywołanie skryptu tworzącego raport ze słuchalności audycji
# Skrypt jest uruchamiany na samym początku działania kontenera

#Najpierw sprawdzamy czy influx, który również jest na tym kontenerze jest już uruchomiony i gotowy do przyjmowania metryk
influx_health=`curl localhost:8086`
status=$?

while [[ $status -ne 0 ]]
do
    echo "Waiting for influx starting at port 8086"
    sleep 15
    influx_health=`curl localhost:8086`
    status=$?
done

#Gdy influx już jest uruchomiony konfigurujemy do niego dostęp, czyli tworzymy użytkownika "ra-stats" ze wszystkim znanym hasłem ;) a także główny bucket "ra-stats", trzeba także podać INFLUX_TOKEN, który jest dostarczony w pliku "secrets", który jest przesyłany poza githubem
influx setup -f \
  -o RadioAktywne \
  -u ra-stats \
  -p $RASSWORD \
  -t $INFLUX_TOKEN \
  -b ra-stats

#Potem tworzymy konfigurację, żeby nie trzeba było za każdym razem podawać INFLUX_TOKEN
influx config create --config-name ra-stats \
  --host-url http://localhost:8086 \
  --org RadioAktywne \
  --token $INFLUX_TOKEN \
  --active

START_SHOW_TIME_UTC=`date -d "-1 hour" +%Y-%m-%dT%TZ --utc`
#Tu rozpoczyna się pętla odpowiedzialna za rejestrację danych o słuchalności
while true
do
DATE_IN_SECONDS=$(date +%s)
#Te sześć zmiennych są potrzebne do przechowywania audycji, która trwała w poprzedniej iteracji sprawdzania słuchalności. Na jej podstawie sprawdzamy, czy można już wygenerować raport
RA_SHOW_OLD=$RA_SHOW_ID
RA_LIVE_OLD=$RA_SHOW_LIVE
RA_TAG_OLD=$RA_TAG
RA_SHOW_LIVE_OLD=$RA_SHOW_LIVE
RA_SHOW_ID_AS_PLANNED_OLD=$RA_SHOW_ID_AS_PLANNED

RA_STREAM_DATA=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl`
EMITER_API_DATA=`curl ${EMITER_API_ADDRESS}`

#RAOGG_LISTENERS to zmienna w której zapisujemy aktualną liczbę słuchaczy streamu "raogg" z icecasta, RAMP3_LISTENERS to zmienna w której zapisujemy aktualną liczbę słuchaczy streamu "ramp3" z icecasta, a RA_LISTENERS to suma tych dwóch zmiennych
RAOGG_LISTENERS=`echo $RA_STREAM_DATA | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg").listeners'`
RAMP3_LISTENERS=`echo $RA_STREAM_DATA | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/ramp3").listeners'`
RA_LISTENERS=$(expr $RAOGG_LISTENERS + $RAMP3_LISTENERS)

########################################################
RA_CODE=`echo ${EMITER_API_DATA} | jq .code | sed 's/\"//g'`
RA_SHOW_ID=`echo ${EMITER_API_DATA} | jq .program_code | sed 's/\"//g'`
RA_TAG=`echo ${EMITER_API_DATA} | jq 'if .artist == "" or .artist == null then .title else .artist + " - "  + .title end' | sed 's/\"//g'`
RA_SOURCE=`echo ${EMITER_API_DATA} | jq .source | sed 's/\"//g'`
RA_FILENAME=`echo ${EMITER_API_DATA} | jq .filename | sed 's/\"//g'`

if [[ "$RA_SOURCE" == "studio" ]]; then
    RA_SHOW_LIVE="true"
else
    if [[ "$RA_SOURCE" == "playout" ]]; then
        if [[ "$RA_FILENAME" == *"puszka"* && -z $RA_SHOW_ID  ]]; then
            tab=$(echo $RA_FILENAME | tr '(/|_|.)' '\n')
            RA_SHOW_ID=`echo "${tab}" | head -5 | tail -1`
            RA_SHOW_LIVE="rec"
        fi
        if [[ "$RA_FILENAME" == *"powtorka"* && -z $RA_SHOW_ID  ]]; then
            tab=$(echo $RA_FILENAME | tr '(/|_|.)' '\n')
            RA_SHOW_ID=`echo "${tab}" | head -5 | tail -1`
            RA_SHOW_LIVE="false"
        fi
    else 
        RA_SHOW_ID="playlista"
        RA_SHOW_LIVE="false"
    fi
fi

if [[ "$RA_SHOW_ID" == "custom" ]]; then
    RA_SHOW_LIVE="custom"
    RA_SHOW_ID=`echo ${RA_TAG,,} | sed -e 's/[ |,|'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g' | cut -b -5`
fi
########################################################

echo $(date) "RA_TAG=$RA_TAG"
echo $(date) "RA_SHOW_ID=$RA_SHOW_ID"
echo $(date) "RA_SHOW_LIVE=$RA_SHOW_LIVE"
echo $(date) "START_SHOW_TIME_UTC=$START_SHOW_TIME_UTC"
echo $(date) "END_SHOW_TIME_UTC=$END_SHOW_TIME_UTC"

#Warunek sprawdzający czy planowany czas audycji się już skończył i czy można generować raport
if [[ "${RA_SHOW_OLD,,}" != "${RA_SHOW_ID,,}"  && -n "${RA_SHOW_OLD,,}" ]]; then
  if [[ "${RA_SHOW_OLD,,}" != "playlista" && "${RA_SHOW_OLD,,}" != "unknown" ]]; then
    END_SHOW_TIME_UTC=`date +%Y-%m-%dT%TZ --utc`
    #Tutaj uruchamiamy skrypt generujący raport
    RA_SHOW_DATE=`date -d "$START_SHOW_TIME_UTC" +%Y-%m-%d`
    echo "Tworzenie raportu słuchalności dla audycji $RA_SHOW_OLD z dnia $RA_SHOW_DATE"
    if [[ "${RA_LIVE_OLD}" == "custom" ]]; then
      echo "/stats/report-generation.sh --show-code $RA_SHOW_OLD --show-start $START_SHOW_TIME_UTC --show-end $END_SHOW_TIME_UTC --show-live $RA_LIVE_OLD --show-title "${RA_TAG_OLD}" &"
      /stats/report-generation.sh --show-code $RA_SHOW_OLD --show-start $START_SHOW_TIME_UTC --show-end $END_SHOW_TIME_UTC --show-live $RA_LIVE_OLD --show-title "${RA_TAG_OLD}" &
      if [[ "${RA_SHOW_LIVE}" != "custom" ]]; then
        /stats/generate-custom-rank.sh
      fi
    else
      echo "/stats/report-generation.sh --show-code $RA_SHOW_OLD --show-start $START_SHOW_TIME_UTC --show-end $END_SHOW_TIME_UTC --show-live $RA_LIVE_OLD --show-title \"\""
      /stats/report-generation.sh --show-code $RA_SHOW_OLD --show-start $START_SHOW_TIME_UTC --show-end $END_SHOW_TIME_UTC --show-live $RA_LIVE_OLD --show-title ""
    fi
  fi
  START_SHOW_TIME_UTC=`date +%Y-%m-%dT%TZ --utc`
fi

#Aby wysłać odpowiednio oznaczoną metrykę słuchalności musimy wygenerować timestamp w formacie epoch liczonym w sekundach
DATE_IN_SECONDS=$(date +%s)

#Tutaj logujemy wysłane informacje do influxa i je faktycznie wysyłamy do bucketu ra-stats
echo 'listeners,show='${RA_SHOW_ID}',live='${RA_SHOW_LIVE}' listeners='${RA_LISTENERS}' '$(date)
influx write \
    -b ra-stats \
    -o RadioAktywne \
    -p s \
    'listeners,show='${RA_SHOW_ID}',live='${RA_SHOW_LIVE}' listeners='${RA_LISTENERS}' '$DATE_IN_SECONDS

#Tu można regulować jak często wysyłamy metrykę - ustawiłem co 10 sekund, ale nie może być rzadziej niż co minutę
sleep $GRANULATION

done