#!/bin/zsh

# Set script to exit on error
set -e

# Function to validate configurations
validate_configs() {
    echo "Validating configurations..."

    # Validate DNS configuration
    if ! named-checkconf ~/lab-infra/dns/config/named.conf; then
        echo "❌ DNS configuration validation failed"
        return 1
    fi

    # Validate zone files
    if ! named-checkzone lab.com ~/lab-infra/dns/config/db.lab.com; then
        echo "❌ Forward zone validation failed"
        return 1
    fi

    if ! named-checkzone 10.168.192.in-addr.arpa ~/lab-infra/dns/config/db.10.168.192; then
        echo "❌ Reverse zone validation failed"
        return 1
    fi

    # Validate DHCP configuration
    if ! dhcpd -t -cf ~/lab-infra/dhcp/config/dhcpd.conf; then
        echo "❌ DHCP configuration validation failed"
        return 1
    fi

    echo "✓ All configurations validated successfully"
    return 0
}

# Function to cleanup existing files and directories
cleanup_existing() {
    echo "Checking for existing files and directories..."

    # Clean existing configuration files
    rm -f ~/lab-infra/dns/config/named.conf
    rm -f ~/lab-infra/dns/config/db.lab.com
    rm -f ~/lab-infra/dns/config/db.10.168.192
    rm -f ~/lab-infra/dhcp/config/dhcpd.conf
    rm -f ~/.config/systemd/user/container-dns-server.service
    rm -f ~/.config/systemd/user/container-dhcp-server.service

    # Clean directories but preserve the structure
    rm -rf ~/lab-infra/dns/data/*
    rm -rf ~/lab-infra/dhcp/data/*
    rm -rf /var/named/data/* 2>/dev/null || true
    rm -rf /var/named/dynamic/* 2>/dev/null || true
    rm -rf /exports/* 2>/dev/null || true

    echo "✓ Cleanup completed"
}

echo "Starting infrastructure deployment..."

# Run cleanup first
cleanup_existing

# Create necessary directories
echo "Creating directory structure..."
mkdir -p ~/lab-infra/{dns,dhcp,nfs}/{config,data,src}
sudo mkdir -p /var/named/{data,dynamic}
sudo mkdir -p /exports/{home,data,apps}
echo "✓ Directory structure created"

# Create DNS configuration files
echo "Creating DNS configuration files..."
cat > ~/lab-infra/dns/config/named.conf << 'EOF'
options {
        listen-on port 53 { 127.0.0.1; 192.168.10.2; };
        listen-on-v6 port 53 { none; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        allow-query     { any; };
        forwarders      { 1.1.1.1; 1.0.0.1; };
        recursion yes;
        dnssec-validation no;
        managed-keys-directory "/var/named/dynamic";
        geoip-directory "/usr/share/GeoIP";
        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";
        include "/etc/crypto-policies/back-ends/bind.config";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "lab.com" IN {
    type master;
    file "db.lab.com";
};

zone "10.168.192.in-addr.arpa" IN {
    type master;
    file "db.10.168.192";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF
echo "✓ Named configuration created"

# Create forward zone file with OpenShift records
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
prometheus-k8s-openshift-monitoring.apps.partner IN A 192.168.10.10
canary-openshift-ingress-canary.apps.partner IN A 192.168.10.10

; Engineering hosts and OpenShift entries
idclab479.engg    IN   A       192.168.10.104
api.engg          IN   A       192.168.10.104
api-int.engg      IN   A       192.168.10.104
*.apps.engg       IN   A       192.168.10.104
oauth-openshift.apps.engg IN A 192.168.10.104
console-openshift-console.apps.engg IN A 192.168.10.104
prometheus-k8s-openshift-monitoring.apps.engg IN A 192.168.10.104
canary-openshift-ingress-canary.apps.engg IN A 192.168.10.104

; Cluster hosts and OpenShift entries
idclab647.clust   IN   A       192.168.10.165
idclab648.clust   IN   A       192.168.10.166
api.clust         IN   A       192.168.10.165
api-int.clust     IN   A       192.168.10.165
*.apps.clust      IN   A       192.168.10.165
oauth-openshift.apps.clust IN A 192.168.10.165
console-openshift-console.apps.clust IN A 192.168.10.165
prometheus-k8s-openshift-monitoring.apps.clust IN A 192.168.10.165
canary-openshift-ingress-canary.apps.clust IN A 192.168.10.165

; KVM hosts and OpenShift entries
idclab649.kvm     IN   A       192.168.10.177
idclab484.kvm     IN   A       192.168.10.178
api.kvm           IN   A       192.168.10.177
api-int.kvm       IN   A       192.168.10.177
*.apps.kvm        IN   A       192.168.10.177
oauth-openshift.apps.kvm IN A 192.168.10.177
console-openshift-console.apps.kvm IN A 192.168.10.177
prometheus-k8s-openshift-monitoring.apps.kvm IN A 192.168.10.177
canary-openshift-ingress-canary.apps.kvm IN A 192.168.10.177

; CICD hosts and OpenShift entries
idclab650.cicd    IN   A       192.168.10.198
api.cicd          IN   A       192.168.10.198
api-int.cicd      IN   A       192.168.10.198
*.apps.cicd       IN   A       192.168.10.198
oauth-openshift.apps.cicd IN A 192.168.10.198
console-openshift-console.apps.cicd IN A 192.168.10.198
prometheus-k8s-openshift-monitoring.apps.cicd IN A 192.168.10.198
canary-openshift-ingress-canary.apps.cicd IN A 192.168.10.198
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
sudo systemctl enable nfs-server
sudo systemctl start nfs-server
sudo exportfs -ra
echo "✓ NFS services started"

# Configure firewall
echo "Configuring firewall rules..."
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --permanent --add-service=dhcp
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload
echo "✓ Firewall rules configured"

# Generate systemd service files
echo "Setting up systemd services..."
mkdir -p ~/.config/systemd/user/
podman generate systemd --name dns-server --files --new
podman generate systemd --name dhcp-server --files --new
mv container-dns-server.service ~/.config/systemd/user/
mv container-dhcp-server.service ~/.config/systemd/user/
echo "✓ Systemd services created"

# Enable and start services
systemctl --user daemon-reload
systemctl --user enable container-dns-server container-dhcp-server
systemctl --user start container-dns-server container-dhcp-server
echo "✓ Services enabled and started"

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
echo "   - Monitoring:"
echo "     dig @192.168.10.2 prometheus-k8s-openshift-monitoring.apps.partner.lab.com"
echo "   - Ingress:"
echo "     dig @192.168.10.2 canary-openshift-ingress-canary.apps.partner.lab.com"

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
