# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :
#
# WARNING: This script is not working, it's very experimental

{% from "grub.jinja" import grub_options, grub_list_option, cmdline_linux, cmdline_xen, apply_grub %}

{% set qube_name = 'sys-gui-gpu' %}
{% set do_attach = salt['pillar.get']('qvm:' + qube_name + ':enabled', False) %}
{% set gpu_pci_device = 'c1:00.0' %}
{% set gpu_audio_pci_device = 'c1:00.1' %}
{% set pci_devices = [gpu_pci_device, gpu_audio_pci_device] %}
{% set pci_devices_qubes_format = pci_devices | map("replace", ":", "_", 1) | list %}
{% set module_name = "load_vfio_pci" %}
{% set mod_dir = "/lib/dracut/modules.d/90" + module_name %}

{% macro rpm_check(filename, valid) -%}
  {{ "'" }}
  {%- if valid -%}
    {{ "! ( " }}
  {%- endif -%}
  rpm -Vf ''{{ filename }}'' | grep -qP ''^..5.*\s{{ filename | regex_escape }}$''
  {%- if valid -%}
    {{ " )" }}
  {%- endif -%}
  {{ "'" }}
{%- endmacro %}

{% if grains['id'] == 'dom0' %}
  {% set vfio_devices = [] %}
  {% for device in pci_devices %}
    {% set vfio_vendor = salt['file.read']('/sys/bus/pci/devices/0000:' + device + '/vendor') | replace('0x', '', 1) | trim() %}
    {% set vfio_device = salt['file.read']('/sys/bus/pci/devices/0000:' + device + '/device') | replace('0x', '', 1) | trim() %}
    {% do vfio_devices.append(vfio_vendor + ':' + vfio_device) %}
  {% endfor %}
{{ qube_name }} autostart:
  qvm.prefs:
    - name: {{ qube_name }}
    - autostart: {{ do_attach }}

{% set vchan = '/usr/bin/vchan-socket-proxy' %}
{% if do_attach %}
Extract GPU BIOS:
  file.copy:
    - name: /usr/libexec/xen/boot/gpubios
    - source: /sys/kernel/debug/dri/0/amdgpu_vbios

{% set vchan_backup = "Create " + vchan + " backup" %}
{{ vchan_backup }}:
  file.copy:
    - name: {{ vchan }}.orig
    - source: {{ vchan }}
    - force: True
    - preserve: True
    - onlyif:
      - {{ rpm_check(vchan, True) }}

Create vchan-socket-proxy override with romfile:
  file.managed:
    - name: {{ vchan }}
    - require:
      - file: {{ vchan_backup }}
    - onlyif:
      - test -f {{ vchan }}.orig
    - mode: 555
    - user: root
    - group: root
    - contents: |
        #!/bin/bash
        vchan_args=( "$@" )
        if [[ ${{ '{#' }}vchan_args[@]} -lt 3 ]] ; then
          /usr/bin/vchan-socket-proxy.orig "${vchan_args[@]}"
          exit $?
        fi
        vchan_sock="${vchan_args[-1]}"
        unset 'vchan_args[-1]'
        /usr/bin/vchan-socket-proxy.orig "${vchan_args[@]}" "${vchan_sock}.internal" &
        channel_pid=$!
        socat UNIX-LISTEN:"${vchan_sock}",fork "EXEC:/usr/bin/vchan-socket-proxy.add_romfile '${vchan_sock}.internal'" &
        socat_pid=$!
        wait "${channel_pid}"
        kill "${socat_pid}"
       
Create vchan-socket-proxy stream updater:
  file.managed:
    - name: {{ vchan }}.add_romfile
    - mode: 555
    - user: root
    - group: root
    - contents: |
        #!/bin/bash
        while [[ ! -S "$1" ]] ; do
          sleep 0.10
        done
        sed -u -e 's|"hostaddr":"0000:{{ gpu_pci_device }}"|"hostaddr":"0000:{{ gpu_pci_device }}","romfile":"/share/gpubios"|' | socat - UNIX-CONNECT:"$1"

{% else %}
{% set restore_vchan = "Restore vchan-socket-proxy romfile override" %}
{{ restore_vchan }}:
  file.copy:
    - name: {{ vchan }}
    - source: {{ vchan }}.orig
    - force: True
    - order: 1
    - onlyif:
      - test -f {{ vchan }}.orig
      - {{ rpm_check(vchan, false) }}

Remove vchan-socket-proxy stream updater:
  file.absent:
    - name: {{ vchan }}.add_romfile

Remove vchan-socket-proxy backup:
  file.absent:
    - name: {{ vchan }}.orig
    - order: 2
    - onlyif:
      - {{ rpm_check(vchan, True) }}

