# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning, systemd_shell %}

{% if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}

/etc/qubes/post-install.d/90-zram-swap-service.sh:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}

        qvm-features-request supported-service.zram-swap=1
        qvm-features-request supported-service.zram-swap-disk-fallback=1
        qvm-features-request supported-feature.vm-config.zram-size=1
        qvm-features-request supported-feature.vm-config.zram-algorithm=1

/usr/lib/systemd/system/zram-swap.service:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Configure zram swap device
        {%- if salt['pillar.get']('zram:require-meminfo', true) %}
        ConditionPathExists=/run/qubes-service/meminfo-writer
        {%- endif %}
        ConditionPathExists=/run/qubes-service/zram-swap
        After=local-fs.target

        [Service]
        Type=oneshot
        ExecStart={%- call systemd_shell() %}
          # Create a swap device in RAM with the 'zram' kernel module. Copy this file to /usr/local/bin.

          # Show supported compression algorithms...
          #  cat /sys/block/zram0/comp_algorithm
          compress="$(qubesdb-read -q /vm-config/zram-algorithm || cat <<< "lz4hc")"

          disksize="$(qubesdb-read -q /vm-config/zram-size || cat <<< "2G")"
          priority="32767"  # give zram device highest priority

          # Disable zswap  in order to prevent zswap intercepting memory pages being swapped out before they reach zram
          echo 0 > /sys/module/zswap/parameters/enabled

          if [ ! -e /run/qubes/service/zram-swap-disk-fallback ]; then
            swapoff --all
          fi
          # Load module
          modprobe zram num_devices=1
          # Set compression algorithm
          echo "$compress" > /sys/block/zram0/comp_algorithm
          # Set disk size
          echo "$disksize" > /sys/block/zram0/disksize
          # Activate
          mkswap --label zram0 /dev/zram0
          swapon --priority $priority /dev/zram0
        {%- endcall %}
        ExecStop={%- call systemd_shell() %}
          # Deactivate zram0 swap device in RAM. Copy this file to /usr/local/bin.

          swapoff /dev/zram0

          # Free already allocated memory to device, reset disksize to 0, and unload the module
          echo 1 > /sys/block/zram0/reset

          sleep 1
          modprobe -r zram
        {%- endcall %}
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target

/etc/systemd/system/multi-user.target.wants/zram-swap.service:
  service.enabled:
    - name: zram-swap.service

/etc/udev/rules.d/30-zram.rules:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - makedirs: true
    - dir_mode: 755
    - contents: |
        {{ salt_warning }}
        ACTION!="remove", SUBSYSTEM=="block", KERNEL=="zram*", ENV{DM_UDEV_DISABLE_DISK_RULES_FLAG}="1"

/etc/sysctl.d/99-zram.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - replace: false
    - contents: |
        # {{ salt_warning }}
        vm.vfs_cache_pressure=500
        vm.swappiness=100
        vm.dirty_background_ratio=1
        vm.dirty_ratio=50
        vm.oom_kill_allocating_task=1
{% endif %}
