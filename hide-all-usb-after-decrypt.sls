# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :
# To use this module, create a .conf file in /etc/dracut.conf.d/ with which
# loads either this module or fido2, as such:
# add_dracutmodules+=" hide-all-usb-after-decrypt "

{% from "formatting.jinja" import systemd_shell, salt_warning %}
{% from "dependents.jinja" import add_dependencies %}

{% set p = "Hide USB after decrypt " %}

{% set module_name = "hide-all-usb-after-decrypt" %}
{% set mod_dir = "/lib/dracut/modules.d/92" + module_name %}
{% set hide_all_usb_service_name = "hide-all-usb-after-decrypt.service" %}
{% set hide_all_usb_service_path = "/usr/lib/systemd/system/" + hide_all_usb_service_name %}
{% set hide_all_network_service_name = "hide-all-network-on-boot.service" %}
{% set hide_all_network_service_path = "/usr/lib/systemd/system/" + hide_all_network_service_name %}
{% set hook_script_name = "qubes-pciback.sh" %}
{% set hide_all_env_path = "/etc/sysconfig/hide-all-usb-after-decrypt" %}
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
            if dracut_module_included "qubes-pciback"; then
                derror "hide-all-usb-after-decrypt conflicts with qubes-pciback"
                return 1
            fi

            inst_multiple lspci awk bash true cat sort
            inst_multiple {{ hide_all_usb_service_path }} {{ hide_all_network_service_path }} {{ hide_all_env_path }}
            inst_rules "$moddir/{{ authorized_decrypt_usb_filename }}"
            inst_hook cmdline 02 "$moddir/{{ hook_script_name }}"
            $SYSTEMCTL -q --root "$initdir" enable '{{ hide_all_network_service_name }}' '{{ hide_all_usb_service_name }}'
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

{{p}}{{ hide_all_env_path }}:
  file.managed:
    - name: {{ hide_all_env_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        EXTRA_USB_TO_UNBIND={{ salt["cmd.run"](["bash", "-c", "qvm-pci list -- sys-usb | grep -Po '(?<=dom0:)[^ ]+'"]) | replace("\n", " ") | replace("_", ":") }}
        EXTRA_NETWORK_TO_UNBIND={{ salt["cmd.run"](["bash", "-c", "qvm-pci list -- sys-net | grep -Po '(?<=dom0:)[^ ]+'"]) | replace("\n", " ") | replace("_", ":") }}

{% for service_path in [hide_all_usb_service_path, hide_all_network_service_path] %}
{{p}}{{ service_path }}:
  file.managed:
    - name: {{ service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - require:
      - file: {{p}}{{ mod_dir }}
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=
        {%- if service_path == hide_all_usb_service_path -%}
        Unbind all USB after disk decryption
        {%- elif service_path == hide_all_network_service_path -%}
        Unbind all network when the machine boots
        {%- endif %}
        ConditionKernelCommandLine=!rd.qubes.hide_all_usb
        {%- set deadline = "cryptsetup.target" if service_path == hide_all_usb_service_path else "network-pre.target" %}
        Before={{ deadline }}
        Conflicts={{ deadline }}

        [Service]
        Type=oneshot
        EnvironmentFile={{ hide_all_env_path }}

        RemainAfterExit=yes

        ExecStart="true"
        {% if service_path == hide_all_network_service_path %}
        ExecStartPost=-systemctl --no-block -- stop "{{ hide_all_network_service_name }}"
        {% endif %}
        ExecStopPost={%- call systemd_shell() %}
            if [[ "$(systemctl is-system-running || true)" == "stopping" ]]; then
                echo "Detected system shutdown, skipping USB unbind"
                exit 1
            fi
            set -e
            {%- if service_path == hide_all_usb_service_path %}
              hide_pci=$(set -o pipefail; { lspci -mm -n | awk "/^[^ ]* \"0c03/ {print \$1}"; echo -n "$EXTRA_USB_TO_UNBIND"; } | sort -u) || die 'Cannot obtain list of PCI devices to unbind.'
            {%- elif service_path == hide_all_network_service_path %}
              hide_pci=$(set -o pipefail; { lspci -mm -n | awk "/^[^ ]* \"02/ {print \$1}"; echo -n "$EXTRA_NETWORK_TO_UNBIND"; } | sort -u) ||  die 'Cannot obtain list of PCI devices to unbind.'
            {%- endif %}

            for dev in $hide_pci; do
              BDF="0000:$dev"
              if [ -e "/sys/bus/pci/drivers/pciback/$BDF" ]; then
                echo "Device $dev already owned by pciback"
                continue
              fi

              if [ -e "/sys/bus/pci/devices/$BDF/driver_override" ]; then
                  echo "Setting driver override for $dev"
                  echo -n pciback > "/sys/bus/pci/devices/$BDF/driver_override"
              else
                  echo "Could not set driver override for $dev" >&2
                  exit 1
              fi
              if [ -e "/sys/bus/pci/devices/$BDF/driver" ]; then
                  echo "Unbinding $dev"
                  echo -n "$BDF" > "/sys/bus/pci/devices/$BDF/driver/unbind"
              else
                  echo "Device $dev is not bound by a driver" >&2
              fi
            done
            for dev in $hide_pci; do
              BDF="0000:$dev"
              echo "Requesting device probe for $dev"
              echo -n "$BDF" > "/sys/bus/pci/drivers_probe"
            done
        {%- endcall %}

        [Install]
        WantedBy=
        {%- if service_path == hide_all_usb_service_path -%}
          systemd-ask-password-plymouth.service systemd-ask-password-wall.service systemd-ask-password-console.service
        {%- elif service_path == hide_all_network_service_path -%}
          basic.target
        {%- endif %}
{% endfor %}


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
        # Allow the network interface to rebind directly at boot
        systemctl daemon-reload
        # getargbool 0 rd.qubes.hide_all_usb && exit

        if ! getargbool 0 rd.qubes.hide_all_usb_after_decrypt; then
            warn 'USB in dom0 is not restricted. Consider adding rd.qubes.hide_all_usb_after_decrypt.'
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
    - file: {{p}}{{ hide_all_usb_service_path }}
    - file: {{p}}{{ hide_all_network_service_path }}
    - file: {{p}}{{ hide_all_env_path }}
  {% endcall %}

  {% call add_dependencies('daemon-reload') %}
    {% for file in [hide_all_usb_service_path, hide_all_network_service_path, hide_all_env_path] %}
    - file: {{p}}{{ file }}
    {% endfor %}
  {% endcall %}

{% endif %}
