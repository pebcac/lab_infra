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

; Partner hosts
idclab695.partner  IN   A       192.168.10.10
api.partner       IN   A       192.168.10.10
api-int.partner   IN   A       192.168.10.10
*.apps.partner    IN   A       192.168.10.10

; Engineering hosts
idclab479.engg    IN   A       192.168.10.104
api.engg          IN   A       192.168.10.104
api-int.engg      IN   A       192.168.10.104
*.apps.engg       IN   A       192.168.10.104

; Cluster hosts
idclab647.clust   IN   A       192.168.10.165
idclab648.clust   IN   A       192.168.10.166
api.clust         IN   A       192.168.10.165
api-int.clust     IN   A       192.168.10.165
*.apps.clust      IN   A       192.168.10.165

; KVM hosts
idclab649.kvm     IN   A       192.168.10.177
idclab484.kvm     IN   A       192.168.10.178
api.kvm           IN   A       192.168.10.177
api-int.kvm       IN   A       192.168.10.177
*.apps.kvm        IN   A       192.168.10.177

; CICD hosts
idclab650.cicd    IN   A       192.168.10.198
api.cicd          IN   A       192.168.10.198
api-int.cicd      IN   A       192.168.10.198
*.apps.cicd       IN   A       192.168.10.198

; OpenShift specific entries
oauth-openshift.apps.partner IN A 192.168.10.10
oauth-openshift.apps.engg    IN A 192.168.10.104
oauth-openshift.apps.clust   IN A 192.168.10.165
oauth-openshift.apps.kvm     IN A 192.168.10.177
oauth-openshift.apps.cicd    IN A 192.168.10.198
