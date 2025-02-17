# DHCP Dockerfile ~/lab_infra/dhcp/src/Dockerfile

FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y isc-dhcp-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy default configuration
COPY config/dhcpd.conf /etc/dhcp/

EXPOSE 67/udp 68/udp

CMD ["/usr/sbin/dhcpd", "-f", "-d", "--no-pid", "-cf", "/etc/dhcp/dhcpd.conf"]
