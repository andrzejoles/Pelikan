# Serwer SSH do testów tunelu Pelikana (tylko środowisko testowe: logowanie kluczem, przekierowanie portów).
FROM alpine:3.20
RUN apk add --no-cache openssh \
 && ssh-keygen -A \
 && adduser -D -s /bin/sh tunnel \
 && sed -i 's/^tunnel:!/tunnel:*/' /etc/shadow \
 && mkdir -p /home/tunnel/.ssh && chmod 700 /home/tunnel/.ssh && chown tunnel:tunnel /home/tunnel/.ssh
COPY sshd_config /etc/ssh/sshd_config
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
