#!/bin/bash

#Instrukcja, która wyświetla się, gdy źle uruchomimy skrypt
usage()
{
  echo "musisz podać parametry audycji --show-code --show-start --show-end --show-live"   
}

#Pętla odpowiedzialna za odpowiednie ustawienie zmiennych odczytując parametry wejściowe
while [ "$1" != "" ]; do
  case $1 in
    -c | --show-code )        shift
                              export SHOW_CODE=$1
                              ;;
    -s | --show-start )       shift
                              export SHOW_START=$1
                              ;;
    -e | --show-end )         shift
                              export SHOW_END=$1
                              ;;
    -l | --show-live )        shift
                              export SHOW_LIVE=$1
                              ;;
    -t | --show-title )       shift
                              export SHOW_TITLE=$1
                              ;;
    * )                       usage
                              exit 1
  esac
  shift
done

#Tutaj ustawiamy stałe potrzebne w dalszej części skryptu
INFLUX_ORGANIZATION="RadioAktywne"
BUCKET_NAME="ra-stats"
BUCKET_NAME_FOR_RETENTION="ra-stats-per-show"
PROGRAM_API_DATA=`curl ${PROGRAM_API_ADDRESS}`


#Wprowadzamy zmienną SHOW_REPLAY, która jest negacją SHOW_LIVE, SHOW_LIVE jest używany w bazie do przypisywania "true" premierowym wydaniom audycji, za to SHOW_REPLAY w jsonie ramówkowym przyjmuje "true" gdy audycja jest powtórką
if [[ "$SHOW_LIVE" == "false" ]]; then
  SHOW_REPLAY="true"
else
  SHOW_REPLAY="false"
fi

START_TIME_IN_SECONDS=`date -d "$SHOW_START" +%s`
END_TIME_IN_SECONDS=`date -d "$SHOW_END" +%s`
DURATION_IN_SECONDS=`expr $END_TIME_IN_SECONDS - $START_TIME_IN_SECONDS`

if [[ $DURATION_IN_SECONDS -lt 600 ]]; then
  echo "Audycja $SHOW_CODE trwała krócej niż 10 minut - nie generuję raportu"
  exit 0
fi

#Tu pobieramy z jsona ramówkowego dane o audycji potrzebne do wygenerowania raportu
if [[ "$SHOW_LIVE" != "custom" ]]; then
  SHOW_TITLE=`echo ${PROGRAM_API_DATA} | jq '. | .[] | select(.program.slug=="'${SHOW_CODE}'") | select(.replay=='${SHOW_REPLAY}') | .program.name ' | head -1 | sed 's/\"//g'`
fi
START_HOUR=`echo ${PROGRAM_API_DATA} | jq '. | .[] | select(.program.slug=="'${SHOW_CODE}'") | select(.replay=='${SHOW_REPLAY}') | .begin_h ' | head -1 | sed 's/\"//g'`
START_MINUTES=`echo ${PROGRAM_API_DATA} | jq '. | .[] | select(.program.slug=="'${SHOW_CODE}'") | select(.replay=='${SHOW_REPLAY}') | .begin_m ' | head -1 | sed 's/\"//g'`

SHOW_DURATION=`echo ${PROGRAM_API_DATA} | jq '. | .[] | select(.program.slug=="'${SHOW_CODE}'") | select(.replay=='${SHOW_REPLAY}') | .duration' | head -1 | sed 's/\"//g'`

TIME_SHIFT=`echo $(date +%:::z | sed "s/\+0//g")`
TIME_ZONE=`echo $(date -d "$SHOW_START" +%Z)`

SHOW_START_TO_QUERY=`date -d "$SHOW_START - $SHOW_DURATION minutes" +%Y-%m-%dT%TZ --utc`
SHOW_END_TO_QUERY=`date -d "$SHOW_END + $SHOW_DURATION minutes" +%Y-%m-%dT%TZ --utc`

#W poniższych zmiennych MIN, MEAN i MAX wyliczamy opisane w nazwach statystyki słuchalności. 
#Stosujemy okno 24-godzinne, po to, żeby nie wygenerować dwóch wyników, z dwóch różnych okien, dlatego jest takie szerokie. 
#Dodajemy parametr TIME_SHIFT w funkcji timeShift(), po to by w wynikach wyświetlały się już prawidłowe godziny. 
#W MEAN użyłem funkcji map() po to, by uzyskany wynik pomnożyć przez 100, przekonwertować na liczbę całkowitą i podzielić przez 100, po to by wynik zawsze miał dwie cyfry po przecinku. 
#Funkcje użyte po pipach są po to, żeby wyłuskać ze zwróconego stringa sam wynik i zapisać go do zmiennej
MIN=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"'${BUCKET_NAME}'")
        |> range(start: '${SHOW_START_TO_QUERY}', stop: '${SHOW_END_TO_QUERY}')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> filter(fn: (r) => r.live == "'$SHOW_LIVE'", onEmpty: "drop")
        |> aggregateWindow(every: 48h, fn: min)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 5 | grep -v "_value" | head -n 1 | sed 's/\r//g'`

MEAN=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"'${BUCKET_NAME}'")
        |> range(start: '${SHOW_START_TO_QUERY}', stop: '${SHOW_END_TO_QUERY}')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> filter(fn: (r) => r.live == "'$SHOW_LIVE'", onEmpty: "drop")
        |> aggregateWindow(every: 48h, fn: mean)
        |> map(fn: (r) => ({
          r with
          _value: float(v: int(v: r._value * 100.0)) / 100.0
        }))
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 5 | grep -v "_value" | head -n 1 | sed 's/\r//g'`

