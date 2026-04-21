#!/usr/bin/env bash
# Copyright (c) 2021-2026 tteck / community-scripts ORG
# Authors: tteck (tteckster), wimb0
# Merged by: custom
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Sources:
#   https://adguard.com/ | https://github.com/AdguardTeam/AdGuardHome
#   https://github.com/NLnetLabs/unbound

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─────────────────────────────────────────────
# 1. UNBOUND — resolver DNS récursif (port 5335)
# ─────────────────────────────────────────────

msg_info "Installing Unbound"

mkdir -p /etc/unbound/unbound.conf.d

cat <<EOF >/etc/unbound/unbound.conf.d/unbound.conf
server:
    interface: 0.0.0.0
    port: 5335
    do-ip6: no

    hide-identity: yes
    hide-version: yes
    harden-referral-path: yes

    cache-min-ttl: 300
    cache-max-ttl: 14400
    serve-expired: yes
    serve-expired-ttl: 3600
    prefetch: yes
    prefetch-key: yes
    target-fetch-policy: "3 2 1 1 1"
    unwanted-reply-threshold: 10000000

    rrset-cache-size: 256m
    msg-cache-size: 128m
    so-rcvbuf: 1m

    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

    access-control: 192.168.0.0/16 allow
    access-control: 172.16.0.0/12 allow
    access-control: 10.0.0.0/8 allow
    access-control: 127.0.0.1/32 allow

    chroot: ""
    logfile: /var/log/unbound.log
EOF

$STD apt install -y \
    unbound \
    unbound-host

touch /var/log/unbound.log
chown unbound:unbound /var/log/unbound.log

sleep 5
systemctl enable --now unbound
systemctl restart unbound

msg_ok "Installed Unbound"

# ─────────────────────────────────────────────
# 2. LOGROTATE pour Unbound
# ─────────────────────────────────────────────

msg_info "Configuring Logrotate for Unbound"

cat <<EOF >/etc/logrotate.d/unbound
/var/log/unbound.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    create 644
    postrotate
        /usr/sbin/unbound-control log_reopen
    endscript
}
EOF

systemctl restart logrotate

msg_ok "Configured Logrotate"

# ─────────────────────────────────────────────
# 3. ADGUARD HOME — filtrage DNS (port 3000/setup, 53 DNS)
#    Upstream configuré vers Unbound sur 127.0.0.1:5335
# ─────────────────────────────────────────────

fetch_and_deploy_gh_release \
    "AdGuardHome" \
    "AdguardTeam/AdGuardHome" \
    "prebuild" \
    "latest" \
    "/opt/AdGuardHome" \
    "AdGuardHome_linux_amd64.tar.gz"

msg_info "Creating AdGuardHome Service"

cat <<EOF >/etc/systemd/system/AdGuardHome.service
[Unit]
Description=AdGuard Home: Network-level blocker
ConditionFileIsExecutable=/opt/AdGuardHome/AdGuardHome
After=syslog.target network-online.target unbound.service
Requires=unbound.service

[Service]
StartLimitInterval=5
StartLimitBurst=10
ExecStart=/opt/AdGuardHome/AdGuardHome "-s" "run"
WorkingDirectory=/opt/AdGuardHome
StandardOutput=file:/var/log/AdGuardHome.out
StandardError=file:/var/log/AdGuardHome.err
Restart=always
RestartSec=10
EnvironmentFile=-/etc/sysconfig/AdGuardHome

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now AdGuardHome

msg_ok "Created AdGuardHome Service"

# ─────────────────────────────────────────────
# 4. NOTE POST-INSTALL
# ─────────────────────────────────────────────

msg_info "Post-install reminder"
cat <<'NOTE'

  ┌─────────────────────────────────────────────────────────┐
  │  CONFIGURATION MANUELLE REQUISE dans AdGuard Home       │
  │                                                         │
  │  Après le wizard initial (http://<IP>:3000) :           │
  │                                                         │
  │  Settings → DNS Settings → Upstream DNS servers :       │
  │    127.0.0.1:5335                                       │
  │                                                         │
  │  Cocher : "Parallel requests" ou "Load-balancing"       │
  │  Bootstrap DNS (pour la résolution des DoH/DoT) :       │
  │    9.9.9.9                                              │
  │    149.112.112.112                                      │
  └─────────────────────────────────────────────────────────┘

NOTE
msg_ok "Post-install reminder displayed"

motd_ssh
customize
cleanup_lxc
