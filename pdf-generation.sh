#!/bin/bash

usage()
{
  echo "musisz podać parametry audycji --show-code --show-date --live"   
}

while [ "$1" != "" ]; do
  case $1 in
    -c | --show-code )        shift
                              export SHOW_CODE=$1
                              ;;
    -d | --show-date )        shift
                              export SHOW_DATE=$1
                              ;;
    -l | --live )             shift
                              export SHOW_LIVE=$1
                              ;;
    * )                       usage
                              exit 1
  esac
  shift
done

INFLUX_ORGANIZATION="RadioAktywne"
SHOW_TITLE=`cat ramowka.json | jq '.ramowka | .[] | select(.id=="'${SHOW_CODE}'") | select(.live=='$SHOW_LIVE') | .name' | sed 's/\"//g'`
START_HOUR=`cat ramowka.json | jq '.ramowka | .[] | select(.id=="'${SHOW_CODE}'") | select(.live=='$SHOW_LIVE') | .startHour'`
START_MINUTES=`cat ramowka.json | jq '.ramowka | .[] | select(.id=="'${SHOW_CODE}'") | select(.live=='$SHOW_LIVE') | .startMinutes'`
END_HOUR=`cat ramowka.json | jq '.ramowka | .[] | select(.id=="'${SHOW_CODE}'") | select(.live=='$SHOW_LIVE') | .endHour'`
END_MINUTES=`cat ramowka.json | jq '.ramowka | .[] | select(.id=="'${SHOW_CODE}'") | select(.live=='$SHOW_LIVE') | .endMinutes'`
TIME_SHIFT=`echo $(date +%:::z | sed "s/\+0//g")`
SHOW_DURATION_IN_MINUTES=`echo $(expr $(expr $END_HOUR \* 60 + $END_MINUTES ) - $(expr $START_HOUR \* 60 + $START_MINUTES ))`

START_TO_QUERY=`date -d "$SHOW_DATE $START_HOUR:$START_MINUTES:00 CEST - $TIME_SHIFT hours" +%Y-%m-%dT%H:%M:%SZ`
END_TO_QUERY=`date -d "$SHOW_DATE $END_HOUR:$END_MINUTES:00 CEST - $TIME_SHIFT hours" +%Y-%m-%dT%H:%M:%SZ`

#MIN
MIN=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"ra-stats")
        |> range(start: '$START_TO_QUERY', stop: '$END_TO_QUERY')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> aggregateWindow(every: '$SHOW_DURATION_IN_MINUTES'm, fn: min)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 5 | grep -v "_value" | head -n 1`

#MEAN
MEAN=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"ra-stats")
        |> range(start: '$START_TO_QUERY', stop: '$END_TO_QUERY')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> aggregateWindow(every: '$SHOW_DURATION_IN_MINUTES'm, fn: mean)
        |> map(fn: (r) => ({
          r with
          _value: float(v: int(v: r._value * 100.0)) / 100.0
        }))
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 5 | grep -v "_value" | head -n 1`

#MAX
MAX=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"ra-stats")
        |> range(start: '$START_TO_QUERY', stop: '$END_TO_QUERY')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> aggregateWindow(every: '$SHOW_DURATION_IN_MINUTES'm, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 5 | grep -v "_value" | head -n 1`

TABLE_DEBUG=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"ra-stats")
        |> range(start: '$START_TO_QUERY', stop: '$END_TO_QUERY')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> aggregateWindow(every: 1m, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 4-5 | cut -d 'T' -f 2 | grep -v value | sed -En 's/Z//p' | sed -En 's/,/ /p'`

TABLE=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"ra-stats")
        |> range(start: '$START_TO_QUERY', stop: '$END_TO_QUERY')
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> aggregateWindow(every: 1m, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 4-5 | cut -d 'T' -f 2 | grep -v value | sed -En 's/Z//p' | sed -En 's/,/ /p'`

if [ "$SHOW_LIVE" == "false" ]; then
  POWTORKI="powtórki "
else
  POWTORKI=""
fi

echo '<head><style>

.center {
  margin-left: auto;
  margin-right: auto;
}

table {
  font-family: arial, sans-serif;
  border-collapse: collapse;
}

h1, h2 {
  text-align: center;
}

td, th {
    border: 1px solid #000000;
    text-align: center;
    padding: 8px;
    font-size: 30px;
  }
</style>
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

echo "$TABLE" > mydata.txt

gnuplot -p -e "
set xdata time;
set timefmt \"%H:%M:%S\";
set format x \"%H:%M\";
set title '$SHOW_TITLE - słuchalność w dniu $SHOW_DATE';
set terminal jpeg size 1200,630;
set output '$SHOW_DATE-$SHOW_CODE.jpg';
set key off;
plot 'mydata.txt' using 1:2 with linespoints linetype 6 linewidth 2;
"

echo "<br> <img src="$SHOW_DATE-$SHOW_CODE".jpg>" >> $SHOW_DATE-$SHOW_CODE.html

echo "$TABLE"  | awk 'BEGIN { print "<br> <h2>Słuchalność minuta po minucie</h2><table class=\"center\">" }
     { print "<tr><td>" $1 "</td><td>" $2 "</td></tr>" }
     END { print "</table></body>" }' >> $SHOW_DATE-$SHOW_CODE.html

mv $SHOW_DATE-$SHOW_CODE.html /stats-results/$SHOW_DATE-$SHOW_CODE.html
mv $SHOW_DATE-$SHOW_CODE.jpg /stats-results/$SHOW_DATE-$SHOW_CODE.jpg

pushd /stats-results/
wkhtmltopdf --encoding 'utf-8' --enable-local-file-access $SHOW_DATE-$SHOW_CODE.html $SHOW_DATE-$SHOW_CODE.pdf
rm $SHOW_DATE-$SHOW_CODE.html $SHOW_DATE-$SHOW_CODE.jpg
popd

rm -f mydata.txt
