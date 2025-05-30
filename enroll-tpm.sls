# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] == 'dom0' %}
  {%- from "formatting.jinja" import salt_warning, systemd_shell, escape_bash %}
  {%- from "dependents.jinja" import add_dependencies %}
  {%- set p = "Re-enroll all TPM - " %}
  {%- set module_name = "enroll-luks-tpm" %}
  {%- set command_line_option = "uki.tpm.reroll" %}
  {%- set cmdline_filename = "apply-tpm-enroll.sh" %}
  {%- set service_filename = "enroll-luks-tpm.service" %}
  {%- set run_tpm_passphrase_path = "/run/tpm-passphrase" %}
  {%- set mod_dir = "/usr/lib/dracut/modules.d/90" + module_name %}
  {%- set pcr_register = 9 %}

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
        question="Update partition passphrase?"
        tpm2_passphrase=$(systemd-ask-password "$question")
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
            PASSWORD="$tpm2_passphrase" systemd-cryptenroll --wipe-slot=tpm2 "--$tpm_device_argument" "--$pcrs_argument" "$device"
        done

{{p}}{{ mod_dir }}:
  file.directory:
    - name: {{ mod_dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: false

{{p}}setup:
  file.managed:
    - name: {{ mod_dir }}/module-setup.sh
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        #!/bin/bash
        # {{ salt_warning }}

        check() {
            # require_binaries || return 1

            # Return 255 to only include the module, if another module requires it.
            return 255
        }

        depends() {
            echo tpm2-tss
        }

        install() {
            inst_multiple sha256sum awk  systemd-cryptenroll systemd-creds tpm2_pcrextend
            inst_simple "$moddir/{{ service_filename }}" /usr/lib/systemd/system/{{ service_filename }}
            inst_hook cmdline 02 "$moddir/{{ cmdline_filename }}"
        }



{{p}}cmdline:
  file.managed:
    - name: {{ mod_dir }}/{{ cmdline_filename }}
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        #!/usr/bin/bash --
        # {{ salt_warning }}
        type getargbool >/dev/null 2>&1 || . /lib/dracut-lib.sh
        getargbool 0 {{ command_line_option }} || exit

        parent_service_path="/run/systemd/system/{{ service_filename }}.d/"
        mkdir -p "$parent_service_path"
        tpm2_devices=$(awk '$4 ~ /(^|,)tpm2-device=/ { print $1 }' < /etc/crypttab)
        for device in $tpm2_devices; do
            escaped_device="$(systemd-escape -- "$device")"
            device_service="systemd-cryptsetup@$escaped_device.service"
            target_dir="/run/systemd/system/$device_service.d/"
            mkdir -p "$target_dir"
            (
                cat <<< "[Service]"
                cat <<< "Environment=\"TPM_REENCRYPT_TARGET=%I\""
                cat <<< "ExecStartPre=-"
                    {%- call escape_bash() %}
                        {%- call systemd_shell() %}
                        device="$TPM_REENCRYPT_TARGET"
                        source=$(awk -vdevice="$device" '$1 == device {
                            source=$2
                            if (match($4,/(^|,)header=([^,]+)(,|$)/,m)) {
                                source=m[2]
                            }
                            if (match(source,/UUID=(.*)/,m)) {
                                print "/dev/disk/by-uuid/" m[1]
                            } else {
                                print source
                            }
                        }' < /etc/crypttab)
                        pcrs_argument=$(awk -vdisk="$device" '$1 == disk { if (match($4,/(^|,)(tpm2-pcrs=[0-9]+(\+[0-9]+)*)(,|$)/,m)) print m[2] }' < /etc/crypttab)
                        tpm_device_argument=$(awk -vdisk="$device" '$1 == disk { if (match($4,/(^|,)(tpm2-device=[^,]*)(,|$)/,m)) print m[2] }' < /etc/crypttab)
                        creds_arguments=( --name=tpm-passphrase --tpm2-pcrs=0+2+4+{{ pcr_register }} --with-key=host+tpm2 --newline=no -- )
                        for attempt in {1..3}; do
                            if [ $attempt -eq 1 ]; then
                                if tpm_password=$(systemd-creds "$${creds_arguments[@]}" decrypt {{ run_tpm_passphrase_path }} - 2>/dev/null); then
                                    query_pass=0
                                else
                                    query_pass=1
                                fi
                            else
                                query_pass=1
                            fi
                            if [ $query_pass -eq 1 ]; then
                                tpm_password=$(systemd-ask-password "TPM Update Passphrase")
                            fi
                            if PASSWORD="$tpm_password" systemd-cryptenroll --wipe-slot=tpm2 "--$tpm_device_argument" "--$pcrs_argument" "$source"; then
                                if [ $query_pass -eq 1 ]; then
                                    for i in {1..5}; do
                                        read -N 32 pcr_seed </dev/random
                                        tpm2_pcrextend {{ pcr_register }}:sha256=$(sha256sum <<< "$pcr_seed" | awk '{ print $1 '})
                                    done
                                    systemd-creds --not-after +2min "$${creds_arguments[@]}" encrypt - {{ run_tpm_passphrase_path }} <<< "$tpm_password"
                                fi
                                exit
                            fi
                        done
                        echo "Could not update TPM key" >&2
                        exit 1
                        {%- endcall %}
                    {%- endcall %}
                cat <<< 'ExecStartPost=-systemctl start --no-block {{service_filename }}'
                cat <<< '[Unit]'
                cat <<< 'Before={{ service_filename }}'
            ) > "$target_dir/enroll-tpm.conf"
            (
                cat <<< '[Unit]'
                cat <<< "Require=$device_service"
                cat <<< "After=$device_service"
            ) > "$parent_service_path/$escaped_device.conf"
        done
        systemctl daemon-reload

{{p}}service:
  file.managed:
    - name: {{ mod_dir }}/{{ service_filename }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Reencrypt disk header with new TPM keys.
        ConditionKernelCommandLine={{ command_line_option }}
        DefaultDependencies=no
        Requires=system-systemd\x2dcryptsetup.slice
        After=system-systemd\x2dcryptsetup.slice cryptsetup-pre.target system-systemd\x2dcryptsetup.slice

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart={%- call systemd_shell() %}
            rm -f {{ run_tpm_passphrase_path }}
            read -N 1024 pcr_seed </dev/random
            tpm2_pcrextend {{ pcr_register }}:sha256=$(sha256sum <<< "$pcr_seed" | awk '{ print $1 '})
        {%- endcall %}
        ExecStartPost=systemctl reboot

  {% call add_dependencies('dracut') %}
    - file: {{p}}setup
    - file: {{p}}service
    - file: {{p}}cmdline
  {% endcall %}
{%- endif %}
