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
    } | docker exec -i "$NAME" sqlplus -S -L /nolog
}

sql_sys() {
    { printf 'CONNECT sys/"%s"@//localhost:1521/FREEPDB1 AS SYSDBA\n' "$PELIKAN_TESTDB_SYSTEM_PASSWORD"
      printf 'WHENEVER SQLERROR EXIT SQL.SQLCODE\nSET FEEDBACK OFF\nSET SERVEROUTPUT ON\n'
      cat
      printf '\nEXIT\n'
    } | docker exec -i "$NAME" sqlplus -S -L /nolog
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
         } | docker exec -i -w /tmp/utPLSQL/source "$NAME" sqlplus -S -L /nolog > "$log" 2>&1; then
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

case "${1:-}" in
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
        echo "Użycie: $0 up | seed | wallet | reset | down | env | sql [SYSTEM|SYS|TEST|AGENT]" >&2
        exit 2
        ;;
esac
