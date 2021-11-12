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

#Tu rozpoczyna się pętla odpowiedzialna za rejestrację danych o słuchalności
while true
do
#Te sześć zmiennych są potrzebne do przechowywania audycji, która trwała w poprzedniej iteracji sprawdzania słuchalności. Na jej podstawie sprawdzamy, czy można już wygenerować raport
RA_SHOW_OLD=$RA_SHOW_ID
RA_LIVE_OLD=$RA_SHOW_LIVE
RA_TAG_OLD=$RA_TAG
RA_SHOW_REPLAY_OLD=$RA_SHOW_REPLAY
RA_SHOW_ID_AS_PLANNED_OLD=$RA_SHOW_ID_AS_PLANNED

RA_STREAM_DATA=`curl -sS https://${RA_ADDRESS}:8443/status-json.xsl`
PROGRAM_API_DATA=`curl ${API_ADDRESS}`

#RAOGG_LISTENERS to zmienna w której zapisujemy aktualną liczbę słuchaczy streamu "raogg" z icecasta, RAMP3_LISTENERS to zmienna w której zapisujemy aktualną liczbę słuchaczy streamu "ramp3" z icecasta, a RA_LISTENERS to suma tych dwóch zmiennych
RAOGG_LISTENERS=`echo $RA_STREAM_DATA | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg").listeners'`
RAMP3_LISTENERS=`echo $RA_STREAM_DATA | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/ramp3").listeners'`
RA_LISTENERS=$(expr $RAOGG_LISTENERS + $RAMP3_LISTENERS)

NEXT_SHOW_RDS=`echo ${PROGRAM_API_DATA} | jq '. | .[] ' | jq -s "sort_by(.weekday,.begin_h,.begin_m) | .[] | select((.weekday*24*60+.begin_h*60+.begin_m >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) and .weekday*24*60+.begin_h*60+.begin_m+.duration > $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)))  or .weekday*24*60+.begin_h*60+.begin_m+.duration >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M) + 7 \* 60 \* 24)) | .program.rds " | sed 's/\"//g' | head -1`
PREVIOUS_SHOW_RDS=`echo ${PROGRAM_API_DATA} | jq '. | .[] ' | jq -s "sort_by(.weekday,.begin_h,.begin_m) | .[] | select((.weekday*24*60+.begin_h*60+.begin_m <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M))) and .weekday*24*60+.begin_h*60+.begin_m+.duration <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) ) | .program.rds " | sed 's/\"//g' | tail -1`

#Poniższe zmienne to informacje o audycji pobrane z pliku ramowka.json, zmienne z "_PLANNED" są potrzebne do tego, żeby nie zostały nadpisane, gdy się okaże, że audycja się nie odbyła, albo potrwała krócej niż w planie. ID to kod audycji z docsa ramówkowego, REPLAY to flaga oznaczająca, czy audycja jest powtórką czy pierwszą emisją, a NAME to tytuł audycji z ramówki
RA_SHOW_ID=`echo ${PROGRAM_API_DATA} | jq ". | .[] | select((.weekday*24*60+.begin_h*60+.begin_m <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) and .weekday*24*60+.begin_h*60+.begin_m+.duration > $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)))  or .weekday*24*60+.begin_h*60+.begin_m+.duration >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M) + 7 \* 60 \* 24)) | .program.slug " | sed 's/\"//g'`
RA_SHOW_REPLAY=`echo ${PROGRAM_API_DATA} | jq ". | .[] | select((.weekday*24*60+.begin_h*60+.begin_m <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) and .weekday*24*60+.begin_h*60+.begin_m+.duration > $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)))  or .weekday*24*60+.begin_h*60+.begin_m+.duration >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M) + 7 \* 60  \* 24)) | .replay " | sed 's/\"//g'`
RA_SHOW_RDS=`echo ${PROGRAM_API_DATA} | jq ". | .[] | select((.weekday*24*60+.begin_h*60+.begin_m <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) and .weekday*24*60+.begin_h*60+.begin_m+.duration > $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)))  or .weekday*24*60+.begin_h*60+.begin_m+.duration >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M) + 7 \* 60 \* 24)) | .program.rds " | sed 's/\"//g'`

#Ta zmienna jest potrzebna, żeby zachować informację o tym jaka audycja powinna być teraz emitowana... RA_SHOW_ID potem może się zmienić, żeby poprawnie zaindeksować metrykę dla danej audycji w zależności od aktualnie emitowanego taga
RA_SHOW_ID_AS_PLANNED=$RA_SHOW_ID

