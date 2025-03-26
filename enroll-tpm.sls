# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] == 'dom0' %}
  {%- from "formatting.jinja" import salt_warning %}
Generate systemd-cryptencroll-all-tpm:
  file.managed:
    - name: /usr/local/sbin/systemd-cryptenroll-all-tpm
    - user: root
    - group: root
    - mode: 755
    - replace: True
    - contents: |
        #!/bin/bash
        # {{ salt_warning }}
        tpm2_devices=$(awk '$4 ~ /(^|,)tpm2-device=/ { print $2 }' < /etc/crypttab)
        for device in $tpm2_devices; do
            pcrs_argument=$(disk="$device" awk '$2 == ENVIRON["disk"] { if (match($4,/tpm2-pcrs=([0-9]+(\+[0-9]+)*)(,|$)/,m)) print m[0] }' < /etc/crypttab)
            pcrs_argument="${pcrs_argument%","}"
            tpm_device_argument=$(disk="$device" awk '$2 == ENVIRON["disk"] { if (match($4,/tpm2-device=[^,]*(,|$)/,m)) print m[0] }' < /etc/crypttab)
            tpm_device_argument="${tpm_device_argument%","}"
            without_uuid="${device#"UUID="}"
            if [ $device == "UUID=$without_uuid" ]; then
                device="/dev/disk/by-uuid/$without_uuid"
            elif [ -b $device ]; then
                true
            else
                echo "Device identifier '$device' not supported"
                exit 1
            fi
            systemd-cryptenroll --wipe-slot=tpm2 "--$tpm_device_argument" "--$pcrs_argument" "$device"
        done
{%- endif %}
