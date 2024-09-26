# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import systemd_inline_bash, salt_warning %}
{% from "dependents.jinja" import add_dependencies %}

{% set p = "Hide USB after decrypt" %}

{% set module_name = "hide-all-usb-after-decrypt" %}
{% set mod_dir = "/lib/dracut/modules.d/90" + module_name %}
{% set unbind_usb_devices_service = "hide-all-usb-devices.service" %}
{% set unbind_usb_devices_service_path = "/usr/lib/systemd/system/" + unbind_usb_devices_service %}
{% set fido2_dracut_conf = "/lib/dracut/dracut.conf.d/90-hide-all-usb-after-decrypt.conf" %}
{% set usbguard_override = "/usr/lib/systemd/system/usbguard.service.d/hide-all-usb-after-decrypt.conf" %}
{% set usbguard_rule_filename = "50-cryptsetup-devices.conf" %}
{% set hook_script_name = "check-hide-all-usb-options.sh" %}
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
        
            # Return 255 to only include the module, if another module requires it.
            return 255
        }
        
        # Module dependency requirements.
        depends() {
            # This module has external dependency on other module(s).
            echo crypt qubes-pciback fido2 bash
            # Return 0 to include the dependent module(s) in the initramfs.
            return 0
        }
        
        # Install the required file(s) and directories for the module in the initramfs.
        install() {
            # Install required libraries.
            {% if (usbguard_rules | length) > 0 %}
            inst "$moddir/{{ usbguard_rule_filename }}" "/etc/usbguard/rules.d/{{ usbguard_rule_filename }}"
            {% endif %}
            inst_multiple {{ unbind_usb_devices_service_path }} {{ usbguard_override }}
            $SYSTEMCTL -q --root "$initdir" enable {{ unbind_usb_devices_service }}
        }

{{p}}{{ fido2_dracut_conf }}:
  file.managed:
    - name: {{ fido2_dracut_conf }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        add_dracutmodules+=" {{ module_name }} "

{{p}}{{ unbind_usb_devices_service_path }}:
  file.managed:
    - name: {{ unbind_usb_devices_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Unbind USB after disk decryption
        After=basic.target
        Before=cryptsetup.target
        Conflicts=cryptsetup.target
        ConditionKernelCommandLine=rd.qubes.hide_all_usb_after_decrypt
        
        [Service]
        Type=oneshot

        RemainAfterExit=yes
        ExecStop=bash -c
        {%- call systemd_inline_bash() %}
            if [[ "$(systemctl is-system-running || true)" == "stopping" ]]; then
                echo "Detected system shutdown, skipping USB unbind"
                exit 1
            fi
            # Select all networking and USB devices
            re='0(2|c03)'

            HIDE_PCI=$(set -o pipefail; { lspci -mm -n | awk "/^[^ ]* \"$re/ {print \$1}";}) ||
                die 'Cannot obtain list of PCI devices to unbind.'
            (
                set -e
                shopt -s nullglob
                # ... and hide them so that they are no longer available to dom0
                for dev in $HIDE_PCI; do
                    BDF=0000:$dev
                    if [ -e "/sys/bus/pci/drivers/pciback/$BDF" ]; then
                        echo "Device $dev already unbound, skipping"
                        continue
                    fi
                    if [ -e "/sys/bus/pci/devices/$BDF/driver" ]; then
                        echo "Unbinding $dev"
                        echo -n "$BDF" > "/sys/bus/pci/devices/$BDF/driver/unbind"
                    fi
                    if [ -e "/sys/bus/pci/devices/$BDF/driver_override" ]; then
                        echo "Setting driver override for $dev"
                        echo -n pciback > "/sys/bus/pci/devices/$BDF/driver_override"
                    fi
                done
                echo "Disabling usbguard"
                systemctl disable --quiet usbguard.service
                systemctl stop usbguard.service
                for dev in $HIDE_PCI; do
                    BDF=0000:$dev
                    echo "Triggering driver scan for $dev"
                    echo -n "$BDF" > "/sys/bus/pci/drivers_probe"
                    driver_dir="$(readlink /sys/bus/pci/devices/$BDF/driver)"
                    echo "New driver is ${driver_dir##*/}"
                done
            ) || {
                systemctl start --no-block usbguard.service
                hypervisor_type=
                if [ -r /sys/hypervisor/type ]; then
                    read -r hypervisor_type < /sys/hypervisor/type || \
                        die 'Cannot determine hypervisor type'
                fi
                if [ "$hypervisor_type" = "xen" ]; then
                    die 'Cannot unbind PCI devices.'
                else
                    warn 'Cannot unbind PCI devices - not running under Xen'
                fi
            }
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
        ExecCondition=/bin/sh -c '! systemctl is-active {{ unbind_usb_devices_service }}'

{{p}}{{ mod_dir }}/{{ hook_script_name }}:
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
        if getargbool 0 rd.qubes.hide_all_usb_after_decrypt; then
            getargbool 1 usbcore.authorized_default || exit
            getargbool 0 rd.qubes.hide_all_usb && exit
            warn 'USB in dom0 is not restricted during boot with only rd.qubes.hide_all_usb_after_decrypt. Consider adding usbcore.authorized_default=0 or rd.qubes.hide_all_usb in combination with rd.qubes.dom0_usb.'
        fi

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
    - file: {{p}}{{ unbind_usb_devices_service_path }}
  {% endcall %}

  {% call add_dependencies('daemon-reload') %}
    {% for file in [usbguard_override, unbind_usb_devices_service_path] %}
    - file: {{p}}{{ file }}
    {% endfor %}
  {% endcall %}

{% endif %}
