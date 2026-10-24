#!/usr/bin/env bash
# Lokalna baza testowa Pelikana: Oracle Database Free (26ai) w kontenerze + schematy testowe + utPLSQL.
#
# Użycie: scripts/testdb.sh up       uruchamia kontener (tworzy go przy pierwszym razie) i czeka na bazę
#         scripts/testdb.sh seed     tworzy schematy i obiekty testowe, instaluje utPLSQL (idempotentne)
#         scripts/testdb.sh reset    usuwa kontener i dane, potem up + seed
#         scripts/testdb.sh down     zatrzymuje kontener (dane zostają)
#         scripts/testdb.sh env      wypisuje zmienne PELIKAN_TESTDB_* (do `eval`)
#         scripts/testdb.sh sql [U]  sqlplus w kontenerze jako U (domyślnie SYSTEM), skrypt ze stdin
#         scripts/testdb.sh ssh-up   serwer SSH w kontenerze (testy tunelu): klucz w .testdb/ssh, port 127.0.0.1:2222
#         scripts/testdb.sh ssh-down usuwa kontener SSH
#         scripts/testdb.sh owm      instaluje Workspace Manager (WMSYS) i przestrzeń DEV_PELIKAN_WS (PD-CONN-009)
#         scripts/testdb.sh ords-up  ORDS (tylko testy) w kontenerze z JRE, HTTP 127.0.0.1:8181 (SD-ORDS-001); ords-down
#         scripts/testdb.sh ldap-up  OpenLDAP z aliasem dev_pelikan_ldap, ldap.ora i sqlnet.ora w .testdb/oracle-net-user (PD-CONN-013); ldap-down
#         scripts/testdb.sh kdc-up   KDC MIT, Kerberos w bazie testowej, bilety w .testdb/kerberos (PD-CONN-014); kdc-down
#         scripts/testdb.sh kdc-linux test Kerberos przez Instant Client dla Linuksa w kontenerze swift:6.3-noble
#
# Hasła: losowe przy pierwszym `up`, w .testdb/env (poza repozytorium, 0600). Port tylko na 127.0.0.1.
# Testy łączą się WYŁĄCZNIE z tą bazą (PELIKAN_TESTDB_*); żadnych innych baz (docs/PROMPT.md §9, §13).
# W CI (Linux) kontener uruchamia workflow jako usługę, a hasła podaje przez zmienne środowiskowe.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/.testdb"
ENVFILE="$STATE/env"
NAME="${PELIKAN_TESTDB_CONTAINER:-pelikan-testdb}"
IMAGE="${PELIKAN_TESTDB_IMAGE:-gvenzl/oracle-free:latest}"
PORT="${PELIKAN_TESTDB_PORT:-1531}"
UTPLSQL_VERSION="${UTPLSQL_VERSION:-v.3.2.3}"

rand() { openssl rand -hex 10; }

# sqlplus w kontenerze bazy. Po `kdc-up` sqlnet.ora serwera włącza Kerberos, który ten sam ORACLE_HOME czytałby też
# jako klient — narzędzia skryptu używają wtedy osobnego katalogu klienta bez Kerberos.
# shellcheck disable=SC2016
SQLPLUS='[ -d /opt/oracle/client-net ] && export TNS_ADMIN=/opt/oracle/client-net; exec sqlplus -S -L /nolog'

ensure_env() {
    mkdir -p "$STATE"
    chmod 700 "$STATE"
    if [ ! -f "$ENVFILE" ]; then
        (umask 077
         cat > "$ENVFILE" <<ENV
PELIKAN_TESTDB_HOST=127.0.0.1
PELIKAN_TESTDB_PORT=$PORT
PELIKAN_TESTDB_SERVICE=FREEPDB1
PELIKAN_TESTDB_SYSTEM_PASSWORD=P$(rand)
PELIKAN_TESTDB_USER=PELIKAN_TEST
PELIKAN_TESTDB_PASSWORD=T$(rand)
PELIKAN_TESTDB_AGENT_USER=PELIKAN_AGENT
PELIKAN_TESTDB_AGENT_PASSWORD=A$(rand)
ENV
        )
    fi
    # shellcheck disable=SC1090
    set -a; . "$ENVFILE"; set +a
}

in_ci() { [ -n "${CI:-}" ] && [ -n "${PELIKAN_TESTDB_SYSTEM_PASSWORD:-}" ]; }

load_env() {
    if in_ci; then return; fi
    ensure_env
}

container_exists() { docker container inspect "$NAME" >/dev/null 2>&1; }

wait_ready() {
    echo "Czekam na bazę w kontenerze ${NAME}…" >&2
    for _ in $(seq 1 180); do
        if docker logs "$NAME" 2>&1 | grep -q "DATABASE IS READY TO USE"; then
            echo "Baza gotowa." >&2
            return 0
        fi
        sleep 2
    done
    echo "Baza nie wystartowała w 6 minut (docker logs ${NAME})" >&2
    return 1
}

up() {
    load_env
    if container_exists; then
        docker start "$NAME" >/dev/null
    else
        docker run -d --name "$NAME" \
            -p "127.0.0.1:${PELIKAN_TESTDB_PORT}:1521" \
            -e ORACLE_PASSWORD="$PELIKAN_TESTDB_SYSTEM_PASSWORD" \
            --shm-size=1g \
            "$IMAGE" >/dev/null
    fi
    wait_ready
}

# sqlplus wewnątrz kontenera; hasło przez stdin (nie w argumentach procesu).
sql_as() {
    local user="$1" pw="$2"
    { printf 'CONNECT %s/"%s"@//localhost:1521/FREEPDB1\n' "$user" "$pw"
      printf 'WHENEVER SQLERROR EXIT SQL.SQLCODE\nSET FEEDBACK OFF\nSET SERVEROUTPUT ON\n'
      cat
      printf '\nEXIT\n'
    } | docker exec -i "$NAME" bash -c "$SQLPLUS"
}