MAX=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"'${BUCKET_NAME}'")
        |> range(start: '${SHOW_START_TO_QUERY}', stop: '${SHOW_END_TO_QUERY}')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> filter(fn: (r) => r.live == "'$SHOW_LIVE'", onEmpty: "drop")
        |> aggregateWindow(every: 48h, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 5 | grep -v "_value" | head -n 1 | sed 's/\r//g'`

#Tu na podobnej zasadzie generujemy tabelki wyników. 
#TABLE_TO_REPORT jest wykorzystywany do tabelki, którą prześlemy na końcu raportu, a TABLE_TO_GRAPH jest użyty do stworzenia wykresu, który również zostanie umieszczony w raporcie. 
#Różnią się tym, że ten pierwszy ma granulację co minutę, a ten drugi co 10 sekund.
TABLE_TO_REPORT=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"'${BUCKET_NAME}'")
        |> range(start: '${SHOW_START_TO_QUERY}', stop: '${SHOW_END_TO_QUERY}')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> filter(fn: (r) => r.live == "'$SHOW_LIVE'", onEmpty: "drop")
        |> aggregateWindow(every: 1m, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> group(columns: ["_time"])
        |> sort(columns: ["_time"], desc: false)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 4-5 | cut -d 'T' -f 2 | grep -v value | sed -En 's/Z//p' | sed -En 's/,/ /p' | sed 's/\r//g'`

TABLE_TO_GRAPH=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"'${BUCKET_NAME}'")
        |> range(start: '${SHOW_START_TO_QUERY}', stop: '${SHOW_END_TO_QUERY}')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> filter(fn: (r) => r.live == "'$SHOW_LIVE'", onEmpty: "drop")
        |> aggregateWindow(every: 10s, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> group(columns: ["_time"])
        |> sort(columns: ["_time"], desc: false)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 4-5 | grep -v value | sed -En 's/Z//p' | sed -En 's/,/ /p' | sed 's/\r//g'`

START_TIME_TO_GRAPH=`echo "$TABLE_TO_GRAPH" | head -1 | cut -d ' ' -f 1`
END_TIME_TO_GRAPH=`echo "$TABLE_TO_GRAPH" | tail -1 | cut -d ' ' -f 1`

SHOW_DATE=`date -d "$SHOW_START" +%Y-%m-%d`

# Jeśli tabela wyników jest pusta, bo wszystkie metryki zostały zapisane jako "playlista", to raport się nie wygeneruje
if [ -z "$TABLE_TO_GRAPH" ]; then
  echo "$SHOW_DATE - Audycja $SHOW_CODE się nie odbyła - nie generuję raportu"
  exit 0
fi

# To jest zmienna tworzona tylko po to, żeby zaznaczyć w raporcie, że dotyczy on słuchalności powtórki
if [ "$SHOW_LIVE" == "false" ]; then
  POWTORKI="powtórki "
else
  POWTORKI=""
  if [ "$SHOW_LIVE" == "custom" ]; then
    POWTORKI="audycji podczas specjalnej ramówki "
  fi
  if [ "$SHOW_LIVE" == "rec" ]; then
    POWTORKI="puszki "
  fi
fi

#Tu zaczynamy tworzenie pliku html, na podstawie, którego stworzony zostanie ostateczny raport w PDFie.
#W tej sekcji są ustawienia dotyczące stylu tego html, czyli rozmiaru czcionek i wyśrodkowania wszystkich elementów
#Ważny jest tag <meta>, bo dzięki niemu działają polskie znaki w raportach
#W tym miejscu jest generowana tabelka z wartościami MIN, MEAN i MAX
echo '<head><style>

.center {
  margin-left: auto;
  margin-right: auto;
}

table {
  font-family: arial;
  border-collapse: collapse;
}

h1, h2 {
  text-align: center;
  font-family: arial;
}

td, th {
    border: 1px solid #000000;
    text-align: center;
    padding: 8px;
    font-size: 30px;
  }
</style>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
</head>

<body>
<center><h1>'$SHOW_TITLE' - słuchalność '$POWTORKI'z dnia '$SHOW_DATE'</h1></center>
<table class="center">
  <tr>
    <th>Minimum</th>
    <th>Średnia</th>
    <th>Maximum</th>
  </tr>
  <tr>
    <td>'$MIN'</td>
    <td>'$MEAN'</td>
    <td>'$MAX'</td>
  </tr>
</table>' > $SHOW_DATE-$SHOW_CODE.html

#Tworzymy plik, w którym są dane potrzebne do generacji wykresu za pomocą gnuplota
echo "$TABLE_TO_GRAPH" > mydata.txt

#Tu tworzymy wykres słuchalności audycji w czasie
#Określamy wpisany w tabelce format czasu (timefmt), potem określamy format czasu wyświetlony w tworzonym wykresie (set format)
#Określamy tytuł wykresu, rozmiar, nazwę pliku wynikowego, wyłączamy legendę, ustawiamy skalę osi y, tak żeby zaczynała się od 0
#i za pomocą polecenia "plot", tworzymy plik z wykresem
gnuplot -p -e "
set xdata time;
set timefmt \"%Y-%m-%dT%H:%M:%S\";
set format x \"%H:%M:%S\";
set title \"$SHOW_TITLE - słuchalność w dniu $SHOW_DATE\";
set terminal jpeg size 1200,630;
set output '$SHOW_DATE-$SHOW_CODE.jpg';
set key off;
set xrange [\"$START_TIME_TO_GRAPH\":\"$END_TIME_TO_GRAPH\"];
set yrange [0:*];
plot 'mydata.txt' using 1:2 with linespoints linetype 6 linewidth 2;
"

#Umieszczamy wykres w html'u
echo "<br> <img src="$SHOW_DATE-$SHOW_CODE".jpg>" >> $SHOW_DATE-$SHOW_CODE.html

#Tworzymy szczegółową tabelę o wynikach słuchalności i także ją umieszczamy w html'u
echo "$TABLE_TO_REPORT"  | awk 'BEGIN { print "<br> <h2>Słuchalność minuta po minucie</h2><table class=\"center\">" }
     { print "<tr><td>" $1 "</td><td>" $2 "</td></tr>" }
     END { print "</table></body>" }' >> $SHOW_DATE-$SHOW_CODE.html

#HTML'a i wykres przenosimy do folderu z raportami (/stats-results)
mv $SHOW_DATE-$SHOW_CODE.html /stats-results/$SHOW_DATE-$SHOW_CODE.html
mv $SHOW_DATE-$SHOW_CODE.jpg /stats-results/$SHOW_DATE-$SHOW_CODE.jpg

#Przechodzimy do katalogu z raportami i tworzymy PDF'a na podstawie wcześniej wygenerowanego HTML'a, potem usuwamy i html'a i obrazek z wykresem i wracamy do wcześniejszego folderu
pushd /stats-results/
wkhtmltopdf --encoding 'utf-8' --enable-local-file-access $SHOW_DATE-$SHOW_CODE.html $SHOW_DATE-$SHOW_CODE.pdf
rm $SHOW_DATE-$SHOW_CODE.html $SHOW_DATE-$SHOW_CODE.jpg
#Kod przenoszący wygenerowany raport do katalogu w NextCloudzie
if [[ "${SHOW_LIVE}" == "custom" ]]; then
  if [[ -d "${CUSTOM_DIR}/raporty" ]]; then
    mv $SHOW_DATE-$SHOW_CODE.pdf ${CUSTOM_DIR}/raporty/$SHOW_DATE-$SHOW_CODE.pdf
  else
    mkdir -p ${CUSTOM_DIR}/raporty
    mv $SHOW_DATE-$SHOW_CODE.pdf ${CUSTOM_DIR}/raporty/$SHOW_DATE-$SHOW_CODE.pdf
  fi
else
  if [[ -d "/nextcloud/$SHOW_CODE/sluchalnosc" ]]; then
    mv $SHOW_DATE-$SHOW_CODE.pdf /nextcloud/$SHOW_CODE/sluchalnosc/$SHOW_DATE-$SHOW_CODE.pdf
  else
    mkdir -p /nextcloud/$SHOW_CODE/sluchalnosc
    mv $SHOW_DATE-$SHOW_CODE.pdf /nextcloud/$SHOW_CODE/sluchalnosc/$SHOW_DATE-$SHOW_CODE.pdf
  fi
fi
popd

# jak już mamy MIN, MEAN i MAX to wrzucimy je do bucketu agregującego dane o słuchalnościach poszczególnych wydań audycji
#Najpierw generujemy odpowiedni timestamp umieszczamy w zapytaniu do influxa, a potem wysyłamy zapytanie z zebranymi danymi
DATE_IN_SECONDS=$(date -d "$SHOW_END" +%s)

influx write \
    -b $BUCKET_NAME_FOR_RETENTION \
    -o $INFLUX_ORGANIZATION \
    -p s \
    'max,show='${SHOW_CODE}',live='${SHOW_LIVE}' min='${MIN}',mean='${MEAN}',max='${MAX}' '${DATE_IN_SECONDS}

#Na koniec usuwamy plik, który posłużył do zrobienia wykresu
rm -f mydata.txt

# I aktualizujemy pliki z rankingami
/stats/generate-week-rank.sh
/stats/generate-year-rank.sh