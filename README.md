docker build -t stats:0.0.15-test .

docker run -d -p 8086:8086 --name ra-stats \
 -v /influxdb-engine:/var/lib/influxdb2 \
 -v /stats-results:/stats-results \
 -v /home/konrad/docker-projects/ra-stats/ramowka.json:/stats/ramowka.json \
 stats:0.0.15-test

 ./pdf-generation.sh --show-date 2021-05-16 --show-code ukryte --show-live true