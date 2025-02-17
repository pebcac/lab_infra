FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y bind9 bind9utils bind9-doc dnsutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Get root hints file
RUN curl -o /etc/bind/named.ca https://www.internic.net/domain/named.root

# Create required directories
RUN mkdir -p /var/run/named && \
    mkdir -p /var/cache/bind && \
    chown -R bind:bind /var/run/named /var/cache/bind

EXPOSE 53/tcp 53/udp

CMD ["/usr/sbin/named", "-g", "-c", "/etc/bind/named.conf", "-u", "bind"]
