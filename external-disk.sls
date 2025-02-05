# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import systemd_shell, salt_warning, escape_bash %}
{%- from "dependents.jinja" import add_dependencies %}

{%- set p = "External disk generator " %}

{%- set service_name = 'external-pool-disk' %}
{%- set super_service_path = '/usr/lib/systemd/system/' + service_name + '.service' %}
{%- set named_service_path = '/usr/lib/systemd/system/' + service_name + '@.service' %}
{%- set watched_files = [p + named_service_path, p + super_service_path] %}
{%- set sys_usb = salt['pillar.get']('qvm:sys-usb:name', 'sys-usb') %}

{%- if grains['id'] == 'dom0' %}
{{ p }}{{ super_service_path }}:
  file.managed:
    - name: {{ super_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Block sys-usb from being shut down while there are still mounted external disks
        Requires=qubesd.service libvirtd.service dm-event.socket
        StopPropagatedFrom=qubes-core.service
        ReloadPropagatedFrom=qubes-core.service
        After=qubes-vm@{{ sys_usb }}.service qubes-core.service qubesd.service dm-event.socket dm-event.service
        StopWhenUnneeded=yes
        RefuseManualStart=yes

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/bin/true

{{ p }}{{ named_service_path }}:
  file.managed:
    - name: {{ named_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Mount external USB device %i as a Qubes pool
        BindsTo={{ service_name }}.service
        After={{ service_name }}.service

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart={%- call systemd_shell() %}
            {%- for var in ['device_description',
                           'luks_name',
                           'logical_volume_name'] %}
            if [[ "${{ var }}" == "" ]] ; then
              echo "Missing environment parameter {{ var }}" >&2
              env >&2
              exit 1
            fi
            {%- endfor %}

            device=$(qvm-block | grep -- "$device_description" | grep -Po '^'{{ escape_bash(sys_usb) }}':sd[a-z]+'"$partition_number"'(?=\s)')
            if [[ "$device" == "" ]] ; then
              echo "Could not find device matching $device_description"
              exit 1
            fi
            echo "Found matching device $device"

            for attempt in {1..2} ; do
              device_info=$(qvm-block | grep -P '^'"$device"'\s' | grep -Po '(?<=dom0 \().*(?=\)$)')

              if [[ "$device_info" == "" ]] ; then
                if ! qvm-block attach dom0 "$device" ; then
                  echo "Could not find device $device"
                  exit 1
                fi
              fi
            done
            if [[ "$device_info" == "" ]] ; then
              exit 1
            fi

            dom0_dev_name=$(grep -Po '(?<=frontend-dev=)[a-z]+(?=,|$)' <<< "$device_info")
            dom0_dev="/dev/$dom0_dev_name"
            echo "Attached $device as $dom0_dev_name"
            luks_dev="/dev/mapper/$luks_name"
            if [[ -b "$luks_dev" ]] ; then
              echo "Luks device $luks_name is already mapped"
            else
              cryptsetup_args=()
              if [[ "$luks_allow_discard" == "1" ]] ; then
                cryptsetup_args+=( --allow-discards )
              fi
              if [[ "$luks_header_path" != "" ]] ; then
                cryptsetup_args+=( --header "$luks_header_path" )
              fi
              if [[ ! -e "$dom0_dev" ]] ; then
                echo "Block device $dom0_dev_name not found" >&2
                exit 1
              fi

              cryptsetup_args+=( "$dom0_dev" "$luks_name" )
              echo -n "Trying to open $dom0_dev_name as $luks_name with args:"
              printf ' "%%s"' "$${cryptsetup_args[@]}"
              echo
              if ! ( systemd-ask-password "Luks password for $luks_name" | cryptsetup open "$${cryptsetup_args[@]}" ) ; then
                echo "Could not open $dom0_dev"
                exit 1
              fi
              if [[ ! -b "$luks_dev" ]] ; then
                echo "Luks device $luks_dev not found" >&2
                exit 1
              fi
              echo "Device mapped as $luks_name"
            fi

            logical_volume_luks_name=$(vgs --noheadings -o pv_name "$logical_volume_name" | grep -Po '(?<=/)[^/]+$')
            if [[ "$logical_volume_luks_name" == "$luks_name" ]] ; then
              lvscan >/dev/null
            else
              echo "Invalid logical volume name '$logical_volume_name'. Matches luks name '$logical_volume_luks_name', should be '$luks_name'" >&2
              exit 1
            fi
        {%- endcall %}

        ExecStartPost=-{%- call systemd_shell() %}
            for attempt in {1..20} ; do
              if lvs -o vg_name | grep -qP '^\s*'"$logical_volume_name"'\s*$' ; then
                exit 0
              fi
            done
            echo Logical volume $logical_volume_name didn't show up
            exit 1
        {%- endcall %}

        {%- macro shutdown_vms(kill) %}
            while true ; do
              pool_vms_raw=$(qvm-volume list -p "$qvm_pool" | tail -n +2 | awk '{ print $2 }' | sort -u)
              readarray -t pool_vms <<< "$pool_vms_raw"
              if [[ "$pool_vms_raw" == "" ]] ; then
                echo "Pool has no VMs"
                break
              fi
              running_vms_raw=$(qvm-ls --running --paused "$${pool_vms[@]}" | tail -n +2 | awk '{ print $1 }')
              readarray -t running_vms <<< "$running_vms_raw"
              if [[ "$running_vms_raw" == "" ]] ; then
                echo "Pool has no running VMs"
                break
              fi
              {%- if kill %}
              echo "Killing {{ '$${#running_vms[@]}' }} VMs: $${running_vms[@]}"
              qvm-kill "$${running_vms[@]}"
              {%- else %}
              echo "Shutting down {{ '$${#running_vms[@]}' }} VMs: $${running_vms[@]}"
              qvm-shutdown --wait "$${running_vms[@]}"
              {%- endif %}
            done
        {%- endmacro %}

        TimeoutStopSec=3m

        ExecStop={%- call systemd_shell() %}
          {{ shutdown_vms(false) }}
        {%- endcall %}

        ExecStopPost={%- call systemd_shell() %}
            {{ shutdown_vms(true) }}

            luks_name=$(vgs --noheadings -o pv_name "$logical_volume_name" | grep -Po '(?<=/)[^/]+$')
            local_device=$(cryptsetup status "$luks_name" | grep -Po '(?<=device:)\s*/dev/[a-z]+$' | grep -Po '(?<=/dev/)[a-z]+$')
            remote_device=$(qvm-block | grep -P "frontend-dev=$local_device[,)]" | grep -Po {{ escape_bash(sys_usb) }}':[a-z]+[0-9]*(?=\s)')

            echo "Deactivating device /dev/$logical_volume_name"
            lvchange -an "/dev/$logical_volume_name" || exit 1

            echo "Closing cryptsetup $luks_name"
            cryptsetup close "$luks_name" || exit 1

            echo "Detaching remote device $remote_device"
            qvm-block detach dom0 "$remote_device" || exit 1
        {%- endcall %}

        [Install]
        WantedBy=multi-user.target


    {%- for (qvm_pool, device) in salt['pillar.get']('external-usb:devices', []).items() %}
  {%- set env = {'device_description': device['device-description'],
                'luks_name': device['luks-name'],
                'partition_number': device['partition-number'] if 'partition-number' in device else '',
                'logical_volume_name': device['logical-volume-name'],
                'luks_header_path': device['luks-header-path'] if 'luks-header-path' in device else None,
                'qvm_pool': qvm_pool,
                'luks_allow_discard': '1' if 'luks-allow-discard' not in device or device['luks-allow-discard'] else '0'
                } %}
    {%- set override_file = '/etc/systemd/system/' + service_name + '@' + env['luks_name'] + '.service.d/disk-parameters.conf' %}
    {%- do watched_files.append(override_file) %}
{{ p }}{{ override_file }}:
  file.managed:
    - name: {{ override_file }}
    - user: root
    - group: root
    - mode: 444
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Service]
        Environment={%- for name in env if env[name] != None -%}
          '{{ name }}={{ env[name] | replace("\\", "\\\\") | replace("'", "\\'") }}'{{ ' ' }}
        {%- endfor %}
  {%- endfor %}

  {%- call add_dependencies('daemon-reload') %}
    {%- for file in watched_files %}
  - file: {{ file }}
    {%- endfor %}
  {%- endcall %}


  {%- set blocker_py_path = "/var/cache/qubes-extension-sys-usb-shutdown-blocker" %}
  {%- set py_pip_name = "block_sys_usb_shutdown_for_external_usb_disk" %}
  {%- set py_short_package_name = "external_disk_handler" %}

{{p}}{{ blocker_py_path }}/setup.py:
  file.managed:
    - name: {{ blocker_py_path }}/setup.py
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: True
    - replace: true
    - contents: |
        # {{ salt_warning }}
        from setuptools import setup, find_packages
        import pathlib

        here = pathlib.Path(__file__).parent.resolve()

        setup(
          name="{{ py_pip_name }}",
          version="0.1.0",
          package_dir={"": "src"},
          packages=["{{ py_short_package_name }}"],
          python_requires=">=3.7,<4",
          entry_points={
              "qubes.ext": [
                "qubes.ext.{{ py_short_package_name }}={{ py_short_package_name }}:UsbProtector",
              ]
          },
        )

  {%- set blocker_script_path = blocker_py_path + "/src/" + py_short_package_name + "/__init__.py" %}

{{p}}{{ blocker_script_path }}:
  file.managed:
    - name: {{ blocker_script_path }}
    - user: root
    - group: root
    - mode: 555
    - dir_mode: 755
    - makedirs: True
    - replace: true
    - contents: |
        #!/usr/bin/env python3
        # {{ salt_warning }}
        import asyncio
        import qubes.ext
        import qubes.exc

        class UsbProtector(qubes.ext.Extension):
            """This extension blocks sys-usb from being shut down if it has active mounts"""
            @qubes.ext.handler("domain-pre-shutdown")
            async def on_domain_pre_shutdown(self, vm, event, **kwargs):
                if vm.name == "{{ sys_usb }}":
                    active_external_disks = await asyncio.create_subprocess_exec("/usr/bin/systemctl", "is-active", "-q", "{{ service_name }}.service")
                    if await active_external_disks.wait() == 0:
                        if not kwargs.get("force", False):
                            raise qubes.exc.QubesVMError(
                                self,
                                f"USB disks from {vm.name} are attached as a pool to dom0, shutting {vm.name} down before detaching will cause problems!"
                            )
                        else:
                            stopping_mounts = await asyncio.create_subprocess_exec("/usr/bin/systemctl", "stop", "{{ service_name }}.service")
                            if await stopping_mounts.wait() != 0:
                                raise qubes.exc.QubesVMError(
                                    self,
                                    "Could not stop service {{ service_name }}"
                                )

{{p}}install {{ py_pip_name }}:
  cmd.run:
    - name: python3 -m pip install --prefix /usr --compile {{ blocker_py_path }}
    - onchanges:
      - file: {{p}}{{ blocker_py_path }}/setup.py
      - file: {{p}}{{ blocker_script_path }}
{%- endif %}
