FROM influxdb:2.0.6

RUN apt-get update && \
    apt-get -y install jq procps vim net-tools supervisor

ADD script.sh /stats/script.sh
RUN chmod +x /stats/script.sh

ADD pdf-generation.sh /stats/pdf-generation.sh
RUN chmod +x /stats/pdf-generation.sh

ENV RASSWORD #FILL
ENV INFLUX_TOKEN #FILL
ENV RA_ADDRESS listen.radioaktywne.pl
ENV TZ Europe/Warsaw

ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ramowka.json /stats/ramowka.json

ENTRYPOINT ["/usr/bin/supervisord"]
EXPOSE 8086 8088