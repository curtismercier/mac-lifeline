# mac-tunnel — minimal hardened SSH rendezvous for a reverse tunnel from the target Mac.
# Purpose: accept ONE thing — a reverse port-forward from the Mac's tunnel key.
# No shell, no local forwarding, no host access. Disposable.
FROM alpine:3.20

RUN apk add --no-cache openssh \
    && adduser -D -s /sbin/nologin tunnel \
    && sed -i 's/^tunnel:!:/tunnel:*:/' /etc/shadow \
    && mkdir -p /home/tunnel/.ssh \
    && chmod 700 /home/tunnel/.ssh \
    && chown -R tunnel:tunnel /home/tunnel/.ssh \
    && ssh-keygen -A \
    && rm -f /etc/motd

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
