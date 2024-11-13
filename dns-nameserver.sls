# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import escape_bash, salt_warning %}

{% if grains['id'] != 'dom0' %}
  {%- set net_vm = salt['pillar.get']('qubes:netvm') %}
  {%- set all_custom_dns = salt['pillar.get']('custom-dns', {}) %}
  {%- set custom_dns = all_custom_dns[net_vm] if net_vm in all_custom_dns else {} %}
  {%- set dns_servers = custom_dns['servers'] if 'servers' in custom_dns else [] %}
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
         network_device=$(ip route show default | grep -Po '(?<=dev )[^ ]+')
         {%- for server in dns_servers %}
         resolvectl dns "$network_device" {{ escape_bash(server) }}
         {%- endfor %}
         {%- if dns_over_tls %}
         resolvectl dnsovertls "$network_device" yes
         {%- endif %}

  {%- endif %}
{%- endif %}
