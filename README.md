```
docker build -t stats:0.0.16-test2 .
docker rm -f ra-stats
docker run -d -p 8086:8086 --name ra-stats --dns 8.8.8.8 \
    -v /influxdb-engine:/var/lib/influxdb2  \
    -v /stats-results:/stats-results  \
    -v /home/konrad/docker-projects/ra-stats/get_api_timeslots.json:/stats/get_api_timeslots.json  \
    stats:0.0.16-test2
docker exec -ti ra-stats bash
```