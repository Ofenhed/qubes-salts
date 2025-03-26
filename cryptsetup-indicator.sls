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
    while IFS="" read -r line || [ -n "$line" ]; do
        luks_name=$(awk '{ print $1 }' <<< "$line")
        luks_systemd_name=$(systemd-escape -- "$luks_name")
        luks_udev_name="${luks_systemd_name//\\/\\\\}"

        source_dev=$(awk {{ awk_arg_get_crypttab_source() }} <<< "$line")
        source_systemd_dev=$(systemd-escape -- "${source_dev#/}")

        {%- if initdir %}
        {%- endif %}
        for prefix in '* ' ''; do
            for suffix in ' *' ''; do
                echo "ENV{DEVLINKS}==\"$prefix$source_dev$suffix\", TAG+=\"systemd\", ENV{SYSTEMD_WANTS}+=\"{{ service_name('$luks_udev_name') }}\""
            done
        done >> {{ rules_file }}
    done < {{ '$initdir' if initdir else '' }}/etc/crypttab
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
            inst "$moddir/{{ change_name_script_name }}" {{ target_change_name_script_path }}
            inst "$moddir/{{ service_name() }}" "{{ systemd_dir }}/{{ service_name() }}"
            if [ $hostonly ]; then
                {{ init_script(True) | indent(16) }}
            else
                inst_hook pre-udev 90 "$moddir/{{ init_script_name }}"
            fi
        }

{{p}}rename_script: 
  file.managed:
    - name: {{ mod_dir }}/{{ change_name_script_name }}
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - require:
      - file: {{ mod_dir }}
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}

        dev_name="$1"
        strip_tag="$2"
        cryptsetup_dump=$(cryptsetup luksDump "$dev_name")
        label=$(echo -n $(awk '/^Label:[0-9a-zA-Z(),\- \t]+$/ { $1=""; print $0 }' <<< "$cryptsetup_dump"))
        if [[ $label != "" ]] && [[ $label != "(no label)" ]]; then
            echo "SUBSYSTEM==\"block\", ACTION==\"change\", ENV{DEVNAME}==\"$dev_name\", ENV{ID_PART_ENTRY_NAME}=\"$label\"" >> /etc/udev/rules.d/99-rename-encrypted-disks.rules
            grep -vF "$strip_tag" < {{ udev_rule_prepare }} > {{ udev_rule_prepare }}.new
            mv {{ udev_rule_prepare }}.new {{ udev_rule_prepare }}
            udevadm control --reload
            udevadm trigger --name-match="$dev_name"
        else
            echo "# $dev_name does not have a label specified, ignoring" >> /etc/udev/rules.d/99-rename-encrypted-disks.rules
            mkdir -p /var/log/
            cat <<< "$cryptsetup_dump" >> /var/log/rename-failed.txt
        fi

{#
luks-04f935b5-17ba-4a25-be2b-fb88722fea70 /home/user/testdisk none discard,force,header=/home/user/testuser,password-cache=no
#}

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
        set -e
        
        awk_script=$(cat << EOF
        {
            if (match(\$4, /(^|,)header=([^,]+)(\$|,)/, m)) {
                header_device=m[2]
            } else {
                header_device=\$2
            }
            do_print=1;
            if (match(header_device, /^\/dev\/mapper\/([0-9a-zA-Z(),\-]+)\$/, mapper_dev)) {
                udev_match="ENV{DM_NAME}==\"" mapper_dev[1] "\", ";
            } else if (match(header_device, /^(UUID=|\/dev\/disk\/by-uuid\/)([0-9a-zA-Z\-]+)\$/, mapper_dev)) {
                udev_match="ENV{ID_FS_UUID}==\"" mapper_dev[2] "\", ";
            } else {
                print "# Invalid header: " header_device;
                do_print=0;
            }
            if (do_print > 0) {
                print "SUBSYSTEM==\"block\", ACTION!=\"remove\"," udev_match " RUN+=\"{{ target_change_name_script_path }} \$env{DEVNAME} tag_for_removal" NR "\"";
            }
        }
        EOF
        )

        {{ init_script(False) | indent(8) }}

{% call add_dependencies('dracut') %}
  - file: {{p}}rename_script
  - file: {{p}}service
  - file: {{p}}hook
  - file: {{p}}setup
{% endcall %}

{% endif %}
