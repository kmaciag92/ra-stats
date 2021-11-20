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
    libreoffice-help-common \
    cron

RUN locale-gen pl_PL.UTF-8
ENV LANG pl_PL.UTF-8
ENV LANGUAGE pl_PL.UTF-8
ENV LC_ALL pl_PL.UTF-8
ENV A24H_MODE false

ADD gathering-script.sh /stats/gathering-script.sh
RUN chmod +x /stats/gathering-script.sh

ADD report-generation.sh /stats/report-generation.sh
RUN chmod +x /stats/report-generation.sh
ADD manual-report-generation.sh /stats/manual-report-generation.sh
RUN chmod +x /stats/manual-report-generation.sh

ADD generate-week-rank.sh /stats/generate-week-rank.sh
RUN chmod +x /stats/generate-week-rank.sh

ADD generate-year-rank.sh /stats/generate-year-rank.sh
RUN chmod +x /stats/generate-year-rank.sh

RUN crontab -l | { cat; echo "30 2 * * * /stats/generate-year-rank.sh"; } | crontab -
RUN crontab -l | { cat; echo "20 2 * * * /stats/generate-week-rank.sh"; } | crontab -

ENV RASSWORD radioniedziala
ENV INFLUX_TOKEN QjR73YQ1Yd-a8KgaqHr7uQULQcLE9TCFIpUVDjGspglTuVw9h_1IMdVgFFFW9txc3DfxCJ2_IEtpTHylWebP1A==
ENV RA_ADDRESS listen.radioaktywne.pl
ENV TZ Europe/Warsaw
ENV API_ADDRESS https://cloud.radioaktywne.pl/api/timeslots

ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENTRYPOINT ["/usr/bin/supervisord"]
EXPOSE 8086 8088