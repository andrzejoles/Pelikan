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
GRANT SELECT ON V_\$SQL TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$MYSTAT TO $PELIKAN_TESTDB_USER;
GRANT SELECT ON V_\$STATNAME TO $PELIKAN_TESTDB_USER;
GRANT EXECUTE ON DBMS_LOCK TO $PELIKAN_TESTDB_USER;
GRANT CREATE SESSION TO $PELIKAN_TESTDB_AGENT_USER;
SQL
    install_utplsql
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
    docker image inspect pelikan-test-sshd >/dev/null 2>&1 || docker build -q -t pelikan-test-sshd "$ROOT/scripts/testdb/ssh" >/dev/null
    if ! docker container inspect "$SSH_NAME" >/dev/null 2>&1; then
        docker run -d --name "$SSH_NAME" --network "$NET" -p "127.0.0.1:${SSH_PORT}:22" pelikan-test-sshd >/dev/null
    else
        docker start "$SSH_NAME" >/dev/null
    fi
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

case "${1:-}" in
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
        echo "Użycie: $0 up | seed | reset | down | env | sql [SYSTEM|SYS|TEST|AGENT]" >&2
        exit 2
        ;;
esac
