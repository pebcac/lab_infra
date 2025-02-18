#!/bin/zsh

# Set script to exit on error
set -e

check_prerequisites() {
    echo "Checking and installing prerequisites..."

    # Check if running on RHEL/CentOS/Fedora
    if command -v dnf &> /dev/null; then
        echo "Installing required packages using dnf..."
        sudo dnf install -y bind-utils bind dhcp-server nfs-utils &> /dev/null
    elif command -v yum &> /dev/null; then
        echo "Installing required packages using yum..."
        sudo yum install -y bind-utils bind dhcp nfs-utils &> /dev/null
    else
        echo "❌ Unsupported package manager. Please install packages manually."
        return 1
    fi

    # Verify NFS service exists
    if ! systemctl list-unit-files | grep -q nfs-server.service; then
        echo "❌ NFS server service not found after installation"
        return 1
    fi

    echo "✓ Prerequisites installed"
    return 0
}

validate_configs() {
    echo "Validating configurations..."

    # Create temporary directories for validation with proper error handling
    echo "Setting up validation environment..."

    # DNS validation setup
    sudo mkdir -p /etc/bind /var/lib/bind || {
        echo "Failed to create DNS directories"
        return 1
    }
    sudo chown $USER:$USER /etc/bind /var/lib/bind

    # Copy DNS files
    cp ~/lab-infra/dns/config/* /etc/bind/ || {
        echo "Failed to copy DNS configuration files"
        return 1
    }

    # Validate DNS configuration
    if ! sudo named-checkconf /etc/bind/named.conf; then
        echo "❌ DNS configuration validation failed"
        return 1
    fi

    # Validate zone files
    if ! sudo named-checkzone lab.com /etc/bind/db.lab.com; then
        echo "❌ Forward zone validation failed"
        return 1
    fi

    if ! sudo named-checkzone 10.168.192.in-addr.arpa /etc/bind/db.10.168.192; then
        echo "❌ Reverse zone validation failed"
        return 1
    fi

    # DHCP validation setup
    sudo mkdir -p /etc/dhcp || {
        echo "Failed to create DHCP configuration directory"
        return 1
    }
    sudo mkdir -p /var/lib/dhcp || {
        echo "Failed to create DHCP lease directory"
        return 1
    }

    # Create and set permissions for DHCP files
    sudo touch /var/lib/dhcp/dhcpd.leases || {
        echo "Failed to create DHCP lease file"
        return 1
    }

    sudo chown -R $USER:$USER /etc/dhcp /var/lib/dhcp || {
        echo "Failed to set DHCP directory permissions"
        return 1
    }

    # Copy DHCP configuration
    cp ~/lab-infra/dhcp/config/dhcpd.conf /etc/dhcp/ || {
        echo "Failed to copy DHCP configuration"
        return 1
    }

    # Validate DHCP configuration
    if ! sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf; then
        echo "❌ DHCP configuration validation failed"
        return 1
    fi

    # Cleanup
    echo "Cleaning up validation environment..."
    sudo rm -rf /etc/bind/* || true
    sudo rm -rf /etc/dhcp/* || true
    sudo rm -rf /var/lib/dhcp/* || true

    echo "✓ All configurations validated successfully"
    return 0
}

# Function to cleanup existing files and directories
cleanup_existing() {
    echo "Checking for existing files and directories..."

    # Clean existing configuration files
    [[ -f ~/lab-infra/dns/config/named.conf ]] && rm -f ~/lab-infra/dns/config/named.conf
    [[ -f ~/lab-infra/dns/config/db.lab.com ]] && rm -f ~/lab-infra/dns/config/db.lab.com
    [[ -f ~/lab-infra/dns/config/db.10.168.192 ]] && rm -f ~/lab-infra/dns/config/db.10.168.192
    [[ -f ~/lab-infra/dhcp/config/dhcpd.conf ]] && rm -f ~/lab-infra/dhcp/config/dhcpd.conf
    [[ -f ~/.config/systemd/user/container-dns-server.service ]] && rm -f ~/.config/systemd/user/container-dns-server.service
    [[ -f ~/.config/systemd/user/container-dhcp-server.service ]] && rm -f ~/.config/systemd/user/container-dhcp-server.service

    # Clean Dockerfiles
    [[ -f ~/lab-infra/dns/src/Dockerfile ]] && rm -f ~/lab-infra/dns/src/Dockerfile
    [[ -f ~/lab-infra/dhcp/src/Dockerfile ]] && rm -f ~/lab-infra/dhcp/src/Dockerfile

    # Clean directories but preserve the structure
    # Use setopt/unsetopt to temporarily disable error on no matches
    setopt local_options no_nomatch
    [[ -d ~/lab-infra/dns/data ]] && rm -rf ~/lab-infra/dns/data/*
    [[ -d ~/lab-infra/dhcp/data ]] && rm -rf ~/lab-infra/dhcp/data/*
    sudo rm -rf /var/named/data/* 2>/dev/null || true
    sudo rm -rf /var/named/dynamic/* 2>/dev/null || true
    sudo rm -rf /exports/* 2>/dev/null || true

    echo "✓ Cleanup completed"
}

echo "Starting infrastructure deployment..."

# Check and install prerequisites first
if ! check_prerequisites; then
    echo "Failed to install prerequisites. Please install them manually."
    exit 1
fi

# Run cleanup first
cleanup_existing

# Create necessary directories
echo "Creating directory structure..."
mkdir -p ~/lab-infra/{dns,dhcp,nfs}/{config,data,src}
sudo mkdir -p /var/named/{data,dynamic}
sudo mkdir -p /exports/{home,data,apps}
echo "✓ Directory structure created"

# Create DNS Dockerfile
echo "Creating DNS Dockerfile..."
cat > ~/lab-infra/dns/src/Dockerfile << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y bind9 bind9utils bind9-doc dnsutils curl && \
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
EOF
echo "✓ DNS Dockerfile created"

# Create DHCP Dockerfile
echo "Creating DHCP Dockerfile..."
cat > ~/lab-infra/dhcp/src/Dockerfile << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y isc-dhcp-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create required directories and lease file
RUN mkdir -p /var/lib/dhcp && \
    touch /var/lib/dhcp/dhcpd.leases

EXPOSE 67/udp 68/udp

CMD ["/usr/sbin/dhcpd", "-f", "-d", "--no-pid", "-cf", "/etc/dhcp/dhcpd.conf"]
EOF
echo "✓ DHCP Dockerfile created"

# Create DNS configuration files
echo "Creating DNS configuration files..."
cat > ~/lab-infra/dns/config/named.conf << 'EOF'
options {
        listen-on port 53 { 127.0.0.1; 192.168.10.2; };
        listen-on-v6 port 53 { none; };
        directory       "/etc/bind";
        dump-file       "/var/lib/bind/cache_dump.db";
        statistics-file "/var/lib/bind/named_stats.txt";
        memstatistics-file "/var/lib/bind/named_mem_stats.txt";
        secroots-file   "/var/lib/bind/named.secroots";
        recursing-file  "/var/lib/bind/named.recursing";
        allow-query     { any; };
        forwarders      { 1.1.1.1; 1.0.0.1; };
        recursion yes;
        dnssec-validation no;
        managed-keys-directory "/var/lib/bind";
        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";
};

logging {
        channel default_debug {
                file "named.run";
                severity dynamic;
        };
};

zone "lab.com" IN {
    type master;
    file "/etc/bind/db.lab.com";
};

zone "10.168.192.in-addr.arpa" IN {
    type master;
    file "/etc/bind/db.10.168.192";
};

zone "." IN {
        type hint;
        file "/etc/bind/named.ca";
};
EOF

echo "✓ Named configuration created"

# Create forward zone file
echo "Creating forward zone file..."
cat > ~/lab-infra/dns/config/db.lab.com << 'EOF'
$TTL 604800
@       IN      SOA     infra.lab.com. admin.lab.com. (
                     2024021701         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

; Name servers
@       IN      NS      infra.lab.com.

; Infrastructure
infra           IN      A       192.168.10.2

; Partner hosts and OpenShift entries
idclab695.partner  IN   A       192.168.10.10
api.partner       IN   A       192.168.10.10
api-int.partner   IN   A       192.168.10.10
*.apps.partner    IN   A       192.168.10.10
oauth-openshift.apps.partner IN A 192.168.10.10
console-openshift-console.apps.partner IN A 192.168.10.10

; Engineering hosts and OpenShift entries
idclab479.engg    IN   A       192.168.10.104
api.engg          IN   A       192.168.10.104
api-int.engg      IN   A       192.168.10.104
*.apps.engg       IN   A       192.168.10.104
oauth-openshift.apps.engg IN A 192.168.10.104

; Cluster hosts and OpenShift entries
idclab647.clust   IN   A       192.168.10.165
idclab648.clust   IN   A       192.168.10.166
api.clust         IN   A       192.168.10.165
api-int.clust     IN   A       192.168.10.165
*.apps.clust      IN   A       192.168.10.165
oauth-openshift.apps.clust IN A 192.168.10.165

; KVM hosts and OpenShift entries
idclab649.kvm     IN   A       192.168.10.177
idclab484.kvm     IN   A       192.168.10.178
api.kvm           IN   A       192.168.10.177
api-int.kvm       IN   A       192.168.10.177
*.apps.kvm        IN   A       192.168.10.177
oauth-openshift.apps.kvm IN A 192.168.10.177

; CICD hosts and OpenShift entries
idclab650.cicd    IN   A       192.168.10.198
api.cicd          IN   A       192.168.10.198
api-int.cicd      IN   A       192.168.10.198
*.apps.cicd       IN   A       192.168.10.198
oauth-openshift.apps.cicd IN A 192.168.10.198
EOF
echo "✓ Forward zone file created"

# Create reverse zone file
echo "Creating reverse zone file..."
cat > ~/lab-infra/dns/config/db.10.168.192 << 'EOF'
$TTL    604800
@       IN      SOA     infra.lab.com. root.lab.com. (
                     2024021701         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      infra.lab.com.
@       IN      A       192.168.10.2

; Infrastructure
2       IN      PTR     infra.lab.com.

; Partner hosts
10      IN      PTR     idclab695.partner.lab.com.

; Engineering hosts
104     IN      PTR     idclab479.engg.lab.com.

; Cluster hosts
165     IN      PTR     idclab647.clust.lab.com.
166     IN      PTR     idclab648.clust.lab.com.

; KVM hosts
177     IN      PTR     idclab649.kvm.lab.com.
178     IN      PTR     idclab484.kvm.lab.com.

; CICD hosts
198     IN      PTR     idclab650.cicd.lab.com.
EOF
echo "✓ Reverse zone file created"

# Create DHCP configuration file
echo "Creating DHCP configuration file..."
cat > ~/lab-infra/dhcp/config/dhcpd.conf << 'EOF'
default-lease-time 600;
max-lease-time 7200;

# Common Options for all subnets:
option domain-name-servers 192.168.10.2;
option ntp-servers 192.168.10.2;
authoritative;

# Class definitions
class "partner-hosts" {
    match if substring (hardware, 1, 3) = 10:70:fd;
}

class "engg-hosts" {
    match if substring (hardware, 1, 3) = 10:70:fd;
}

class "ocp-clust-hosts" {
    match if substring (hardware, 1, 3) = 10:70:fd;
}

class "ocp-kvm-hosts" {
    match if substring (hardware, 1, 3) = 10:70:fd;
}

class "ocp-cicd-hosts" {
    match if substring (hardware, 1, 3) = 10:70:fd;
}

# Single subnet declaration with pools
subnet 192.168.10.0 netmask 255.255.255.0 {
    # Partner pool (10-99)
    pool {
        allow members of "partner-hosts";
        range 192.168.10.10 192.168.10.99;
        option domain-name "partner.lab.com";
        option routers 192.168.10.1;
    }

    # Engineering pool (100-150)
    pool {
        allow members of "engg-hosts";
        range 192.168.10.100 192.168.10.150;
        option domain-name "engg.lab.com";
        option routers 192.168.10.1;
    }

    # OCP Cluster pool (160-175)
    pool {
        allow members of "ocp-clust-hosts";
        range 192.168.10.160 192.168.10.175;
        option domain-name "ocp-clust.com";
        option routers 192.168.10.161;
    }

    # OCP KVM pool (176-190)
    pool {
        allow members of "ocp-kvm-hosts";
        range 192.168.10.176 192.168.10.190;
        option domain-name "ocp-kvm.com";
        option routers 192.168.10.177;
    }

    # OCP CICD pool (191-200)
    pool {
        allow members of "ocp-cicd-hosts";
        range 192.168.10.191 192.168.10.200;
        option domain-name "ocp-cicd.com";
        option routers 192.168.10.192;
    }
}

# Group definitions
group {
    option domain-name "partner.lab.com";
    host idclab695 {
        hardware ethernet 10:70:fd:26:4d:1b;
        fixed-address 192.168.10.10;
    }
}

group {
    option domain-name "engg.lab.com";
    host idclab479 {
        hardware ethernet 10:70:fd:26:4b:ea;
        fixed-address 192.168.10.104;
    }
}

group {
    option domain-name "ocp-clust.com";
    host idclab647 {
        hardware ethernet 10:70:fd:26:4f:d2;
        fixed-address 192.168.10.165;
    }
    host idclab648 {
        hardware ethernet 10:70:fd:26:50:52;
        fixed-address 192.168.10.166;
    }
}

group {
    option domain-name "ocp-kvm.com";
    host idclab649 {
        hardware ethernet 10:70:fd:26:4e:12;
        fixed-address 192.168.10.177;
    }
    host idclab484 {
        hardware ethernet 6c:fe:54:4a:e9:81;
        fixed-address 192.168.10.178;
    }
}

group {
    option domain-name "ocp-cicd.com";
    host idclab650 {
        hardware ethernet 10:70:fd:26:49:72;
        fixed-address 192.168.10.198;
    }
}

# Infrastructure host
host infra {
    hardware ethernet 6c:fe:54:4a:ea:21;
    fixed-address 192.168.10.2;
}
EOF
echo "✓ DHCP configuration file created"

# Validate configurations before proceeding
if ! validate_configs; then
    echo "Configuration validation failed. Deployment aborted."
    exit 1
fi

# Build containers
echo "Building DNS container..."
podman build -t local/dns-server ~/lab-infra/dns/src
echo "✓ DNS container built"

echo "Building DHCP container..."
podman build -t local/dhcp-server ~/lab-infra/dhcp/src
echo "✓ DHCP container built"

# Stop and remove existing containers
echo "Cleaning up existing containers..."
podman stop dns-server dhcp-server 2>/dev/null || true
podman rm dns-server dhcp-server 2>/dev/null || true
echo "✓ Container cleanup completed"

# Start new containers
echo "Starting DNS server..."
podman run -d \
  --name dns-server \
  --network host \
  -v ~/lab-infra/dns/config:/etc/bind \
  -v ~/lab-infra/dns/data:/var/lib/bind \
  local/dns-server
echo "✓ DNS server started"

echo "Starting DHCP server..."
podman run -d \
  --name dhcp-server \
  --network host \
  --cap-add=NET_ADMIN \
  -v ~/lab-infra/dhcp/config:/etc/dhcp \
  local/dhcp-server
echo "✓ DHCP server started"

# Configure and start NFS
echo "Starting NFS services..."
if systemctl list-unit-files | grep -q nfs-server.service; then
    sudo systemctl enable nfs-server
    sudo systemctl start nfs-server
    sudo exportfs -ra
    echo "✓ NFS services started"
else
    echo "❌ NFS server service not found. Please ensure nfs-utils is installed."
    exit 1
fi

# Configure firewall
echo "Configuring firewall rules..."
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --permanent --add-service=dhcp
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload
echo "✓ Firewall rules configured"

# Generate systemd service files using Quadlets
echo "Setting up systemd services..."
mkdir -p ~/.config/containers/systemd/

# Create DNS Quadlet
cat > ~/.config/containers/systemd/dns-server.container << 'EOF'
[Container]
Image=localhost/local/dns-server:latest
Network=host
Volume=${HOME}/lab-infra/dns/config:/etc/bind
Volume=${HOME}/lab-infra/dns/data:/var/lib/bind

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

# Create DHCP Quadlet
cat > ~/.config/containers/systemd/dhcp-server.container << 'EOF'
[Container]
Image=localhost/local/dhcp-server:latest
Network=host
AddCapability=NET_ADMIN
Volume=${HOME}/lab-infra/dhcp/config:/etc/dhcp

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF

# Reload and start services
systemctl --user daemon-reload
systemctl --user enable container-dns-server container-dhcp-server
systemctl --user start container-dns-server container-dhcp-server
echo "✓ Systemd services created and started"

echo ""
echo "=== Deployment Complete ==="
echo "Please verify the following:"

echo "1. Basic DNS Resolution:"
echo "   - Forward lookup test:"
echo "     dig @192.168.10.2 infra.lab.com"
echo "   - Reverse lookup test:"
echo "     dig @192.168.10.2 -x 192.168.10.2"

echo "2. OpenShift DNS Records:"
echo "   Testing each cluster's critical endpoints..."
echo "   Partner Cluster:"
echo "   - dig @192.168.10.2 api.partner.lab.com"
echo "   - dig @192.168.10.2 *.apps.partner.lab.com"
echo "   - dig @192.168.10.2 oauth-openshift.apps.partner.lab.com"

echo "3. Specific OpenShift Service Tests:"
echo "   - Console access:"
echo "     dig @192.168.10.2 console-openshift-console.apps.partner.lab.com"

echo "4. DHCP Service:"
echo "   - Test DHCP discovery:"
echo "     sudo nmap -sU -p 67 192.168.10.2"

echo "5. NFS Service:"
echo "   - Test NFS exports:"
echo "     showmount -e 192.168.10.2"

echo ""
echo "For full cluster verification, test these endpoints for each environment:"
echo "- partner.lab.com"
echo "- engg.lab.com"
echo "- clust.lab.com"
echo "- kvm.lab.com"
echo "- cicd.lab.com"
