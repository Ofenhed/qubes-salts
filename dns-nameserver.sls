# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import escape_bash, salt_warning %}

{%- set vm_type = salt['pillar.get']('qubes:type') %}

{%- set is_template = vm_type == 'template' %}
{%- set is_app = vm_type == 'app' %}
{%- if is_template or is_app %}
  {%- set net_vm = salt['pillar.get']('qubes:netvm') %}
  {%- set etc_dir = '/etc/systemd/resolved.conf.d' %}
  {%- set etc_filename = 'dns_servers.conf' %}
  {%- set etc_path = etc_dir + '/' + etc_filename %}
  {%- set custom_dns = salt['pillar.get']('custom-dns:' + grains['id'], {}) %}
  {%- set dns_servers = custom_dns['servers'] if 'servers' in custom_dns else [] %}
  {%- set fallback_dns_servers = custom_dns['fallback_servers'] if 'fallback_servers' in custom_dns else [] %}
  {%- set dns_over_tls = 'dnsovertls' in custom_dns and custom_dns['dnsovertls'] %}
{%- if is_template %}
Create directory for {{ etc_path }}:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

{{ etc_path }}:
{%- else %}
/rw/config/rc.local.d/10-custom-dns.rc:
{%- endif %}
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
    {%- if is_app %}
         #!/bin/sh
    {%- endif %}
         # {{ salt_warning }}
    {%- if is_app %}
         mkdir -p /etc/systemd/resolved.conf.d
         cat <<EOF > {{ etc_path }}
    {%- endif %}
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
    {%- if is_app %}
         EOF
         systemctl restart systemd-resolved
    {%- endif %}
  {%- endif %}
{%- endif %}
