<h1>RA-Stats</h1>

Narzędzie do pobierania, przechowywania i prezentacji metryki słuchalności audycji w Radiu Aktywnym. Narzędzie jest przystosowane do działania jako kontener dockerowy. Składa się z trzech elementów:
- Bazy danych influxDB, która służy do przechowywania wszystkich statystyk związanych ze słuchalnością przesyłanej przez pozostałe komponenty. Baza danych jest podzielona na dwa buckety:
    - `ra-stats` - bucket, do którego są przesyłane szczegółowe metryki dotyczące słuchalności z rozdzielczością wybieraną przez użytkownika (domyślnie ustawione na co 10 sekund). Na podstawie danych z tego bucketu sporządzane są raporty słuchalności i formowane dane do bucketu `ra-stats-per-show`. W buckecie ustawiona jest retencja na 90 dni, co oznacza, że po 90 dniach zebrane dane są usuwane
    - `ra-stats-per-show` - bucket do którego przesyłane są metryki dotyczące słuchalności poszczególnych wydań audycji. Można z niego odczytać dane na temat minimalnej, średniej i maksymalnej słuchalności, które są tam przesyłane w momencie tworzenia raportu o słuchalności danego wydania audycji
- Skryptu `gathering-script.sh` - skrypt będący silnikiem przesyłającym dane do bazy danych. Co 10 sekund sprawdza aktualną liczbę słuchaczy radia, sprawdza w ramówce, która audycja powinna teraz się odbywać, następnie sprawdza na podstawie taga przesyłanego razem z danymi dźwiękowymi (tzw. RDSa) czy audycja faktycznie się odbywa i 
zapisuje aktualną metrykę słuchalności w bazie danych, w buckecie `ra-stats` oznaczając ją odpowiednim tagiem.
- Skryptu `report-generation.sh` - skrypt odpowiedzialny za generowanie raportów słuchalności, w których możemy znaleźć informacje o minimalnej, średniej i maksymalnej słuchalności danego wydania audycji, wykres słuchalności w zależności od czasu i tabelkę ze szczegółową słuchalnością. Pierwsze trzy informacje są także przesyłane w formie metryk do bucketu `ra-stats-per-show`, a raport jest przesyłany do odpowiedniego katalogu w NextCloudzie.

Dane o ramówce są pobierane z wewnętrznego API ramówkowego działającego pod adresem `cloud.radioaktywne.pl/api/timeslots`

W repozytorium można znaleźć także aktualny dump bazy danych.

<h3>Instrukcja poprawnego uruchomienia</h3>

1.	Pobierz aktualny kod aplikacji z jednego z dwóch repozytoriów:

a.	https://github.com/kmaciag92/ra-stats

b.	https://github.com/RadioAktywne/ra-stats 

2.	Zainstaluj i uruchom aplikację docker, tak aby można było za jej pośrednictwem zbudować i uruchomić kontener
3.	Sprawdź czy w katalogu `influxdb-engine`, znajduje się aktualny dump bazy danych. Jeśli nie, stwórz w katalogu głównym roota katalog o takiej nazwie i skopiuj tam zawartość katalogu `influxdb-engine` z repozytorium. Katalog będzie potem domontowany do kontenera jako katalog `/var/lib/influxdb2`. 
4.	Stwórz w katalogu głównym roota katalog `stats-results` tam będą tymczasowo przechowywane wygenerowane raporty. Katalog potem będzie domontowany do kontenera jako katalog `/stats-results`
5. Sprawdź czy w `Dockerfile` są odpowiednio wypełnione zmienne `RASSWORD` i `INFLUX_TOKEN`. Jeśli jest tam wpisany komentarz `#FILL` to musisz dostać plik z tymi zmiennymi. Jeśli nie został na serwerze po poprzedniej instalacji zapytaj autora tego featura o te zmienne, bo mogą one gwarantować dostęp do poprzednich danych.
6.	Będąc w katalogu repozytorium, zbuduj kontener za pomocą polecenia,

