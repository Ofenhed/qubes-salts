# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning %}

/etc/sysctl.d/50-mtu-detection.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - makedirs: true
    - dir_mode: 555
    - replace: true
    - contents: |
         # {{ salt_warning }}

         # 0 - Disabled
         # 1 - Disabled by default, enabled when an ICMP black hole detected
         # 2 - Always enabled, use initial MSS_of tcp_base_mss
         net.ipv4.tcp_mtu_probing=2


         net.ipv4.tcp_base_mss=1300

