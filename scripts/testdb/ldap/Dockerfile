# OpenLDAP do testów nazewnictwa katalogowego Oracle Net Pelikana (PD-CONN-013). Wpisy z /ldif/*.ldif ładowane
# przez slapadd przy każdym starcie (scripts/testdb.sh ldap-up generuje je z portem bazy testowej).
FROM alpine:3.20
RUN apk add --no-cache openldap openldap-back-mdb openldap-clients \
 && mkdir -p /run/openldap /var/lib/openldap/pelikan /ldif
COPY oraclenet-min.schema /etc/openldap/schema/oraclenet-min.schema
COPY slapd.conf /etc/openldap/slapd.conf
EXPOSE 389
CMD ["/bin/sh", "-c", "rm -rf /var/lib/openldap/pelikan/* && cat /ldif/*.ldif | slapadd -f /etc/openldap/slapd.conf && exec slapd -f /etc/openldap/slapd.conf -h ldap:/// -d stats"]