`docker build -t stats:0.2 .`

nazwa obrazu i wersja są przykładowe, można użyć dowolnych.

7.	Jeśli uruchamiałeś wcześniej kontener o nazwie ra-stats to usuń go poleceniem

`docker rm -f ra-stats`

bądź w następnym punkcie uruchom go z inną nazwą 
8.	Uruchom kontener za pomocą następującej komendy:

```
docker run -d -p 8086:8086 --name ra-stats --dns 8.8.8.8 \
    -v /influxdb-engine:/var/lib/influxdb2  \
    -v /stats-results:/stats-results  \
    -v /srv/ra/audycje:/nextcloud \
    stats:0.2
```

Wykonanie powyższego polecenia udostępniasz port 8086 na którym działa baza influxDB, co nam umożliwia skorzystanie z jej API, a także zmienia adres dns używany przez kontener na `8.8.8.8`, żeby uniknąć kłopotów z łącznością. 

Aby działały dodatkowe funkcje, takie jak generowanie rankingów w formie plików PDF i „A24H mode”, należy także zamontować odpowiednie katalogi dostępne z zewnątrz kontenera, w których będzie można odczytywać bądź zapisywać pliki potrzebne do obsługi tych funkcji

```
    -v <folder dostępny w nextcloudzie z którego będzie można pobrać pliki z aktualnymi rankingami>:/rankingi \
    -v <folder dostępny w nextcloudzie z którego będzie można pobrać pliki z raportami słuchalności customowych audycji>:/custom_reports
```

Więc pełne polecenie brzmi:
```
docker run -d -p 8086:8086 --name ra-stats --dns 8.8.8.8 \
    -v /influxdb-engine:/var/lib/influxdb2  \
    -v /stats-results:/stats-results  \
    -v /srv/ra/audycje:/nextcloud \
    -v <folder dostępny w nextcloudzie z którego będzie można pobrać pliki z aktualnymi rankingami>:/rankingi \
    /v <folder dostępny w nextcloudzie z którego będzie można pobrać pliki z raportami słuchalności customowych audycji>:/custom_reports \
    stats:0.2
```

9.	Aby sprawdzić czy wszystko dobrze działa wyświetl logi z kontenera za pomocą polecenia

`docker logs ra-stats --tail 50 -f`

i na ich podstawie sprawdź czy logi są przesyłane do bazy danych, logi powinny wyglądać następująco:
```
Sat Nov 12 00:44:40 CET 2022 RA_TAG=Radiohead - Daydreaming
Sat Nov 12 00:44:40 CET 2022 RA_SHOW_ID=playlista
Sat Nov 12 00:44:40 CET 2022 RA_SHOW_LIVE=false
Sat Nov 12 00:44:40 CET 2022 START_SHOW_TIME_UTC=2022-11-11T22:34:01Z
Sat Nov 12 00:44:40 CET 2022 END_SHOW_TIME_UTC=
listeners,show=playlista,live=false listeners=2 Sat Nov 12 00:44:40 CET 2022
Sat Nov 12 00:44:50 CET 2022 RA_TAG=Radiohead - Daydreaming
Sat Nov 12 00:44:50 CET 2022 RA_SHOW_ID=playlista
Sat Nov 12 00:44:50 CET 2022 RA_SHOW_LIVE=false
Sat Nov 12 00:44:50 CET 2022 START_SHOW_TIME_UTC=2022-11-11T22:34:01Z
Sat Nov 12 00:44:50 CET 2022 END_SHOW_TIME_UTC=
listeners,show=playlista,live=false listeners=2 Sat Nov 12 00:44:50 CET 2022
```

a także wejdź na adres `localhost:8086` zaloguj się loginem `ra-stats` i odpowiednim hasłem i sprawdź na dashboardzie `Słuchalność` czy aktualne dane są przesyłane do bazy danych.
