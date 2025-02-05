# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] == 'dom0' %}
  {%- from "formatting.jinja" import yaml_string, salt_warning %}
  {%- set tpm_enrolled = salt['cmd.run'](["bash", "-c", "cat /etc/crypttab | awk '$4 ~ /tpm2-device/ { print $2 }'"]) %}
Generate systemd-cryptencroll-all-tpm:
  file.managed:
    - name: /usr/local/sbin/systemd-cryptenroll-all-tpm
      user: root
      group: root
      mode: 755
      replace: True
      contents: |
        # {{ salt_warning }}
  {%- for device in tpm_enrolled.split() %}
    {%- set pcrs = salt['cmd.run'](["bash", "-c", "cat /etc/crypttab | awk '$2 == ENVIRON[\"disk\"] { if (match($4,/tpm2-pcrs=([0-9]+(\+[0-9]+)*)/,m)) print m[0] }'"], env={'disk': device}) %}
    {%- set pcrs_argument = "--" + pcrs %}
    {%- set uuid_stripped = device.replace("UUID=", "") %}
    {%- set device = ("/dev/disk/by-uuid/" + uuid_stripped) if ("UUID=" + uuid_stripped) == device else device %}
        systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto {{ pcrs_argument }} "{{ device }}"
  {%- endfor %}
{%- endif %}