#RA_TAG to pobrany z icecasta tag z audycji. Generalnie to jest to co wpisujemy w RDSa :) Niektórzy tagując puszki używają także taga "artist" razem z tagiem "title" i taki przypadek też jest przewidziany
RA_TAG=`echo $RA_STREAM_DATA | jq '.icestats.source | .[] | select(.listenurl=="http://'${RA_ADDRESS}':8000/raogg") | if .artist == "" or .artist == null then .title else .artist + " - "  + .title end' | sed 's/\"//g'`
#RA_TAG_COMPRESSED i #RA_SHOW_NAME_COMPRESSED to skrócone formy zmiennych RA_TAG i RA_SHOW_NAME. Porównywane są takie formy, gdyż RDS nie zawsze jest wypełniany z taką samą precyzją. Skrócenie tych zmiennych polega na tym, że zamieniamy wszystkie znaki na małe litery, kasujemy znaki jakie jak: spacja, przecinek, apostrof, #, | i myślnik
RA_TAG_COMPRESSED=`echo ${RA_TAG,,} | sed -e 's/[ |,|'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g'`
RA_SHOW_RDS_COMPRESSED=`echo ${RA_SHOW_RDS,,} | sed -e 's/[ |,|'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g' | cut -b -5`
NEXT_SHOW_RDS_COMPRESSED=`echo ${NEXT_SHOW_RDS,,} | sed -e 's/[ |,|'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g' | cut -b -5`
PREVIOUS_SHOW_RDS_COMPRESSED=`echo ${PREVIOUS_SHOW_RDS,,} | sed -e 's/[ |,|'"'"'|\#|\||\-]//g' | sed 's/ą/a/g' | sed 's/ę/e/g' | sed 's/ł/l/g' | sed 's/ń/n/g' | sed 's/ó/o/g' | sed 's/ś/s/g' | sed 's/[ż|ź]/z/g' | cut -b -5`

#To samo się stanie, jeśli wpis w RDSie nie będzie się zgadzał z tytułem audycji
if [[ "$RA_TAG_COMPRESSED" != *"$RA_SHOW_RDS_COMPRESSED"* ]]; then
  RA_SHOW_ID="playlista"
  RA_SHOW_REPLAY="true"
  if [[ "$RA_TAG_COMPRESSED" == *"$NEXT_SHOW_RDS_COMPRESSED"* ]]; then
    RA_SHOW_ID=`echo ${PROGRAM_API_DATA} | jq '. | .[] ' | jq -s "sort_by(.weekday,.begin_h,.begin_m) | .[] | select((.weekday*24*60+.begin_h*60+.begin_m >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) and .weekday*24*60+.begin_h*60+.begin_m+.duration > $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)))  or .weekday*24*60+.begin_h*60+.begin_m+.duration >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M) + 7 \* 60 \* 24)) | .program.slug " | sed 's/\"//g' | head -1`
    RA_SHOW_REPLAY=`echo ${PROGRAM_API_DATA} | jq '. | .[] ' | jq -s "sort_by(.weekday,.begin_h,.begin_m) | .[] | select((.weekday*24*60+.begin_h*60+.begin_m >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) and .weekday*24*60+.begin_h*60+.begin_m+.duration > $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)))  or .weekday*24*60+.begin_h*60+.begin_m+.duration >= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M) + 7 \* 60 \* 24)) | .replay " | sed 's/\"//g' | head -1`
  fi
  if [[ "$RA_TAG_COMPRESSED" == *"$PREVIOUS_SHOW_RDS_COMPRESSED"* ]]; then
    RA_SHOW_ID=`echo ${PROGRAM_API_DATA} | jq '. | .[] ' | jq -s "sort_by(.weekday,.begin_h,.begin_m) | .[] | select((.weekday*24*60+.begin_h*60+.begin_m <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M))) and .weekday*24*60+.begin_h*60+.begin_m+.duration <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) ) | .program.slug " | sed 's/\"//g' | tail -1`
    RA_SHOW_REPLAY=`echo ${PROGRAM_API_DATA} | jq '. | .[] ' | jq -s "sort_by(.weekday,.begin_h,.begin_m) | .[] | select((.weekday*24*60+.begin_h*60+.begin_m <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M))) and .weekday*24*60+.begin_h*60+.begin_m+.duration <= $(expr $(date +%u) \* 24 \* 60 + $(date +%H) \* 60 + $(date +%M)) ) | .replay " | sed 's/\"//g' | tail -1`
  fi
fi

