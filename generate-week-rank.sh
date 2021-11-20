#!/bin/bash

INFLUX_ORGANIZATION=RadioAktywne
INFLUX_TOKEN=QjR73YQ1Yd-a8KgaqHr7uQULQcLE9TCFIpUVDjGspglTuVw9h_1IMdVgFFFW9txc3DfxCJ2_IEtpTHylWebP1A==
API_ADDRESS=https://cloud.radioaktywne.pl/api/timeslots
PROGRAM_API_DATA=`curl ${API_ADDRESS}`
REPORT_TIME=`date '+%Y-%m-%d %T'`
GENERATED_FILE_NAME="tygodniowy_ranking"

RANKING=`curl -sS --request POST  \
  http://localhost:8086/api/v2/query?org=$INFLUX_ORGANIZATION \
  --header 'Authorization: Token '${INFLUX_TOKEN} \
  --header 'Accept: application/csv' \
  --header 'Content-type: application/vnd.flux' \
  --data 'from(bucket: "ra-stats-per-show")
  |> range(start: -duration(v: 7d))
  |> filter(fn: (r) =>
    r._field == "mean"
    )
  |> group(columns: ["_show"])
  |> sort(desc: true)
  |> unique(column: "show")
  |> keep(columns: ["show", "_value", "live", "_time"])' | cut -d ',' -f 4-7 | grep -v value | sed -En 's/Z//p' | sed -En 's/T/ /p' | sed -En 's/,/ /p' | sed -En 's/,/ /p' | sed -En 's/,/ /p' | sed 's/\r//g'`

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
<center><h1>tygodniowy ranking słuchalności</h1></center>
<center><h6>wygenerowano: '$REPORT_TIME'</h6></center>
<table class="center">
  <tr>
    <th>LP</th>
    <th>Wynik</th>
    <th>Nazwa Audycji</th>
    <th>Data</th>
  </tr>' > $GENERATED_FILE_NAME.html

while IFS= read -r line
do
  SHOW_CODE=`echo "$line" | awk '{ print $5 }'`
  SHOW_NAME=`echo ${PROGRAM_API_DATA} | jq '. | .[] | select(.program.slug=="'${SHOW_CODE}'") |  .program.rds ' | sed 's/\"//g' | head -1`
  line=`echo $line | sed "s/ /=/g"`
  if [[ -z "$SHOW_NAME" ]]; then
    echo "$line" >> ranking.txt
    continue
  fi
  line=`echo $line | sed "s/$SHOW_CODE/$SHOW_NAME/g"`
  echo "$line" >> ranking.txt
done <<< $(echo "$RANKING")

cat ranking.txt | awk 'BEGIN { FS="="; print "<tr>" }
     { print "<td>" } 
     { print NR } 
     { print "</td><td>" $3 "</td><td>" $5 "</td><td>" $1 "</td></tr>" }
     END { print "</table></body>" }' >> $GENERATED_FILE_NAME.html

rm ranking.txt

wkhtmltopdf --encoding 'utf-8' --enable-local-file-access $GENERATED_FILE_NAME.html $GENERATED_FILE_NAME.pdf

rm $GENERATED_FILE_NAME.html

if [[ -d "/rankingi" ]]; then
  mv $GENERATED_FILE_NAME.pdf /rankingi/$GENERATED_FILE_NAME.pdf
else
  mkdir -p /rankingi
  mv $GENERATED_FILE_NAME.pdf /rankingi/$GENERATED_FILE_NAME.pdf
fi