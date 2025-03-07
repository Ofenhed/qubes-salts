# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import escape_bash, salt_warning %}

{% if grains['id'] != 'dom0' %}
  {%- set net_vm = salt['pillar.get']('qubes:netvm') %}
  {%- set custom_dns = salt['pillar.get']('custom-dns:' + grains['id'], {}) %}
  {%- set dns_servers = custom_dns['servers'] if 'servers' in custom_dns else [] %}
  {%- set fallback_dns_servers = custom_dns['fallback_servers'] if 'fallback_servers' in custom_dns else [] %}
  {%- set dns_over_tls = 'dnsovertls' in custom_dns and custom_dns['dnsovertls'] %}
/rw/config/rc.local.d/10-custom-dns.rc:
  {%- if (dns_servers | length) == 0 %}
  file.absent: []
  {%- else %}
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
         mkdir -p /etc/systemd/resolved.conf.d
         cat <<EOF > /etc/systemd/resolved.conf.d/dns_servers.conf
         [Resolve]
         {%- if (dns_servers | length) > 0 %}
         DNS={{- dns_servers | join(' ') }}
         {%- endif %}
         {%- if (fallback_dns_servers | length) > 0 %}
         FallbackDNS={{- fallback_dns_servers | join(' ') }}
         {%- endif %}
         {%- if dns_over_tls %}
         DNSOverTls=yes
         {%- endif %}
         Domains=~.
         EOF
         systemctl restart systemd-resolved

  {%- endif %}
{%- endif %}
