# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :
# To use this module, create a .conf file in /etc/dracut.conf.d/ with which
# loads either this module or fido2, as such:
# add_dracutmodules+=" hide-all-usb-after-decrypt "

{% from "formatting.jinja" import systemd_inline_bash, salt_warning %}
{% from "dependents.jinja" import add_dependencies %}

{% set p = "Hide USB after decrypt" %}

{% set module_name = "hide-all-usb-after-decrypt" %}
{% set mod_dir = "/lib/dracut/modules.d/92" + module_name %}
{% macro unbind_pci_device_service(device = '') -%}
  unbind-pci-device@{{device}}.service
{%- endmacro %}
{% macro bind_pciback_device_service(device = '') -%}
  bind-pciback-device@{{device}}.service
{%- endmacro %}
{% set unbind_pci_devices_service = 'unbind-pci-devices.service' %}
{% set unbind_pci_device_service_path = "/usr/lib/systemd/system/" + unbind_pci_device_service() %}
{% set bind_pciback_device_service_path = "/usr/lib/systemd/system/" + bind_pciback_device_service() %}
{% set unbind_pci_devices_service_path = "/usr/lib/systemd/system/" + unbind_pci_devices_service %}
{% set usbguard_override = "/usr/lib/systemd/system/usbguard.service.d/hide-all-usb-after-decrypt.conf" %}
{% set usbguard_rule_filename = "50-cryptsetup-devices.conf" %}
{% set hook_script_name = "check-hide-all-usb-options.sh" %}
{% set start_usbguard_script_name = "start_usbguard_if_no_qubes_pciback.sh" %}
{% set usbguard_rules = salt['pillar.get']('cryptsetup-devices', ['allow 1050:* with-interface match-all { 03:00:00 03:01:01 0b:00:00 }']) %}