#Przed dostosowaniem się do API ramówkowego RA używałem, zmiennej RA_SHOW_LIVE, która przyjmowała true jak audycja była na żywo, albo była puszką w nowym wydaniu w ramówce i false jak była powtórką. By nie rozkopywać całej logiki audycji postanowiłem zrobić prostą negację zmiennej RA_SHOW_REPLAY z API ramówkowego RA
if [[ "$RA_SHOW_REPLAY" == "false" ]]; then
  RA_SHOW_LIVE="true"
else
  RA_SHOW_LIVE="false"
fi

#RA_SHOW_ID_PLANNED=$RA_SHOW_ID
#RA_SHOW_LIVE_PLANNED=$RA_SHOW_LIVE
#RA_SHOW_ID=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .id" | sed 's/\"//g'`
#RA_SHOW_LIVE=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .live" | sed 's/\"//g'`
#RA_SHOW_NAME=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.weekDay==$(date +%w)) | select (.startHour*60+.startMinutes <= $(expr $(date +%H) \* 60 + $(date +%M)) and .endHour*60+.endMinutes > $(expr $(date +%H) \* 60 + $(date +%M))) | .name" | sed 's/\"//g'`

#Jeśli o danej porze nie jest zaplanowana żadna audycja, to wynik słuchalności zostanie przypisany playliście.
if [ -z "$RA_SHOW_ID" ]; then
  RA_SHOW_ID="playlista"
  RA_SHOW_LIVE="false"
  RA_SHOW_REPLAY="true"
  #RA_SHOW_ID_PLANNED="playlista"
  #RA_SHOW_LIVE_PLANNED="false"
fi

if [ -z "$RA_SHOW_ID_AS_PLANNED" ]; then
  RA_SHOW_ID_AS_PLANNED="playlista"
fi

echo $(date) "RA_TAG=$RA_TAG"
#echo $(date) "RA_TAG_COMPRESSED=$RA_TAG_COMPRESSED"
#echo $(date) "RA_SHOW_ID=$RA_SHOW_ID"
#echo $(date) "RA_SHOW_OLD=$RA_SHOW_OLD"
#echo $(date) "RA_SHOW_ID_AS_PLANNED=$RA_SHOW_ID_AS_PLANNED"
#echo $(date) "RA_SHOW_ID_AS_PLANNED_OLD=$RA_SHOW_ID_AS_PLANNED_OLD"
#echo $(date) "RA_SHOW_LIVE=$RA_SHOW_LIVE"
#echo $(date) "RA_SHOW_REPLAY=$RA_SHOW_REPLAY"
#echo $(date) "RA_SHOW_REPLAY_OLD=$RA_SHOW_REPLAY_OLD"
#echo $(date) "RA_SHOW_RDS=$RA_SHOW_RDS"
#echo $(date) "NEXT_SHOW_RDS=$NEXT_SHOW_RDS"
#echo $(date) "NEXT_SHOW_RDS_COMPRESSED=$NEXT_SHOW_RDS_COMPRESSED"
#echo $(date) "PREVIOUS_SHOW_RDS=$PREVIOUS_SHOW_RDS"

#Warunek sprawdzający czy planowany czas audycji się już skończył i czy można generować raport
if [[ "${RA_SHOW_OLD,,}" != "${RA_SHOW_ID,,}" || "${RA_SHOW_ID_AS_PLANNED,,}" != "${RA_SHOW_ID_AS_PLANNED_OLD,,}" ]]; then
  if [[ "${RA_SHOW_OLD,,}" != "playlista" && "${RA_SHOW_ID_AS_PLANNED_OLD,,}" != "playlista" ]]; then
    NOW_WEEKDAY=`date +%u`
    #SHOW_WEEKDAY=`cat /stats/ramowka.json | jq ".ramowka | .[] | select(.id==\"$RA_SHOW_OLD\") | select(.live==${RA_LIVE_OLD}) | .weekDay"`
    SHOW_WEEKDAY=`echo ${PROGRAM_API_DATA} | jq ". | .[] | select(.program.slug==\"$RA_SHOW_OLD\") | select(.replay==${RA_SHOW_REPLAY_OLD}) | .weekday"`
    #Jeśli audycja kończy się o godzinie 0:00 to trzeba dostosować datę
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
    #Tutaj uruchamiamy skrypt generujący raport
    echo "Tworzenie raportu słuchalności dla audycji $RA_SHOW_OLD dnia $RA_SHOW_DATE"
    /stats/pdf-generation.sh --show-code $RA_SHOW_OLD --show-date $RA_SHOW_DATE --show-live $RA_LIVE_OLD &
  fi
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
sleep 10

done