INFLUX_ORGANIZATION="RadioAktywne"
SHOW_TITLE="Fast Forward Charts"
SHOW_CODE="fastforward"
SHOW_DATE="2021-05-30"
TIME_SHIFT=`echo $(date +%:::z | sed "s/\+0//g")`
START_HOUR="18"
START_MINUTES="00"
END_HOUR="20"
END_MINUTES="00"
SHOW_DURATION_IN_MINUTES=`echo $(expr $(expr $END_HOUR \* 60 + $END_MINUTES ) - $(expr $START_HOUR \* 60 + $START_MINUTES ))`
START_HOUR_TO_QUERY=`echo $(expr $START_HOUR - $TIME_SHIFT)`
END_HOUR_TO_QUERY=`echo $(expr $END_HOUR - $TIME_SHIFT)`

#MIN
MIN=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket:"ra-stats")
        |> range(start: '$SHOW_DATE'T'$START_HOUR_TO_QUERY':'$START_MINUTES':00Z, stop: '$SHOW_DATE'T'$END_HOUR_TO_QUERY':'$END_MINUTES':00Z)
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
        |> range(start: '$SHOW_DATE'T'$START_HOUR_TO_QUERY':'$START_MINUTES':00Z, stop: '$SHOW_DATE'T'$END_HOUR_TO_QUERY':'$END_MINUTES':00Z)
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
        |> range(start: '$SHOW_DATE'T'$START_HOUR_TO_QUERY':'$START_MINUTES':00Z, stop: '$SHOW_DATE'T'$END_HOUR_TO_QUERY':'$END_MINUTES':00Z)
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
        |> range(start: '$SHOW_DATE'T'$START_HOUR_TO_QUERY':'$START_MINUTES':00Z, stop: '$SHOW_DATE'T'$END_HOUR_TO_QUERY':'$END_MINUTES':00Z)
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
        |> range(start: '$SHOW_DATE'T'$START_HOUR_TO_QUERY':'$START_MINUTES':00Z, stop: '$SHOW_DATE'T'$END_HOUR_TO_QUERY':'$END_MINUTES':00Z)
        |> filter(fn: (r) => r.show == "'$SHOW_CODE'", onEmpty: "drop")
        |> aggregateWindow(every: 1m, fn: max)
        |> timeShift(duration: '$TIME_SHIFT'h)
        |> keep(columns: ["_time", "_value"])
        |> drop(columns: ["result", "table"])' | cut -d ',' -f 4-5 | cut -d 'T' -f 2 | grep -v value | sed -En 's/Z//p' | sed -En 's/,/ /p'`

echo '<h1>'$SHOW_TITLE' - słuchalność z dnia '$SHOW_DATE'</h1>

<style>
table {
  font-family: arial, sans-serif;
  border-collapse: collapse;
}

td, th {
    border: 1px solid #000000;
    text-align: left;
    padding: 8px;
  }
</style>

<table>
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

echo "$TABLE"  | awk 'BEGIN { print "<br> <h2>Słuchalność minuta po minucie</h2><table>" }
     { print "<tr><td>" $1 "</td><td>" $2 "</td></tr>" }
     END { print "</table>" }' >> $SHOW_DATE-$SHOW_CODE.html

mv $SHOW_DATE-$SHOW_CODE.html /stats-results/$SHOW_DATE-$SHOW_CODE.html
mv $SHOW_DATE-$SHOW_CODE.jpg /stats-results/$SHOW_DATE-$SHOW_CODE.jpg

rm -f mydata.txt
