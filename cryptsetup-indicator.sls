# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning, systemd_shell, escape_bash %}
{%- from "dependents.jinja" import add_dependencies %}

{%- set p = "Systemd ask password show label " %}
{%- set module_name = "systemd-ask-password-print-label" %}
{%- set mod_dir = "/lib/dracut/modules.d/91" + module_name %}
{%- set systemd_dir = "/usr/lib/systemd/system" %}
{%- macro service_name(instance='') -%}
    sync-luks-partition-name@{{ instance }}.service
{%- endmacro %}
{%- set init_script_name = "prepare_change_crypttab_names.sh" %}
{%- set change_name_script_name = "change_crypttab_names.sh" %}
{%- set target_change_name_script_path = "/usr/sbin/rename-luks-device-names" %}
{%- set udev_rule_prepare = "/etc/udev/rules.d/99-prepare-name-change.rules" %}
{%- macro awk_arg_get_crypttab_source(luks_name=None, header=True) %}
    {%- set result %}{%- call escape_bash() %}
        {
        {%- if luks_name is string %}
            if ($1 == {{ luks_name }}) {
        {%- endif %}
        {%- if header %}
                if (match($4, /(^|,)header=([^ ,]+)($|,)/, m)) {
                    print m[2]
                } else {
        {%- endif %}
                    print $2
        {%- if header %}
                }
        {%- endif %}
        {%- if luks_name is string %}
            }
        {%- endif %}
        }
    {%- endcall %}{%- endset %}
    {{- result | replace('\n', ' ') }}
{%- endmacro %}

{%- macro systemctl(initdir=False) %}
    {%- if initdir -%}
        $SYSTEMCTL -q --root "$initdir"
    {%- else -%}
        systemctl
    {%- endif %}
{%- endmacro %}

{%- macro init_script(initdir=False) %}
    {%- set rules_name = '99-start-encrypted-disk-rename-service.rules' %}
    {%- set rules_file = '$rules_file' if initdir else '/etc/udev/rules.d/{{ rules_name }}' %}
    {%- if initdir %}
    rules_file=$(mktemp -d)/{{ rules_name }}
    {%- endif %}
    echo 'SUBSYSTEM!="block", GOTO="not_in_crypttab"' >> {{ rules_file }}
    echo 'ACTION=="remove", GOTO="not_in_crypttab"' >> {{ rules_file }}
    counter=0
    crypttab_label_rule() {
        cat <<< "crypttab_label_not_rule_$1"
    }
    while IFS="" read -r line || [ -n "$line" ]; do
        luks_name=$(awk '{ print $1 }' <<< "$line")
        luks_systemd_name=$(systemd-escape -- "$luks_name")
        luks_udev_name="${luks_systemd_name//\\/\\\\}"
        luks_udev_name="${luks_udev_name//\"/\\\"}"

        source_dev=$(awk {{ awk_arg_get_crypttab_source() }} <<< "$line")
        source_systemd_dev=$(systemd-escape -p -- "$source_dev")

        counter=$((counter+1))
        echo
        echo "ENV{DEVLINKS}!=\"*${source_dev}*\", GOTO=\"$(crypttab_label_rule $counter)\""

        for prefix in '* ' ''; do
            for suffix in ' *' ''; do
                echo "ENV{DEVLINKS}==\"$prefix$source_dev$suffix\", TAG+=\"systemd\", ENV{SYSTEMD_WANTS}+=\"{{ service_name('$luks_udev_name') }}\""
            done
        done

        echo "LABEL=\"$(crypttab_label_rule $counter)\""
    done < {{ '$initdir' if initdir else '' }}/etc/crypttab >> {{ rules_file }}
    echo 'LABEL="not_in_crypttab"' >> {{ rules_file }}
    {%- if initdir %}
        inst_rules "$rules_file"
    {%- else %}
        udevadm control --reload
    {%- endif %}
{%- endmacro %}


