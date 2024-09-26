# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import systemd_inline_bash, salt_warning %}

{% if grains['id'] != 'dom0' %}
  {%- set dns_servers = salt['pillar.get']('dns-servers', []) %}
  {% if (dns_servers | length) != 0 %}
/rw/config/rc.local.d/10-resolv-conf.rc:
  file.managed:
    - user: root
    - group: root
    - mode: 744
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
         #!/bin/sh
         # {{ salt_warning }}
         mount -rB /rw/config/resolv.conf /etc/resolv.conf

/rw/config/resolv.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
    {%- for dns_server in dns_servers %}
        nameserver {{ dns_server }}
    {% endfor %}
  {% endif %}

{% endif %}
