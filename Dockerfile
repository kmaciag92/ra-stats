FROM influxdb:2.0.6

RUN apt-get update && \
    apt-get -y install jq \
    procps \
    vim \
    net-tools \
    supervisor \
    gnuplot-x11 \
    wkhtmltopdf \
    locales \
    libreoffice-help-common

RUN locale-gen pl_PL.UTF-8
ENV LANG pl_PL.UTF-8
ENV LANGUAGE pl_PL.UTF-8
ENV LC_ALL pl_PL.UTF-8

ADD script.sh /stats/script.sh
RUN chmod +x /stats/script.sh

ADD pdf-generation.sh /stats/pdf-generation.sh
RUN chmod +x /stats/pdf-generation.sh

ENV RASSWORD #FILL
ENV INFLUX_TOKEN #FILL
ENV RA_ADDRESS listen.radioaktywne.pl
ENV TZ Europe/Warsaw
ENV API_ADDRESS https://cloud.radioaktywne.pl/api/timeslots

ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENTRYPOINT ["/usr/bin/supervisord"]
EXPOSE 8086 8088