sql_sys() {
    { printf 'CONNECT sys/"%s"@//localhost:1521/FREEPDB1 AS SYSDBA\n' "$PELIKAN_TESTDB_SYSTEM_PASSWORD"
      printf 'WHENEVER SQLERROR EXIT SQL.SQLCODE\nSET FEEDBACK OFF\nSET SERVEROUTPUT ON\n'
      cat
      printf '\nEXIT\n'
    } | docker exec -i "$NAME" bash -c "$SQLPLUS"
}

# Tabele DBMS_TRACE (PD-OPT-007): tracetab.sql z ORACLE_HOME tworzy SYS.PLSQL_TRACE_RUNS/EVENTS — raz, tylko baza testowa.
install_tracetab() {
    local n
    n=$(printf "SET HEADING OFF\nSELECT COUNT(*) FROM dba_tables WHERE owner = 'SYS' AND table_name = 'PLSQL_TRACE_RUNS';\n" | sql_sys | tr -dc '0-9')
    if [ "${n:-0}" = "0" ]; then
        { printf 'WHENEVER SQLERROR CONTINUE\n@?/rdbms/admin/tracetab.sql\n'
          printf 'CREATE OR REPLACE PUBLIC SYNONYM plsql_trace_runs FOR sys.plsql_trace_runs;\n'
          printf 'CREATE OR REPLACE PUBLIC SYNONYM plsql_trace_events FOR sys.plsql_trace_events;\n'
          printf 'GRANT SELECT ON sys.plsql_trace_runs TO PUBLIC;\nGRANT SELECT ON sys.plsql_trace_events TO PUBLIC;\n'
        } | sql_sys >/dev/null
    fi
}

install_utplsql() {
    local have
    have="$(printf "SET HEADING OFF\nSELECT COUNT(*) FROM dba_users WHERE username = 'UT3';\n" | sql_sys | tr -d '[:space:]')"
    if [ "$have" = "1" ]; then
        echo "utPLSQL już zainstalowany." >&2
        return
    fi
    local cache="$STATE/utplsql-$UTPLSQL_VERSION"
    if [ ! -d "$cache/utPLSQL/source" ]; then
        mkdir -p "$cache"
        curl -fsSL -o "$cache/utPLSQL.tar.gz" \
            "https://github.com/utPLSQL/utPLSQL/releases/download/$UTPLSQL_VERSION/utPLSQL.tar.gz"
        curl -fsSL -o "$cache/utPLSQL.tar.gz.sha256" \
            "https://github.com/utPLSQL/utPLSQL/releases/download/$UTPLSQL_VERSION/utPLSQL.tar.gz.sha256"
        (cd "$cache" && shasum -a 256 -c utPLSQL.tar.gz.sha256 >/dev/null 2>&1 \
            || [ "$(awk '{print $1}' utPLSQL.tar.gz.sha256)" = "$(shasum -a 256 utPLSQL.tar.gz | awk '{print $1}')" ]) \
            || { echo "Błędna suma kontrolna utPLSQL" >&2; exit 1; }
        tar -xzf "$cache/utPLSQL.tar.gz" -C "$cache"
    fi
    # docker cp tworzy pliki jako root, a instalator zapisuje log w katalogu roboczym — właściciel oracle.
    docker exec -u root "$NAME" rm -rf /tmp/utPLSQL
    docker cp "$cache/utPLSQL" "$NAME:/tmp/utPLSQL"
    docker exec -u root "$NAME" chown -R oracle /tmp/utPLSQL
    local utpw log="$STATE/utplsql-install.log"
    utpw="U$(rand)"
    # install_headless.sql: schemat UT3, publiczne synonimy i granty (dokumentacja utPLSQL „Install”).
    if ! { printf 'CONNECT sys/"%s"@//localhost:1521/FREEPDB1 AS SYSDBA\n' "$PELIKAN_TESTDB_SYSTEM_PASSWORD"
           printf '@install_headless.sql UT3 "%s" USERS\nEXIT\n' "$utpw"
         } | docker exec -i -w /tmp/utPLSQL/source "$NAME" bash -c "$SQLPLUS" > "$log" 2>&1; then
        tail -30 "$log" >&2
        echo "Instalacja utPLSQL nie powiodła się (pełny log: $log)" >&2
        exit 1
    fi
    echo "Zainstalowano utPLSQL $UTPLSQL_VERSION." >&2
}