{% if grains['id'] == 'dom0' %}
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
        #!/usr/bin/bash
        # {{ salt_warning }}
        # SPDX-License-Identifier: GPL-2.0-or-later

        # Prerequisite check(s) for module.
        check() {
            # require_binaries || return 1

            dracut_module_included "fido2" && return 0
            # Return 255 to only include the module, if another module requires it.
            return 255
        }

        # Module dependency requirements.
        depends() {
            # This module has external dependency on other module(s).
            echo crypt bash systemd
            # Return 0 to include the dependent module(s) in the initramfs.
            return 0
        }

        # Install the required file(s) and directories for the module in the initramfs.
        install() {
            inst_multiple lspci awk bash true
            {% if (usbguard_rules | length) > 0 %}
            inst "$moddir/{{ usbguard_rule_filename }}" "/etc/usbguard/rules.d/{{ usbguard_rule_filename }}"
            {% endif %}
            inst_multiple {{ usbguard_override }} {{ unbind_pci_devices_service_path }} {{ unbind_pci_device_service_path }} {{ bind_pciback_device_service_path }}
            if ! dracut_module_included "qubes-pciback"; then
                mkdir -p -m 0700 -- "$initdir/etc/usbguard"
                mkdir -p -m 0755 -- "$systemdsystemunitdir/usbguard.service.d"
                inst_multiple /etc/nsswitch.conf
                inst_multiple /etc/usbguard/{qubes-usbguard.conf,rules.d,IPCAccessControl.d}
                inst_multiple /etc/usbguard/rules.d/*
                inst -l /usr/bin/usbguard
                inst -l /usr/sbin/usbguard-daemon
                inst /usr/lib/systemd/system/usbguard.service.d/30_qubes.conf
                inst /usr/lib/systemd/system/usbguard.service
                inst_hook cmdline 02 "$moddir/{{ start_usbguard_script_name }}"
            else
                inst_hook cmdline 05 "$moddir/{{ hook_script_name }}"
            fi
        }

        installkernel() {
            installkernel() {
                local mod=

                for mod in pciback xen-pciback; do
                    if modinfo -k "${kernel}" "${mod}" >/dev/null 2>&1; then
                        hostonly='' instmods "${mod}"
                    fi
                done
            }
        }

{{p}}{{ unbind_pci_device_service_path }}:
  file.managed:
    - name: {{ unbind_pci_device_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Unbind %i after disk decryption
        After={{ unbind_pci_devices_service }}
        BindsTo={{ unbind_pci_devices_service }}
        ConditionKernelCommandLine=rd.qubes.hide_all_usb_after_decrypt
        ConditionKernelCommandLine=!rd.qubes.keep_pci_after_decrypt=%i
        ConditionPathIsDirectory=/sys/bus/pci/devices/0000:%i

        [Service]
        Type=oneshot

        RemainAfterExit=yes

        TimeoutSec=3min
        ExecStop=bash -c
        {%- call systemd_inline_bash() %}
            if [[ "$(systemctl is-system-running || true)" == "stopping" ]]; then
                echo "Detected system shutdown, skipping USB unbind"
                exit 1
            fi
            set -e

            BDF="0000:%i"
            if [ -e "/sys/bus/pci/drivers/pciback/$BDF" ]; then
                echo "Device $dev already unbound, skipping"
                continue
            fi
            if [ -e "/sys/bus/pci/devices/$BDF/driver" ]; then
                echo "Unbinding $dev"
                echo -n "$BDF" > "/sys/bus/pci/devices/$BDF/driver/unbind"
            fi
            if [ -e "/sys/bus/pci/devices/$BDF/driver_override" ]; then
                echo "Setting driver override for %i"
                echo -n pciback > "/sys/bus/pci/devices/$BDF/driver_override"
            fi
        {%- endcall %}

        [Install]
        WantedBy=basic.target

{{p}}{{ unbind_pci_devices_service_path }}:
  file.managed:
    - name: {{ unbind_pci_devices_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Unbind PCI devices
        Before=cryptsetup.target
        Conflicts=cryptsetup.target
        ConditionKernelCommandLine=rd.qubes.hide_all_usb_after_decrypt

        [Service]
        Type=oneshot

        RemainAfterExit=yes

        TimeoutSec=3min
        ExecStop=bash -c
        {%- call systemd_inline_bash() %}
            systemctl disable --quiet usbguard.service
            systemctl stop usbguard.service
        {%- endcall %}

        [Install]
        WantedBy=basic.target

{{p}}{{ bind_pciback_device_service_path }}:
  file.managed:
    - name: {{ bind_pciback_device_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Bind %i to pciback after disk decryption
        After=basic.target
        Requires={{ unbind_pci_device_service('%i') }}
        Before={{ unbind_pci_devices_service }}
        BindsTo={{ unbind_pci_devices_service }}
        Before=cryptsetup.target
        Conflicts=cryptsetup.target
        ConditionKernelCommandLine=rd.qubes.hide_all_usb_after_decrypt
        ConditionKernelCommandLine=!rd.qubes.keep_pci_after_decrypt=%i
        ConditionPathIsDirectory=/sys/bus/pci/devices/0000:%i

        [Service]
        Type=oneshot

        RemainAfterExit=yes

        TimeoutSec=3min
        ExecStop=bash -c
        {%- call systemd_inline_bash() %}
            if [[ "$(systemctl is-system-running || true)" == "stopping" ]]; then
                echo "Detected system shutdown, skipping USB unbind"
                exit 1
            fi
            set -e
            BDF="0000:%i"
            echo "Triggering driver scan for %i"
            echo -n "$BDF" > "/sys/bus/pci/drivers_probe"
        {%- endcall %}

        [Install]
        WantedBy=basic.target

{{p}}{{ usbguard_override }}:
  file.managed:
    - name: {{ usbguard_override }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Service]
        ExecCondition=/bin/sh -c '! systemctl is-active {{ unbind_pci_devices_service }}'

{% for script in [hook_script_name, start_usbguard_script_name] %}
{{p}}{{ mod_dir }}/{{ script }}:
  file.managed:
    - name: {{ mod_dir }}/{{ script }}
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        #!/usr/bin/bash --
        # {{ salt_warning }}
        type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh
        {% if script == start_usbguard_script_name %}
        if ! getargbool 1 usbcore.authorized_default; then
            info "Restricting USB in dom0 via usbguard."
            systemctl --quiet -- enable usbguard.service
            systemctl --no-block start usbguard.service
        fi
        {% endif %}
        HIDE_NETWORK=$(set -o pipefail; { lspci -mm -n | awk "/^[^ ]* \"02/ {print \$1}";}) ||
            die 'Cannot obtain list of PCI devices to unbind.'
        HIDE_USB=$(set -o pipefail; { lspci -mm -n | awk "/^[^ ]* \"0c03/ {print \$1}";}) ||
            die 'Cannot obtain list of PCI devices to unbind.'
        shopt -s nullglob
        # Allow the network interface to rebind directly at boot
        for dev in $HIDE_NETWORK; do
            bind_pciback_service="{{ bind_pciback_device_service('$dev') }}"
            unbind_device_service="{{ unbind_pci_device_service('$dev') }}"
            unbind_override_path="/usr/lib/systemd/system/$unbind_device_service.d"
            pciback_override_path="/usr/lib/systemd/system/$bind_pciback_service.d"
            echo "Creating overrides '$unbind_override_path' and '$pciback_override_path'"
            mkdir -p -- "$unbind_override_path" "$pciback_override_path"
            cat > "$unbind_override_path/unbind_network_early.conf" <<EOF
            [Unit]
            BindsTo=
            After=
            Conflicts=
            Before=network-pre.target
            Conflicts=network-pre.target
            [Service]
            ExecStartPost=-systemctl --no-block -- stop "$unbind_device_service"
        EOF
            cat > "$pciback_override_path/rebind_network_early.conf" <<EOF
            [Unit]
            StopWhenUnneeded=yes
            Requires=
            After=
            BindsTo=
            BindsTo=$unbind_device_service
            Before=$unbind_device_service
            Conflicts=
        EOF
        done
        systemctl daemon-reload
        for dev in $HIDE_NETWORK $HIDE_USB; do
            pciback_service="{{ bind_pciback_device_service('$dev') }}"
            echo "Starting $pciback_service"
            systemctl --quiet -- enable "$pciback_service"
            systemctl --no-block -- start "$pciback_service"
        done
        if getargbool 0 rd.qubes.hide_all_usb_after_decrypt; then
            getargbool 1 usbcore.authorized_default || exit
            getargbool 0 rd.qubes.hide_all_usb && exit
            warn 'USB in dom0 is not restricted during boot with only rd.qubes.hide_all_usb_after_decrypt. Consider adding usbcore.authorized_default=0 or rd.qubes.hide_all_usb in combination with rd.qubes.dom0_usb.'
        fi
{% endfor %}

{{p}}{{ mod_dir }}/{{ usbguard_rule_filename }}:
  {% if (usbguard_rules | length) == 0 %}
  file.absent:
    - name: {{ mod_dir }}/{{ usbguard_rule_filename }}
  {% else %}
  file.managed:
    - name: {{ mod_dir }}/{{ usbguard_rule_filename }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        ## {{ salt_warning }}

        {% filter indent(8) %}
        {%- for rule in usbguard_rules -%}
        {{ rule + "\n" }}
        {%- endfor %}
        {%- endfilter %}
  {%- endif %}

  {% call add_dependencies('dracut') %}
    - file: {{p}}setup
    - file: {{p}}{{ mod_dir }}/{{ usbguard_rule_filename }}
    - file: {{p}}{{ mod_dir }}/{{ hook_script_name }}
    - file: {{p}}{{ mod_dir }}/{{ start_usbguard_script_name }}
    - file: {{p}}{{ unbind_pci_device_service_path }}
    - file: {{p}}{{ unbind_pci_devices_service_path }}
    - file: {{p}}{{ bind_pciback_device_service_path }}
    - file: {{p}}{{ usbguard_override }}
  {% endcall %}

  {% call add_dependencies('daemon-reload') %}
    {% for file in [usbguard_override, unbind_pci_devices_service_path, unbind_pci_device_service_path, bind_pciback_device_service_path] %}
    - file: {{p}}{{ file }}
    {% endfor %}
  {% endcall %}

{% endif %}
