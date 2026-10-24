#!/bin/sh
# KDC testów Pelikana: baza principali tworzona raz (stan w kontenerze), potem krb5kdc na pierwszym planie.
set -eu
if [ ! -f /var/lib/krb5kdc/principal ]; then
    # Główne hasło bazy KDC: losowe, zapisane tylko w pliku stash (-s), nigdzie poza kontenerem.
    master="$(head -c 24 /dev/urandom | base64)"
    printf '%s\n%s\n' "$master" "$master" | kdb5_util create -s -r PELIKAN.TEST >/dev/null
    unset master
    kadmin.local -q "addprinc -randkey dev_krb@PELIKAN.TEST" >/dev/null
fi
# Principal usługi bazy (oracle/<host>) dodaje scripts/testdb.sh kdc-up — nazwa hosta kontenera bazy jest znana dopiero tam.
rm -f /out/dev_krb.keytab
kadmin.local -q "ktadd -norandkey -k /out/dev_krb.keytab dev_krb@PELIKAN.TEST" >/dev/null
chmod 644 /out/*.keytab
exec krb5kdc -n