Reinstall vchan-socket-proxy if it's corrupted:
  pkg.installed:
    - name: xen-runtime
    - require: 
      - file: {{ restore_vchan }}
    - verify_options:
      - nodeps
    - reinstall: True
    - order: 3
    - onlyif:
      - {{ rpm_check(vchan, False) }}
      - "test ! -f '{{ vchan }}.orig' || diff '{{ vchan }}' '{{ vchan }}.orig'"
{% endif %}

{% for package, file in {"xen-hvm-stubdom-linux": "/usr/libexec/xen/boot/qemu-stubdom-linux-rootfs", "xen-hvm-stubdom-linux-full": "/usr/libexec/xen/boot/qemu-stubdom-linux-full-rootfs"}.items() %}
  {% if do_attach %}
    {% set create_backup = "Create backup for " + file %}
{{ create_backup }}: 
  file.copy:
    - name: {{ file }}.orig
    - force: True
    - onlyif:
      - {{ rpm_check(file, True) }}
      - "! diff '{{ file }}' '{{ file }}.orig'"
    - source: {{ file }}
    - preserve: True

{% set tmp_dir = salt['cmd.run']('mktemp -d') %}
Patch {{ file }} with vbios:
  cmd.run:
    - shell: /bin/bash
    - require:
      - file: {{ create_backup }}
    - onlyif:
      - "test -f '{{ file }}.orig'"
      - {{ rpm_check(file, True) }}
    - name: 'zcat ''{{ file }}.orig''|cpio -idm && cp -a /usr/libexec/xen/boot/gpubios ./share/gpubios && find . | cpio -o -c | gzip -9 > ''{{ file }}'''
    - cwd: '{{ tmp_dir }}'
  {% else %}
Restore backup for {{ file }}:
  file.copy:
    - name: {{ file }}
    - force: True
    - onlyif:
      - {{ rpm_check(file, True) }}
      - "test -f '{{ file }}.orig'"
      - "! diff '{{ file }}' '{{ file }}.orig'"
    - source: {{ file }}.orig
    - preserve: True

Delete backup file for {{ file }}:
  file.absent:
    - require:
      - file: {{ file }}
    - name: {{ file }}.orig
    - onlyif:
      - {{ rpm_check(file, True) }}

Restore {{ file }} from RPM:
  pkg.installed:
    - name: '{{ package }}'
    - verify_options:
      - nodeps
    - reinstall: True
    - onlyif:
      - {{ rpm_check(file, False) }}
      - "test ! -f '{{ file }}.orig' || diff '{{ file }}' '{{ file }}.orig'"
  {% endif %}
{% endfor %}

  {% if do_attach %}
{{ qube_name }}-attach-gpu:
  qvm.devices:
    - name: {{ qube_name }}
      {% if (pci_devices_qubes_format | length) > 0 %}
    - attach:
      {% for pci_device in pci_devices_qubes_format %}
      - pci:dom0:{{ pci_device }}:
        - permissive: true
        - no-strict-reset: true
      {% endfor %}
    {% endif %}

  {% else %}

    {% set mounted_devices = salt['qvm.devices'](qube_name, 'list')['comment'] %}
    {% set attached = [] %}
    {% for device in pci_devices_qubes_format if device in mounted_devices %}
      {% do attached.append(device) %}
    {% endfor %}
    {% if (attached | length) != 0 %}
{{ qube_name }}-detach-gpu:
  qvm.devices:
    - name: {{ qube_name }}
    - failhard: False
    - detach:
      {% for pci_device in attached %}
      - pci:dom0:{{ pci_device }}: []
      {% endfor %}
    {% endif %}
  {% endif %}

  {{ grub_options(cmdline_linux, 'Disable console gui', 'efifb:off nomodeset', None, do_attach) }}
  {{ grub_options(cmdline_linux, 'Blacklist sysfb_init', 'initcall_blacklist=sysfb_init', None, do_attach) }}
  {{ grub_list_option(cmdline_linux, 'Disable dom0 graphics', 'rd.qubes.hide_pci', pci_devices, None, do_attach) }}
  {{ grub_list_option(cmdline_linux, 'Activate vfio-pci', 'vfio-pci.ids', vfio_devices, None, do_attach) }}
  {{ grub_options(cmdline_linux, 'Disable vfio-pci vga', 'vfio-pci.disable_vga=1', None, do_attach) }}
  {{ grub_options(cmdline_linux, 'Blacklist dom0 graphics', 'rd.driver.blacklist=amdgpu', None, do_attach) }}
  {{ grub_options(cmdline_linux, 'Blacklist dom0 graphics fallback', 'rd.driver.blacklist=radeon', None, do_attach) }}
  {{ grub_options(cmdline_linux, 'Activate iommu passthrough', 'iommu=pt', None, do_attach) }}

{% endif %}
