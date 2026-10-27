# Serwer SSH do testów tunelu Pelikana (tylko środowisko testowe: `tunnel` — klucz, `haslo` — hasło ustawiane
# przy starcie przez scripts/testdb.sh; przekierowanie portów).
FROM alpine:3.24
RUN apk add --no-cache openssh \
 && ssh-keygen -A \
 && adduser -D -s /bin/sh tunnel \
 && adduser -D -s /bin/sh haslo \
 && sed -i 's/^tunnel:!/tunnel:*/' /etc/shadow \
 && mkdir -p /home/tunnel/.ssh && chmod 700 /home/tunnel/.ssh && chown tunnel:tunnel /home/tunnel/.ssh
COPY sshd_config /etc/ssh/sshd_config
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
