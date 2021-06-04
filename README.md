docker run -d -p 8086:8086 --name ra-stats \
 -v /influxdb-engine:/var/lib/influxdb2 \
 -v /stats-results:/stats-results \
 -v /home/konrad/docker-projects/ra-stats/ramowka.json:/stats/ramowka.json \
 stats:0.0.13-final