{%- if grains['id'] == 'dom0' %}
{{ mod_dir }}:
  file.directory:
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
      - file: {{ mod_dir }}
    - contents: |
        #!/usr/bin/bash
        # {{ salt_warning }}
        # SPDX-License-Identifier: GPL-2.0-or-later
        
        # Prerequisite check(s) for module.
        check() {
            if ! require_binaries sh grep tr; then
                echo "Missing required binaries"
                return 1
            fi
        
            if ! dracut_module_included crypt; then
                echo "Missing module crypt"
                return 1
            fi
            return 0
        }
        
        # Module dependency requirements.
        depends() {
            # This module has external dependency on other module(s).
            echo systemd-ask-password
            # Return 0 to include the dependent module(s) in the initramfs.
            return 0
        }
        
        # Install the required file(s) and directories for the module in the initramfs.
        install() {
            # Install required libraries.
            inst "$moddir/{{ service_name() }}" "{{ systemd_dir }}/{{ service_name() }}"
            if [ $hostonly ]; then
                {{ init_script(True) | indent(16) }}
            else
                inst_hook pre-udev 90 "$moddir/{{ init_script_name }}"
            fi
        }

{{p}}service:
  file.managed:
    - name: {{ mod_dir }}/{{ service_name() }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description="Sync partition label from %I cryptsetup label"
        Before=systemd-cryptsetup@%i.service
        Conflicts=cryptsetup.target
        
        [Service]
        Type=oneshot
        Environment="SERVICE_LUKS_TARGET=%I"
        ExecStart={%- call systemd_shell('sh') %}
            set -e
            header_device=$(awk -v luks_dev="$SERVICE_LUKS_TARGET" {{ awk_arg_get_crypttab_source(luks_name="luks_dev") }} < /etc/crypttab)
            if [[ "$header_device" == "" ]]; then
                echo "Invalid header path from crypttab while looking for $SERVICE_LUKS_TARGET"
                exit 1
            fi

            disk_device=$(awk -v luks_dev="$SERVICE_LUKS_TARGET"
                {%- call escape_bash(before=' ') %} {
                    if ($1 == luks_dev) {
                        print $2
                    }
                }
            {%- endcall %} < /etc/crypttab)
            if [[ "$disk_device" == "" ]]; then
                echo "Invalid source path from crypttab while looking for $SERVICE_LUKS_TARGET"
                exit 1
            fi

            echo "Reading luks header from $header_device"
            cryptsetup_dump=$(cryptsetup luksDump "$header_device")
            label=$(echo -n $(awk '/^Label:[0-9a-zA-Z(),\- \t]+$/ { $1=""; print $0 }' <<< "$cryptsetup_dump"))
            echo "Fround label $label"
            if [[ $label != "" ]] && [[ $label != "(no label)" ]]; then
                for prefix in '' '* '; do
                    for suffix in '' ' *'; do
                        echo "SUBSYSTEM==\"block\", ACTION!=\"remove\", ENV{DEVLINKS}==\"$prefix$disk_device$suffix\", ENV{ID_PART_ENTRY_NAME}=\"$label\""
                    done
                done >> /etc/udev/rules.d/99-rename-encrypted-disks.rules
                udevadm control --reload
                udevadm trigger --name-match="$disk_device" || true
            else
                echo "# $SERVICE_LUKS_TARGET does not have a label specified, ignoring" >> /etc/udev/rules.d/99-rename-encrypted-disks.rules
                mkdir -p /var/log/
                cat <<< "$cryptsetup_dump" >> /var/log/rename-failed.txt
            fi
        {%- endcall %}
        
        [Install]
        WantedBy=systemd-cryptsetup@%i.service


{{p}}hook:
  file.managed:
    - name: {{ mod_dir }}/{{ init_script_name }}
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - require:
      - file: {{ mod_dir }}
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}
        {{ init_script(False) | indent(8) }}

{% call add_dependencies('dracut') %}
  - file: {{p}}service
  - file: {{p}}hook
  - file: {{p}}setup
{% endcall %}

{% endif %}