seed() {
    load_env
    sql_sys <<SQL
DECLARE
  PROCEDURE mk(u VARCHAR2, p VARCHAR2) IS
    n PLS_INTEGER;
  BEGIN
    SELECT COUNT(*) INTO n FROM dba_users WHERE username = u;
    IF n = 0 THEN
      EXECUTE IMMEDIATE 'CREATE USER ' || u || ' IDENTIFIED BY "' || p || '" QUOTA UNLIMITED ON USERS';
    ELSE
      EXECUTE IMMEDIATE 'ALTER USER ' || u || ' IDENTIFIED BY "' || p || '" ACCOUNT UNLOCK';
    END IF;
  END;
BEGIN
  mk('$PELIKAN_TESTDB_USER', '$PELIKAN_TESTDB_PASSWORD');
  mk('$PELIKAN_TESTDB_AGENT_USER', '$PELIKAN_TESTDB_AGENT_PASSWORD');
END;
/
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER,
      CREATE TYPE, CREATE SYNONYM, CREATE JOB, CREATE MATERIALIZED VIEW, CREATE DOMAIN, CREATE MLE,
      DEBUG CONNECT SESSION TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_DEBUG_JDWP TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_HPROF TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SESSION TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SQL_PLAN TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SQL_PLAN_STATISTICS_ALL TO $PELIKAN_TESTDB_USER;
-- Eksport/import przez Data Pump (PD-TOOL-005): katalog DATA_PUMP_DIR — tylko w bazie testowej.
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SQL TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$MYSTAT TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$STATNAME TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_LOCK TO $PELIKAN_TESTDB_USER;
-- Przeglądarka sesji (PD-TOOL-015): widoki V$ i zabijanie sesji — tylko w bazie testowej.
GRANT SELECT ON V_\$SESSION TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$OPEN_CURSOR TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$LOCK TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SESSTAT TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SESSION_WAIT TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SQLTEXT_WITH_NEWLINES TO $PELIKAN_TESTDB_USER;
-- Panel DBA i Instance Viewer (SD-DBA-001, SD-DBA-004): słownik i widoki V$ tylko do odczytu.
GRANT SELECT ON DBA_TABLESPACES TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_DATA_FILES TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_TEMP_FILES TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_FREE_SPACE TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_USERS TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_ROLES TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_ROLE_PRIVS TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$PARAMETER TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$INSTANCE TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$DATABASE TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$VERSION TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SYSTEM_WAIT_CLASS TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$SGASTAT TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$PGASTAT TO $PELIKAN_TESTDB_USER;
GRANT ALTER SYSTEM TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_MONITOR TO $PELIKAN_TESTDB_USER;
-- Event Monitor (PD-TOOL-014).
GRANT EXECUTE ON DBMS_ALERT TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_PIPE TO $PELIKAN_TESTDB_USER;
-- Diagnostics/Tuning Pack (SD-DBA-002/003, SD-MON-001) — Oracle Free ma je w licencji; tylko baza testowa.
GRANT SELECT_CATALOG_ROLE TO $PELIKAN_TESTDB_USER;
GRANT ADVISOR TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_WORKLOAD_REPOSITORY TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_SQLTUNE TO $PELIKAN_TESTDB_USER;
-- Synonimy PUBLIC (Query Builder, PD-QB-001) — tylko baza testowa.
GRANT CREATE PUBLIC SYNONYM TO $PELIKAN_TESTDB_USER;
GRANT DROP PUBLIC SYNONYM TO $PELIKAN_TESTDB_USER;
-- Zakończenie sesji okna i SQL Trace (PD-CONN-027, PD-OPT-008) — tylko baza testowa.
GRANT ALTER SYSTEM TO $PELIKAN_TESTDB_USER;
GRANT ALTER SESSION TO $PELIKAN_TESTDB_USER;
-- MLE (SD-MLE-001).
GRANT CREATE MLE TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON JAVASCRIPT TO $PELIKAN_TESTDB_USER;
-- Edytory obiektów (PD-OED-008/009): biblioteki, katalogi, łącza, kolejki AQ, profile, uprawnienia obiektowe —
-- tylko baza testowa.
GRANT CREATE LIBRARY, CREATE ANY DIRECTORY, DROP ANY DIRECTORY, CREATE DATABASE LINK, CREATE PROFILE, ALTER PROFILE,
      DROP PROFILE, CREATE USER, ALTER USER, DROP USER, CREATE ROLE, DROP ANY ROLE, GRANT ANY ROLE,
      GRANT ANY PRIVILEGE TO $PELIKAN_TESTDB_USER;
GRANT AQ_ADMINISTRATOR_ROLE TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_AQADM TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_PROFILES TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_SYS_PRIVS TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_TAB_PRIVS TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_TS_QUOTAS TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON DBA_DIRECTORIES TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_AQ TO $PELIKAN_TESTDB_USER;
-- Asercje SQL (23.26+, PD-OB-002) — na starszych obrazach bez tego uprawnienia.
BEGIN EXECUTE IMMEDIATE 'GRANT CREATE ASSERTION TO $PELIKAN_TESTDB_USER'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
GRANT CREATE SESSION TO $PELIKAN_TESTDB_AGENT_USER;
-- Agent przez proxy: sesja PELIKAN_TEST[PELIKAN_AGENT] z uprawnieniami użytkownika agenta (PROMPT §7.3 p.4).
ALTER USER $PELIKAN_TESTDB_AGENT_USER GRANT CONNECT THROUGH $PELIKAN_TESTDB_USER;
SQL
    install_utplsql
    install_tracetab
    for f in "$ROOT"/scripts/testdb/seed/*.sql; do
        [ -f "$f" ] || continue
        echo "Seed: $(basename "$f")" >&2
        sql_as "$PELIKAN_TESTDB_USER" "$PELIKAN_TESTDB_PASSWORD" < "$f" >/dev/null
    done
    # Rekompilacja zależnych (niepoprawny ma zostać tylko celowo zepsuty BROKEN_PKG) i konto agenta:
    # tylko odczyt tabel i widoków schematu testowego.
    sql_as "$PELIKAN_TESTDB_USER" "$PELIKAN_TESTDB_PASSWORD" <<SQL
BEGIN
  DBMS_UTILITY.COMPILE_SCHEMA(schema => USER, compile_all => FALSE);
END;
/
BEGIN
  FOR t IN (SELECT object_name FROM user_objects WHERE object_type IN ('TABLE', 'VIEW')
             AND object_name NOT LIKE 'BIN$%') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON "' || t.object_name || '" TO $PELIKAN_TESTDB_AGENT_USER';
  END LOOP;
END;
/
SQL
    echo "Seed zakończony." >&2
}

SSH_NAME="${PELIKAN_TESTDB_SSH_CONTAINER:-pelikan-testdb-ssh}"
SSH_PORT="${PELIKAN_TESTDB_SSH_PORT:-2222}"
NET="${PELIKAN_TESTDB_NETWORK:-pelikan-testnet}"

# Serwer SSH (bastion) w tej samej sieci Docker co baza: tunel ssh -L … pelikan-testdb:1521.
ssh_up() {
    load_env
    mkdir -p "$STATE/ssh"
    chmod 700 "$STATE/ssh"
    [ -f "$STATE/ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C "pelikan-test" -f "$STATE/ssh/id_ed25519"
    docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
    docker network inspect "$NET" | grep -q "\"$NAME\"" || docker network connect "$NET" "$NAME"
    # Obraz w wersji 2 (użytkownik z hasłem); kontener ze starszego obrazu jest tworzony od nowa.
    local image=pelikan-test-sshd:2
    docker image inspect "$image" >/dev/null 2>&1 || docker build -q -t "$image" "$ROOT/scripts/testdb/ssh" >/dev/null
    if docker container inspect "$SSH_NAME" >/dev/null 2>&1 \
       && [ "$(docker container inspect -f '{{.Config.Image}}' "$SSH_NAME")" != "$image" ]; then
        docker rm -f "$SSH_NAME" >/dev/null
    fi
    if ! docker container inspect "$SSH_NAME" >/dev/null 2>&1; then
        docker run -d --name "$SSH_NAME" --network "$NET" -p "127.0.0.1:${SSH_PORT}:22" "$image" >/dev/null
    else
        docker start "$SSH_NAME" >/dev/null
    fi
    # Hasło użytkownika `haslo` (test tunelu z hasłem): losowe, tylko w .testdb/env jak hasła bazy testowej.
    grep -q '^PELIKAN_TESTDB_SSH_PASSWORD=' "$ENVFILE" || echo "PELIKAN_TESTDB_SSH_PASSWORD=S$(rand)" >> "$ENVFILE"
    load_env
    printf 'haslo:%s\n' "$PELIKAN_TESTDB_SSH_PASSWORD" | docker exec -i "$SSH_NAME" chpasswd >/dev/null 2>&1
    docker cp "$STATE/ssh/id_ed25519.pub" "$SSH_NAME:/home/tunnel/.ssh/authorized_keys"
    docker exec "$SSH_NAME" sh -c 'chown tunnel:tunnel /home/tunnel/.ssh/authorized_keys && chmod 600 /home/tunnel/.ssh/authorized_keys'
    # known_hosts testu: klucz hosta kontenera (tunel weryfikuje host jak zwykły ssh).
    for _ in $(seq 1 20); do
        if ssh-keyscan -p "$SSH_PORT" -t ed25519 127.0.0.1 2>/dev/null | sed "s/^127.0.0.1/[127.0.0.1]:${SSH_PORT}/" > "$STATE/ssh/known_hosts.tmp" && [ -s "$STATE/ssh/known_hosts.tmp" ]; then
            mv "$STATE/ssh/known_hosts.tmp" "$STATE/ssh/known_hosts"
            break
        fi
        sleep 0.5
    done
    grep -q '^PELIKAN_TESTDB_SSH_PORT=' "$ENVFILE" || {
        echo "PELIKAN_TESTDB_SSH_PORT=$SSH_PORT" >> "$ENVFILE"
        echo "PELIKAN_TESTDB_SSH_DBHOST=$NAME" >> "$ENVFILE"
    }
    echo "SSH gotowy: tunnel@127.0.0.1:${SSH_PORT} → ${NAME}:1521" >&2
}

# Portfel magazynu haseł (SEPS) dla testów Oracle Wallet (D53): .testdb/wallet z poświadczeniem aliasu DEV_PELIKAN_SEPS
# oraz .testdb/oracle-net-user/tnsnames.ora. mkstore z bibliotek PKI Oracle (Maven Central) i lokalnej Javy; hasła
# (portfela — losowe, nigdzie niezapisywane, i bazy testowej) przekazywane przez stdin, nie w argumentach.
wallet() {
    load_env
    local java_home java pki="$STATE/pki" w="$STATE/wallet" net="$STATE/oracle-net-user" v=21.23.0.0
    java_home="${JAVA_HOME:-$(/usr/libexec/java_home 2>/dev/null || true)}"
    java="$java_home/bin/java"
    [ -x "$java" ] || { echo "Brak Javy (JAVA_HOME) — portfel testowy pominięty" >&2; return 1; }
    mkdir -p "$pki"
    for a in oraclepki osdt_core osdt_cert; do
        [ -f "$pki/$a.jar" ] || curl -fsSL -o "$pki/$a.jar" "https://repo1.maven.org/maven2/com/oracle/database/security/$a/$v/$a-$v.jar"
    done
    local cp="$pki/oraclepki.jar:$pki/osdt_core.jar:$pki/osdt_cert.jar" wp
    wp="W$(openssl rand -hex 12)a1"
    rm -rf "$w"; mkdir -p "$w" "$net"; chmod 700 "$w"
    printf '%s\n%s\n' "$wp" "$wp" | "$java" -cp "$cp" oracle.security.pki.OracleSecretStoreTextUI -wrl "$w" -create >/dev/null
    printf '%s\n%s\n%s\n' "$PELIKAN_TESTDB_PASSWORD" "$PELIKAN_TESTDB_PASSWORD" "$wp" \
        | "$java" -cp "$cp" oracle.security.pki.OracleSecretStoreTextUI -wrl "$w" -createCredential dev_pelikan_seps "$PELIKAN_TESTDB_USER" >/dev/null
    echo "dev_pelikan_seps=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${PELIKAN_TESTDB_HOST:-127.0.0.1})(PORT=${PELIKAN_TESTDB_PORT:-$PORT}))(CONNECT_DATA=(SERVICE_NAME=${PELIKAN_TESTDB_SERVICE:-FREEPDB1})))" > "$net/tnsnames.ora"
    [ -f "$w/cwallet.sso" ] && echo "Portfel testowy: $w" >&2
}

# Workspace Manager (PD-CONN-009): obraz Oracle Free ma skrypty OWM w ORACLE_HOME, ale bez zainstalowanego WMSYS.
# owminst.plb w PDB testowej (kilka minut, raz), potem przestrzeń robocza DEV_PELIKAN_WS dla użytkownika testowego.
install_owm() {
    load_env
    local n log="$STATE/owm-install.log"
    n=$(printf "SET HEADING OFF\nSELECT COUNT(*) FROM dba_registry WHERE comp_id = 'OWM' AND status = 'VALID';\n" | sql_sys | tr -dc '0-9')
    if [ "${n:-0}" = "0" ]; then
        echo "Instaluję Workspace Manager (owminst.plb)…" >&2
        { printf 'CONNECT sys/"%s"@//localhost:1521/FREEPDB1 AS SYSDBA\n' "$PELIKAN_TESTDB_SYSTEM_PASSWORD"
          printf 'WHENEVER SQLERROR CONTINUE\nSET ECHO OFF\n@?/rdbms/admin/owminst.plb\nEXIT\n'
        } | docker exec -i "$NAME" bash -c "$SQLPLUS" > "$log" 2>&1 || true
        n=$(printf "SET HEADING OFF\nSELECT COUNT(*) FROM dba_registry WHERE comp_id = 'OWM' AND status = 'VALID';\n" | sql_sys | tr -dc '0-9')
        [ "${n:-0}" != "0" ] || { tail -30 "$log" >&2; echo "Instalacja Workspace Manager nie powiodła się (log: $log)" >&2; exit 1; }
    fi
    # GrantSystemPriv jako SYS kończy się ORA-06598 (pakiet WMSYS z prawami wywołującego) — rola administracyjna OWM
    # dla użytkownika testowego (tylko baza testowa), przestrzeń tworzy on sam.
    sql_sys <<SQL
GRANT WM_ADMIN_ROLE TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_WM TO $PELIKAN_TESTDB_USER;
SQL
    sql_as "$PELIKAN_TESTDB_USER" "$PELIKAN_TESTDB_PASSWORD" <<SQL
DECLARE
  n PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO n FROM all_workspaces WHERE workspace = 'DEV_PELIKAN_WS';
  IF n = 0 THEN DBMS_WM.CreateWorkspace('DEV_PELIKAN_WS'); END IF;
END;
/
SQL
    echo "Workspace Manager gotowy: przestrzeń DEV_PELIKAN_WS." >&2
}

ORDS_NAME="${PELIKAN_TESTDB_ORDS_CONTAINER:-pelikan-testdb-ords}"
ORDS_PORT="${PELIKAN_TESTDB_ORDS_PORT:-8181}"
ORDS_IMAGE="${PELIKAN_TESTDB_ORDS_IMAGE:-eclipse-temurin:21-jre}"

docker_net() {
    docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
    docker network inspect "$NET" | grep -q "\"$NAME\"" || docker network connect "$NET" "$NAME"
}

# ORDS tylko do testów (SD-ORDS-001, nigdy w Pelikanie): publiczne ords-latest.zip w .testdb/ords, samodzielny ORDS
# w kontenerze z JRE, w sieci Docker bazy testowej; instalacja schematu ORDS w PDB testowej (hasło SYS i nowe
# losowe hasło ORDS_PUBLIC_USER przez stdin), konfiguracja w wolumenie Dockera. HTTP tylko na 127.0.0.1.
ords_up() {
    load_env
    local dist="$STATE/ords" zip="$STATE/ords-dist/ords-latest.zip" vol="${ORDS_NAME}-config"
    if [ ! -x "$dist/bin/ords" ]; then
        mkdir -p "$STATE/ords-dist"
        [ -f "$zip" ] || curl -fsSL -o "$zip" https://download.oracle.com/otn_software/java/ords/ords-latest.zip
        rm -rf "$dist"; mkdir -p "$dist"
        unzip -q "$zip" -d "$dist"
    fi
    docker_net
    grep -q '^PELIKAN_TESTDB_ORDS_PASSWORD=' "$ENVFILE" || echo "PELIKAN_TESTDB_ORDS_PASSWORD=O$(rand)" >> "$ENVFILE"
    load_env
    local have
    have=$(printf "SET HEADING OFF\nSELECT COUNT(*) FROM dba_users WHERE username = 'ORDS_METADATA';\n" | sql_sys | tr -dc '0-9')
    if [ "${have:-0}" = "0" ] || ! docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "Instaluję ORDS w ${NAME}/FREEPDB1…" >&2
        docker rm -f "$ORDS_NAME" >/dev/null 2>&1 || true
        printf '%s\n%s\n' "$PELIKAN_TESTDB_SYSTEM_PASSWORD" "$PELIKAN_TESTDB_ORDS_PASSWORD" \
            | docker run --rm -i --network "$NET" -v "$dist:/opt/ords:ro" -v "$vol:/etc/ords/config" \
                -e JAVA_TOOL_OPTIONS=-Xmx512m "$ORDS_IMAGE" \
                /opt/ords/bin/ords --config /etc/ords/config install --admin-user "SYS AS SYSDBA" \
                --db-hostname "$NAME" --db-port 1521 --db-servicename FREEPDB1 \
                --feature-sdw false --feature-db-api false --feature-rest-enabled-sql false \
                --log-folder /tmp --password-stdin > "$STATE/ords-install.log" 2>&1 \
            || { tail -30 "$STATE/ords-install.log" >&2; echo "Instalacja ORDS nie powiodła się" >&2; exit 1; }
    fi
    if docker container inspect "$ORDS_NAME" >/dev/null 2>&1; then
        docker start "$ORDS_NAME" >/dev/null
    else
        docker run -d --name "$ORDS_NAME" --network "$NET" -p "127.0.0.1:${ORDS_PORT}:8080" \
            -v "$dist:/opt/ords:ro" -v "$vol:/etc/ords/config" -e JAVA_TOOL_OPTIONS=-Xmx512m "$ORDS_IMAGE" \
            /opt/ords/bin/ords --config /etc/ords/config serve --port 8080 >/dev/null
    fi
    for _ in $(seq 1 90); do
        # Dowolna odpowiedź HTTP (przekierowanie z /ords/, 404) — serwer działa.
        [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${ORDS_PORT}/ords/" || true)" != "000" ] && break
        sleep 2
    done
    grep -q '^PELIKAN_TESTDB_ORDS_URL=' "$ENVFILE" || echo "PELIKAN_TESTDB_ORDS_URL=http://127.0.0.1:${ORDS_PORT}/ords" >> "$ENVFILE"
    echo "ORDS gotowy: http://127.0.0.1:${ORDS_PORT}/ords → ${NAME}/FREEPDB1" >&2
}

# Parametr w sqlnet.ora katalogu użytkownika (.testdb/oracle-net-user) — każde polecenie zarządza swoimi wierszami.
net_set() {
    local f="$STATE/oracle-net-user/sqlnet.ora"
    mkdir -p "$STATE/oracle-net-user"
    touch "$f"
    grep -v -i "^$1=" "$f" > "$f.tmp" || true
    printf '%s=%s\n' "$1" "$2" >> "$f.tmp"
    mv "$f.tmp" "$f"
}

net_unset() {
    local f="$STATE/oracle-net-user/sqlnet.ora"
    [ -f "$f" ] || return 0
    grep -v -i "^$1=" "$f" > "$f.tmp" || true
    mv "$f.tmp" "$f"
    [ -s "$f" ] || rm -f "$f"
}

LDAP_NAME="${PELIKAN_TESTDB_LDAP_CONTAINER:-pelikan-testdb-ldap}"
LDAP_PORT="${PELIKAN_TESTDB_LDAP_PORT:-1389}"

# Nazewnictwo katalogowe (PD-CONN-013): OpenLDAP z własnym minimalnym schematem Oracle Net (scripts/testdb/ldap),
# alias DEV_PELIKAN_LDAP → baza testowa; po stronie klienta ldap.ora i sqlnet.ora (NAMES.DIRECTORY_PATH z LDAP)
# w .testdb/oracle-net-user — katalogu użytkownika, który Pelikan dołącza do swojego katalogu Oracle Net. Bez haseł:
# odczyt anonimowy, wpisy ładowane przez slapadd przy starcie kontenera.
ldap_up() {
    load_env
    local image=pelikan-test-ldap:1 dir="$STATE/ldap" net="$STATE/oracle-net-user"
    docker image inspect "$image" >/dev/null 2>&1 || docker build -q -t "$image" "$ROOT/scripts/testdb/ldap" >/dev/null
    mkdir -p "$dir" "$net"
    cat > "$dir/pelikan.ldif" <<LDIF
dn: dc=pelikan,dc=test
objectClass: dcObject
objectClass: organization
dc: pelikan
o: Pelikan test

dn: cn=OracleContext,dc=pelikan,dc=test
objectClass: orclContext
cn: OracleContext

dn: cn=dev_pelikan_ldap,cn=OracleContext,dc=pelikan,dc=test
objectClass: orclNetService
cn: dev_pelikan_ldap
orclNetDescString: (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${PELIKAN_TESTDB_HOST:-127.0.0.1})(PORT=${PELIKAN_TESTDB_PORT:-$PORT}))(CONNECT_DATA=(SERVICE_NAME=${PELIKAN_TESTDB_SERVICE:-FREEPDB1})))
LDIF
    docker rm -f "$LDAP_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$LDAP_NAME" -p "127.0.0.1:${LDAP_PORT}:389" -v "$dir:/ldif:ro" "$image" >/dev/null
    for _ in $(seq 1 30); do
        docker exec "$LDAP_NAME" ldapsearch -x -H ldap://127.0.0.1 -b "cn=OracleContext,dc=pelikan,dc=test" "(cn=dev_pelikan_ldap)" cn 2>/dev/null \
            | grep -q '^cn: dev_pelikan_ldap' && break
        sleep 1
    done
    printf 'DIRECTORY_SERVERS=(127.0.0.1:%s)\nDEFAULT_ADMIN_CONTEXT="dc=pelikan,dc=test"\nDIRECTORY_SERVER_TYPE=OID\n' "$LDAP_PORT" > "$net/ldap.ora"
    # TNSNAMES przed LDAP (portfel SEPS z tnsnames.ora), EZCONNECT na końcu — przy zatrzymanym LDAP odmowa połączenia
    # na 127.0.0.1 jest natychmiastowa.
    net_set NAMES.DIRECTORY_PATH "(TNSNAMES, LDAP, EZCONNECT)"
    echo "LDAP gotowy: ldap://127.0.0.1:${LDAP_PORT}, alias dev_pelikan_ldap → ${PELIKAN_TESTDB_HOST:-127.0.0.1}:${PELIKAN_TESTDB_PORT:-$PORT}" >&2
}

ldap_down() {
    docker rm -f "$LDAP_NAME" >/dev/null 2>&1 || true
    rm -f "$STATE/oracle-net-user/ldap.ora"
    net_unset NAMES.DIRECTORY_PATH
    echo "Usunięto ${LDAP_NAME} i konfigurację LDAP klienta" >&2
}

KDC_NAME="${PELIKAN_TESTDB_KDC_CONTAINER:-pelikan-testdb-kdc}"
KDC_PORT="${PELIKAN_TESTDB_KDC_PORT:-1088}"

# Kerberos (PD-CONN-014): KDC MIT w kontenerze (scripts/testdb/kdc), realm PELIKAN.TEST. Serwer bazy: tablica kluczy
# usługi oracle/localhost i sqlnet.ora z KERBEROS5; użytkownik DEV_KRB IDENTIFIED EXTERNALLY AS 'dev_krb@PELIKAN.TEST'.
# Klient: pamięć podręczna biletów (TGT i bilet usługi z kinit -k w KDC, bez haseł) i krb5.conf w .testdb/kerberos,
# sqlnet.ora klienta z parametrami Kerberos w .testdb/kerberos/net (użycie: kdc-linux; na macOS zob. D-ENV-4).
kdc_up() {
    load_env
    local image=pelikan-test-kdc:1 k="$STATE/kerberos"
    docker image inspect "$image" >/dev/null 2>&1 || docker build -q -t "$image" "$ROOT/scripts/testdb/kdc" >/dev/null
    docker_net
    if docker container inspect "$KDC_NAME" >/dev/null 2>&1; then
        docker start "$KDC_NAME" >/dev/null
    else
        docker run -d --name "$KDC_NAME" --network "$NET" -p "127.0.0.1:${KDC_PORT}:88/tcp" -p "127.0.0.1:${KDC_PORT}:88/udp" "$image" >/dev/null
    fi
    for _ in $(seq 1 30); do
        docker exec "$KDC_NAME" test -s /out/dev_krb.keytab 2>/dev/null && break
        sleep 1
    done
    mkdir -p "$k"; chmod 700 "$k"
    # Principal usługi bazy: klient Oracle prosi o bilet dla oracle/<nazwa hosta serwera bazy> (nazwa kontenera
    # z odpowiedzi serwera, nie host z deskryptora) — principal dla tej nazwy i dla localhost, losowe klucze.
    local dbhost
    dbhost="$(docker exec "$NAME" cat /proc/sys/kernel/hostname)"
    docker exec -e DBHOST="$dbhost" "$KDC_NAME" sh -c '
        for h in localhost "$DBHOST"; do
            kadmin.local -q "getprinc oracle/$h@PELIKAN.TEST" 2>/dev/null | grep -q "^Principal:" \
                || kadmin.local -q "addprinc -randkey oracle/$h@PELIKAN.TEST" >/dev/null 2>&1
        done
        rm -f /out/oracle.keytab
        kadmin.local -q "ktadd -norandkey -k /out/oracle.keytab oracle/localhost@PELIKAN.TEST oracle/$DBHOST@PELIKAN.TEST" >/dev/null
        chmod 644 /out/oracle.keytab'
    # Bilety użytkownika: TGT z tablicy kluczy i od razu bilety usługi bazy — klient nie musi kontaktować się z KDC.
    docker exec -e DBHOST="$dbhost" "$KDC_NAME" sh -c 'rm -f /tmp/dev_krb.cc && kinit -k -t /out/dev_krb.keytab -c FILE:/tmp/dev_krb.cc dev_krb@PELIKAN.TEST && kvno -q -c FILE:/tmp/dev_krb.cc oracle/localhost@PELIKAN.TEST "oracle/$DBHOST@PELIKAN.TEST"'
    docker cp "$KDC_NAME:/tmp/dev_krb.cc" "$k/ccache" >/dev/null
    chmod 600 "$k/ccache"
    sed "s/kdc = 127.0.0.1:88/kdc = 127.0.0.1:${KDC_PORT}/" "$ROOT/scripts/testdb/kdc/krb5.conf" > "$k/krb5.conf"
    # Serwer bazy: tablica kluczy usługi i konfiguracja Kerberos (docker cp tworzy pliki jako root — chown).
    docker cp "$KDC_NAME:/out/oracle.keytab" "$k/oracle.keytab" >/dev/null
    docker exec -u root "$NAME" mkdir -p /opt/oracle/krb5
    docker cp "$k/oracle.keytab" "$NAME:/opt/oracle/krb5/v5srvtab"
    docker cp "$ROOT/scripts/testdb/kdc/krb5.conf" "$NAME:/opt/oracle/krb5/krb5.conf"
    rm -f "$k/oracle.keytab"
    docker exec -u root "$NAME" sh -c 'chown -R oracle /opt/oracle/krb5 && chmod 600 /opt/oracle/krb5/v5srvtab'
    # Katalog klienta narzędzi skryptu (sqlplus w kontenerze) — sqlnet.ora serwera bez bloku Kerberos.
    docker exec "$NAME" bash -c 'mkdir -p /opt/oracle/client-net && sed "/^# PELIKAN-KERBEROS/,/^# PELIKAN-KERBEROS-END/d" $ORACLE_HOME/network/admin/sqlnet.ora > /opt/oracle/client-net/sqlnet.ora'
    docker exec -i "$NAME" bash -c 'f=$ORACLE_HOME/network/admin/sqlnet.ora; sed -i "/^# PELIKAN-KERBEROS/,/^# PELIKAN-KERBEROS-END/d" "$f"; cat >> "$f"' <<'ORA'
# PELIKAN-KERBEROS (scripts/testdb.sh kdc-up)
SQLNET.AUTHENTICATION_SERVICES=(BEQ, KERBEROS5)
SQLNET.AUTHENTICATION_KERBEROS5_SERVICE=oracle
SQLNET.KERBEROS5_KEYTAB=/opt/oracle/krb5/v5srvtab
SQLNET.KERBEROS5_CONF=/opt/oracle/krb5/krb5.conf
SQLNET.KERBEROS5_CONF_MIT=TRUE
# PELIKAN-KERBEROS-END
ORA
    sql_sys <<SQL
DECLARE
  n PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'DEV_KRB';
  IF n = 0 THEN EXECUTE IMMEDIATE q'[CREATE USER DEV_KRB IDENTIFIED EXTERNALLY AS 'dev_krb@PELIKAN.TEST']'; END IF;
END;
/
GRANT CREATE SESSION TO DEV_KRB;
SQL
    # Konfiguracja klienta osobno w .testdb/kerberos/net: Instant Client dla macOS nie może jej używać w procesie
    # z Kerberos.framework (D-ENV-4) — w katalogu użytkownika zablokowałaby wszystkie testy bazy na macOS.
    mkdir -p "$k/net"
    krb_client_sqlnet "$k" > "$k/net/sqlnet.ora"
    grep -q '^PELIKAN_TESTDB_KERBEROS_USER=' "$ENVFILE" || echo "PELIKAN_TESTDB_KERBEROS_USER=DEV_KRB" >> "$ENVFILE"
    echo "Kerberos gotowy: KDC 127.0.0.1:${KDC_PORT}, realm PELIKAN.TEST, użytkownik bazy DEV_KRB (bilety: $k/ccache)" >&2
}

krb_client_sqlnet() {
    printf 'SQLNET.AUTHENTICATION_SERVICES=(KERBEROS5)\nSQLNET.AUTHENTICATION_KERBEROS5_SERVICE=oracle\n'
    printf 'SQLNET.KERBEROS5_CONF=%s/krb5.conf\nSQLNET.KERBEROS5_CONF_MIT=TRUE\nSQLNET.KERBEROS5_CC_NAME=%s/ccache\n' "$1" "$1"
}

# Test Kerberos przez Instant Client dla Linuksa (ścieżka CI): pakiet w .linux-build, kontener swift:6.3-noble w sieci
# Docker bazy testowej, Instant Client Basic Light w .testdb/instantclient-linux. Konfiguracja testów w
# .linux-build/.testdb (poza repozytorium, 0600); baza pod nazwą kontenera, więc CI=1 (TestDatabase dopuszcza wtedy
# host spoza 127.0.0.1). Bilety z kdc-up — klient nie kontaktuje się z KDC.
kdc_linux() {
    load_env
    [ -s "$STATE/kerberos/ccache" ] || { echo "Najpierw: scripts/testdb.sh kdc-up" >&2; exit 1; }
    local ic="$STATE/instantclient-linux" lb="$ROOT/.linux-build" arch
    case "$(docker info --format '{{.Architecture}}' 2>/dev/null)" in aarch64|arm64) arch=arm64 ;; *) arch=x64 ;; esac
    if [ ! -f "$ic/libclntsh.so" ]; then
        rm -rf "$ic" "$ic.tmp"; mkdir -p "$ic.tmp"
        curl -fsSL -o "$ic.tmp/ic.zip" "https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linux-${arch}.zip"
        unzip -q "$ic.tmp/ic.zip" -d "$ic.tmp"
        mv "$ic.tmp"/instantclient_* "$ic"
        rm -rf "$ic.tmp"
    fi
    mkdir -p "$lb"
    rsync -a --delete --exclude .build --exclude .swiftpm --exclude .testdb "$ROOT/Packages/PelikanKit/" "$lb/"
    local t="$lb/.testdb"
    rm -rf "$t"; mkdir -p "$t/oracle-net-user" "$t/kerberos"; chmod 700 "$t"
    cp "$STATE/kerberos/ccache" "$STATE/kerberos/krb5.conf" "$t/kerberos/"
    krb_client_sqlnet /src/.testdb/kerberos > "$t/oracle-net-user/sqlnet.ora"
    (umask 077
     printf 'PELIKAN_TESTDB_HOST=%s\nPELIKAN_TESTDB_PORT=1521\nPELIKAN_TESTDB_SERVICE=%s\n' "$NAME" "${PELIKAN_TESTDB_SERVICE:-FREEPDB1}" > "$t/env"
     printf 'PELIKAN_TESTDB_USER=%s\nPELIKAN_TESTDB_PASSWORD=%s\nPELIKAN_TESTDB_KERBEROS_USER=DEV_KRB\n' "$PELIKAN_TESTDB_USER" "$PELIKAN_TESTDB_PASSWORD" >> "$t/env")
    docker run --rm --network "$NET" -v "$lb:/src" -v "$ic:/opt/oracle/instantclient:ro" -w /src \
        -e CI=1 -e PELIKAN_OCI_LIB_DIR=/opt/oracle/instantclient -e LD_LIBRARY_PATH=/opt/oracle/instantclient \
        swift:6.3-noble bash -c 'apt-get update -qq >/dev/null && apt-get install -y -qq libaio1t64 >/dev/null \
            && a=$(ls /usr/lib/*-linux-gnu/libaio.so.1t64) && ln -sf "$a" "${a%t64}" \
            && swift test --filter "KerberosTests|KerberosGuardTests" 2>&1 | grep -E "✔|✘|error:|passed|failed|recorded"'
}

kdc_down() {
    docker rm -f "$KDC_NAME" >/dev/null 2>&1 || true
    rm -rf "$STATE/kerberos"
    if container_exists; then
        docker exec "$NAME" bash -c 'sed -i "/^# PELIKAN-KERBEROS/,/^# PELIKAN-KERBEROS-END/d" $ORACLE_HOME/network/admin/sqlnet.ora && rm -rf /opt/oracle/client-net' || true
    fi
    echo "Usunięto ${KDC_NAME} i konfigurację Kerberos" >&2
}

case "${1:-}" in
    kdc-up) kdc_up ;;
    kdc-down) kdc_down ;;
    kdc-linux) kdc_linux ;;
    ldap-up) ldap_up ;;
    ldap-down) ldap_down ;;
    ords-up) ords_up ;;
    ords-down) docker rm -f "$ORDS_NAME" >/dev/null 2>&1; echo "Usunięto ${ORDS_NAME} (ORDS zostaje w bazie)" ;;
    owm) install_owm ;;
    wallet) wallet ;;
    ssh-up) ssh_up ;;
    ssh-down) docker rm -f "$SSH_NAME" >/dev/null 2>&1; echo "Usunięto ${SSH_NAME}" ;;
    up) up ;;
    seed) seed ;;
    down) docker stop "$NAME" >/dev/null && echo "Zatrzymano ${NAME}" ;;
    reset)
        docker rm -f "$NAME" >/dev/null 2>&1 || true
        up
        seed
        ;;
    env)
        load_env
        env | grep '^PELIKAN_TESTDB_' | sed 's/^/export /'
        ;;
    sql)
        load_env
        u="${2:-SYSTEM}"
        case "$u" in
            SYSTEM) sql_as SYSTEM "$PELIKAN_TESTDB_SYSTEM_PASSWORD" ;;
            SYS) sql_sys ;;
            AGENT) sql_as "$PELIKAN_TESTDB_AGENT_USER" "$PELIKAN_TESTDB_AGENT_PASSWORD" ;;
            *) sql_as "$PELIKAN_TESTDB_USER" "$PELIKAN_TESTDB_PASSWORD" ;;
        esac
        ;;
    *)
        echo "Użycie: $0 up | seed | wallet | reset | down | env | sql [SYSTEM|SYS|TEST|AGENT] | ssh-up | ssh-down | owm" >&2
        echo "        | ords-up | ords-down | ldap-up | ldap-down | kdc-up | kdc-down | kdc-linux" >&2
        exit 2
        ;;
esac
