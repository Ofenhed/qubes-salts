# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

wireguard-tools:
  pkg.installed: []

/etc/wireguard:
  file.directory:
    - user: root
    - group: systemd-network
    - mode: 550

