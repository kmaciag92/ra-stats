<h1>RA-Stats</h1>

Narzędzie do pobierania, przechowywania i prezentacji metryki słuchalności audycji w Radiu Aktywnym. Narzędzie jest przystosowane do działania jako kontener dockerowy. Składa się z trzech elementów:
- Bazy danych influxDB, która służy do przechowywania wszystkich statystyk związanych ze słuchalnością przesyłanej przez pozostałe komponenty. Baza danych jest podzielona na dwa buckety:
    - `ra-stats` - bucket, do którego są przesyłane szczegółowe metryki dotyczące słuchalności z rozdzielczością wybieraną przez użytkownika (domyślnie ustawione na co 10 sekund). Na podstawie danych z tego bucketu sporządzane są raporty słuchalności i formowane dane do bucketu `ra-stats-per-show`. W buckecie ustawiona jest retencja na 90 dni, co oznacza, że po 90 dniach zebrane dane są usuwane
    - `ra-stats-per-show` - bucket do którego przesyłane są metryki dotyczące słuchalności poszczególnych wydań audycji. Można z niego odczytać dane na temat minimalnej, średniej i maksymalnej słuchalności, które są tam przesyłane w momencie tworzenia raportu o słuchalności danego wydania audycji
- Skryptu `script.sh` - skrypt będący silnikiem przesyłającym dane do bazy danych. Co 10 sekund sprawdza aktualną liczbę słuchaczy radia, sprawdza w ramówce, która audycja powinna teraz się odbywać, następnie sprawdza na podstawie taga przesyłanego razem z danymi dźwiękowymi (tzw. RDSa) czy audycja faktycznie się odbywa i 
zapisuje aktualną metrykę słuchalności w bazie danych, w buckecie `ra-stats` oznaczając ją odpowiednim tagiem.
- Skryptu `pdf-generation.sh` - skrypt odpowiedzialny za generowanie raportów słuchalności, w których możemy znaleźć informacje o minimalnej, średniej i maksymalnej słuchalności danego wydania audycji, wykres słuchalności w zależności od czasu i tabelkę ze szczegółową słuchalnością. Pierwsze trzy informacje są także przesyłane w formie metryk do bucketu `ra-stats-per-show`, a raport jest przesyłany do odpowiedniego katalogu w NextCloudzie.

Dane o ramówce są pobierane z pliku `get_api_timeslots.json`. Docelowo będą pobierane z wewnętrznego API ramówkowego.

W repozytorium można znaleźć także aktualny dump bazy danych.

<h3>Instrukcja uruchomienia</h3>

1. Do uruchomienia tego kontenera potrzebny jest daemon dockera zainstalowany na środowisku
2. Stwórz w katalogu głównym roota katalog `influxdb-engine` i skopiuj tam zawartość katalogu `influxdb-engine` z repozytorium. Katalog będzie potem domontowany do kontenera jako katalog `/var/lib/influxdb2`
3. Stwórz w roocie katalog `/stats-results` tam będą tymczasowo przechowywane wygenerowane raporty. Katalog potem będzie domontowany do kontenera jako katalog `/stats-results`
4. Będąc w katalogu repozytorium, zbuduj kontener za pomocą polecenia 
```
docker build -t stats:0.0.16 .
```
5. Jeśli uruchamiałeś wcześniej kontener o nazwie `ra-stats` to usuń go poleceniem
```
docker rm -f ra-stats
```
bądź w następnym punkcie uruchom go z inną nazwą
6. Uruchom kontener za pomocą następującej komendy:
```
docker run -d -p 8086:8086 --name ra-stats --dns 8.8.8.8 \
    -v /influxdb-engine:/var/lib/influxdb2  \
    -v /stats-results:/stats-results  \
    -v /home/konrad/docker-projects/ra-stats/get_api_timeslots.json:/stats/get_api_timeslots.json  \
    -v /srv/ra/audycje:/nextcloud \
    stats:0.0.16
```
Poza dwoma poprzednimi volumami domontowujemy jeszcze plik z ramówką do odpowiedniego katalogu w kontenerze i katalog z nextclouda.
Dodatkowo udostępniamy port `8086` na którym działa influx, co nam umożliwia skorzystanie z API influxowej bazy danych, a także zmieniamy wewnątrzkontenerowy dns `8.8.8.8`, żeby uniknąć kłopotów z łącznością.
7. Aby sprawdzić czy wszystko dobrze działa wyświetlamy sobie logi za pomocą polecenia
```
docker logs ra-stats --tail 50 -f
```
i patrzymy czy logi są przesyłane do bazy danych, a także wchodzimy na adres ```localhost:8086``` logujemy się loginem `ra-stats` i odpowiednim statsem i sprawdzamy na odpowiednim wykresie czy aktualne dane się wczytują
