# DNS Dockerfile ~/lab_infra/dns/src/Dockerfile

FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y bind9 bind9utils bind9-doc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /var/run/named && \
    mkdir -p /var/cache/bind && \
    chown -R bind:bind /var/run/named /var/cache/bind

# Copy default configuration
COPY config/named.conf /etc/bind/
COPY config/lab.local.zone /etc/bind/

EXPOSE 53/tcp 53/udp

CMD ["/usr/sbin/named", "-g", "-c", "/etc/bind/named.conf", "-u", "bind"]
