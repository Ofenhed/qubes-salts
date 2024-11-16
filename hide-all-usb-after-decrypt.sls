# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :
# To use this module, create a .conf file in /etc/dracut.conf.d/ with which
# loads either this module or fido2, as such:
# add_dracutmodules+=" hide-all-usb-after-decrypt "

{% from "formatting.jinja" import escape_bash, salt_warning %}
{% from "dependents.jinja" import add_dependencies %}

{% set p = "Hide USB after decrypt " %}

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
{% set network_override_filename = "rebind-network-early.conf" %}
{% set unbind_pci_device_service_network_override_dir = "/usr/lib/systemd/system/" + unbind_pci_device_service('network') + ".d" %}
{% set unbind_pci_device_service_network_override_path = unbind_pci_device_service_network_override_dir + "/" + network_override_filename %}
{% set bind_pciback_device_service_network_override_dir = "/usr/lib/systemd/system/" + bind_pciback_device_service('network') + ".d" %}
{% set bind_pciback_device_service_network_override_path = bind_pciback_device_service_network_override_dir + "/" + network_override_filename %}
{% set unbind_pci_devices_service_path = "/usr/lib/systemd/system/" + unbind_pci_devices_service %}
{% set hook_script_name = "check-hide-all-usb-options.sh" %}
{% set authorized_decrypt_usb = salt['pillar.get']('hide-all-usb-after-decrypt:udev:authorized', [
  {'SUBSYSTEM': 'hid', 'ATTR{idVendor}': '1050'},
  {'SUBSYSTEM': 'usb', 'ATTR{idVendor}': '1050'},
  {'SUBSYSTEM': 'usb', 'ATTR{bDeviceClass}': '09', 'ATTR{bDeviceSubClass}': '00', 'ATTR{bDeviceProtocol}': '00'},
  {'SUBSYSTEM': 'usb', 'ATTR{bDeviceClass}': '09', 'ATTR{bDeviceSubClass}': '00', 'ATTR{bDeviceProtocol}': '01'},
  {'SUBSYSTEM': 'usb', 'ATTR{bDeviceClass}': '09', 'ATTR{bDeviceSubClass}': '00', 'ATTR{bDeviceProtocol}': '02'},
  {'SUBSYSTEM': 'usb', 'ATTR{bDeviceClass}': '09', 'ATTR{bDeviceSubClass}': '00', 'ATTR{bDeviceProtocol}': '03'},
  ]) %}
{% set authorized_decrypt_usb_filename = '20-authorized-decrypt.rules' %}


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
            inst_multiple {{ unbind_pci_devices_service_path }} {{ unbind_pci_device_service_path }} {{ bind_pciback_device_service_path }} {{ unbind_pci_device_service_network_override_path }} {{ bind_pciback_device_service_network_override_path }}
            inst "$moddir/{{ authorized_decrypt_usb_filename }}" "/usr/lib/udev/rules.d/{{ authorized_decrypt_usb_filename }}"
            inst_hook cmdline 05 "$moddir/{{ hook_script_name }}"
            $SYSTEMCTL -q --root "$initdir" mask usbguard.service
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

        ExecStop=bash -c
        {%- call escape_bash() %}
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

        ExecStart="true"

        [Install]
        WantedBy=basic.target

{{p}}{{ unbind_pci_device_service_network_override_path }}:
  file.managed:
    - name: {{ unbind_pci_device_service_network_override_path }}
    - user: root
    - group: root
    - mode: 444
    - makedirs: true
    - dirmode: 555
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        BindsTo=
        After=
        Conflicts=
        Before=network-pre.target
        Conflicts=network-pre.target
        [Service]
        ExecStartPost=-systemctl --no-block -- stop "{{ unbind_pci_device_service('%i') }}"

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

        ExecStop=bash -c
        {%- call escape_bash() %}
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

{{p}}{{ bind_pciback_device_service_network_override_path }}:
  file.managed:
    - name: {{ bind_pciback_device_service_network_override_path }}
    - user: root
    - group: root
    - mode: 444
    - makedirs: true
    - dirmode: 555
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        StopWhenUnneeded=yes
        Requires=
        After=
        BindsTo=
        BindsTo={{ unbind_pci_device_service('%i') }}
        Before={{ unbind_pci_device_service('%i') }}
        Conflicts=

{{p}}{{ hook_script_name }}:
  file.managed:
    - name: {{ mod_dir }}/{{ hook_script_name }}
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
            mkdir -p "$unbind_override_path" "$pciback_override_path"
            ln -s "{{ unbind_pci_device_service_network_override_path }}" "$unbind_override_path/{{ network_override_filename }}"
            ln -s "{{ bind_pciback_device_service_network_override_path }}" "$pciback_override_path/{{ network_override_filename }}"
        done
        systemctl daemon-reload
        for dev in $HIDE_NETWORK $HIDE_USB; do
            pciback_service="{{ bind_pciback_device_service('$dev') }}"
            echo "Starting $pciback_service"
            systemctl --quiet --no-block --now -- enable "$pciback_service"
        done
        getargbool 0 rd.qubes.hide_all_usb && exit

        if getargbool 0 rd.qubes.hide_all_usb_after_decrypt; then
            getargbool 1 usbcore.authorized_default || exit
            warn 'USB in dom0 is not restricted during boot with only rd.qubes.hide_all_usb_after_decrypt. Consider adding usbcore.authorized_default=0 to the command line.'
        else
            warn 'USB in dom0 is not restricted. Consider adding rd.qubes.hide_all_usb_after_decrypt and usbcore.authorized_default=0.'
        fi

{{p}}{{ authorized_decrypt_usb_filename }}:
  file.managed:
    - name: {{ mod_dir }}/{{ authorized_decrypt_usb_filename }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        ACTION!="add", GOTO="authorized_end"
        {% for rule in authorized_decrypt_usb %}
        {{ "" }}
          {%- for (key, value) in rule.items() -%}
            {{key}}=="{{ value }}",
          {%- endfor -%}
          ATTR{authorized}="1", GOTO="authorized_end"
        {%- endfor %}

        LABEL="authorized_end"

  {% call add_dependencies('dracut') %}
    - file: {{p}}setup
    - file: {{p}}{{ hook_script_name }}
    - file: {{p}}{{ authorized_decrypt_usb_filename }}
    - file: {{p}}{{ unbind_pci_device_service_path }}
    - file: {{p}}{{ unbind_pci_devices_service_path }}
    - file: {{p}}{{ bind_pciback_device_service_path }}
  {% endcall %}

  {% call add_dependencies('daemon-reload') %}
    {% for file in [unbind_pci_devices_service_path, unbind_pci_device_service_path, bind_pciback_device_service_path] %}
    - file: {{p}}{{ file }}
    {% endfor %}
  {% endcall %}

{% endif %}
