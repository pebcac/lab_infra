# Lab Infrastructure Deployment

This repository contains scripts and configurations for deploying core infrastructure services (DNS, DHCP, and NFS) for a lab environment supporting multiple OpenShift clusters.

## Overview

The deployment script sets up:
- DNS server (BIND) configured for multiple OpenShift clusters
- DHCP server with specific subnet configurations
- NFS server with exports for shared storage
- All services are containerized using Podman
- Systemd service configurations for automatic startup

## Prerequisites

- RHEL/CentOS/Fedora-based system
- Podman installed
- Systemd
- SELinux (optional but supported)
- Firewalld
- User with sudo privileges
- ZSH shell with oh-my-zsh

## Network Requirements

- Available IP range: 192.168.10.0/24
- DNS server IP: 192.168.10.2
- Available ports:
  - DNS: 53 (TCP/UDP)
  - DHCP: 67/68 (UDP)
  - NFS: 2049 (TCP), 111 (TCP/UDP)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/lab-infra.git
cd lab-infra

2. Review and modify configurations if needed:
  - DHCP ranges in dhcp/config/dhcpd.conf
  - DNS records in dns/config/db.lab.com
  - NFS exports in the deployment script

3. Run the deployment script:

``` bash
chmod +x deploy.sh
./deploy.sh
```

## Verification

After deployment, verify the services:

1. DNS Resolution:

``` bash
# Test forward lookup
dig @192.168.10.2 infra.lab.com

# Test reverse lookup
dig @192.168.10.2 -x 192.168.10.2

# Test OpenShift DNS
dig @192.168.10.2 api.partner.lab.com
dig @192.168.10.2 console-openshift-console.apps.partner.lab.com
```

2. DHCP Service:

``` bash
sudo nmap -sU -p 67 192.168.10.2
```

3. NFS Exports:

``` bash
showmount -e 192.168.10.2
```

## Troubleshooting

### DNS Issues

- Check named logs: podman logs dns-server
- Verify zone files syntax: named-checkzone lab.com /path/to/db.lab.com
- Test DNS resolution: dig @192.168.10.2 infra.lab.com

### DHCP Issues

- Check DHCP logs: podman logs dhcp-server
- Verify DHCP configuration: dhcpd -t -cf /path/to/dhcpd.conf
- Monitor DHCP requests: tcpdump -i any port 67 or port 68

## NFS Issues

- Check NFS status: systemctl status nfs-server
- Verify exports: exportfs -v
- Check mount access: showmount -e 192.168.10.2

## Contributing

- Fork the repository
- Create a feature branch
- Commit your changes
- Push to the branch
- Create a Pull Request
