# KDC MIT Kerberos do testów uwierzytelniania Kerberos Pelikana (PD-CONN-014), tylko środowisko testowe.
# Przy pierwszym starcie: realm PELIKAN.TEST, główne hasło bazy KDC losowe i tylko w pliku stash wewnątrz kontenera,
# principal użytkownika z losowym kluczem (bez hasła), tablica kluczy w /out.
FROM alpine:3.20
RUN apk add --no-cache krb5 krb5-server
COPY krb5.conf /etc/krb5.conf
COPY kdc.conf /var/lib/krb5kdc/kdc.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh && mkdir -p /out
EXPOSE 88
CMD ["/entrypoint.sh"]
