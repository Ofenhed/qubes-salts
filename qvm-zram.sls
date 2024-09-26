# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning %}

{% if grains['id'] != 'dom0' %}

{% set in_template = salt['pillar.get']('qubes:type') == 'template' %}

{% set bin_path = '/usr/bin' if in_template else '/usr/local/bin' %}

{{ bin_path }}/zram_start:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - replace: {{ "true" if in_template else "false" }}
    - contents: |
        #!/usr/bin/env bash
        # Create a swap device in RAM with the 'zram' kernel module. Copy this file to /usr/local/bin.
        
        # Show supported compression algorithms...
        #  cat /sys/block/zram0/comp_algorithm
        compress="{{ salt['pillar.get']('zram:compress', 'lz4hc') }}"
        
        disksize="{{ salt['pillar.get']('zram:disksize', '2G') }}" #Set this accordingly to available RAM
        priority="32767"  # give zram device highest priority
        
        # Disable zswap  in order to prevent zswap intercepting memory pages being swapped out before they reach zram
        echo 0 > /sys/module/zswap/parameters/enabled
        # Disable any active swaps (I don't want to disable swap to prevent crashes that - uncomment if you want to completely disable swap)
        {{ '# ' if not salt['pillar.get']('zram:swap', false) else '' }}swapoff --all
        # Load module
        modprobe zram num_devices=1
        # Set compression algorithm
        echo $compress > /sys/block/zram0/comp_algorithm
        # Set disk size
        echo $disksize > /sys/block/zram0/disksize
        # Activate
        mkswap --label zram0 /dev/zram0
        swapon --priority $priority /dev/zram0

{{ bin_path }}/zram_stop:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - replace: {{ "true" if in_template else "false" }}
    - contents: |
        #!/usr/bin/env bash
        # Deactivate zram0 swap device in RAM. Copy this file to /usr/local/bin.
        
        swapoff /dev/zram0
        
        # Free already allocated memory to device, reset disksize to 0, and unload the module
        echo 1 > /sys/block/zram0/reset
        
        sleep 1
        modprobe -r zram

  {% if in_template %}

/usr/lib/systemd/system/zram_swap.service:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - replace: true
    - contents: |
        [Unit]
        Description=Configure zram swap device
        {%- if salt['pillar.get']('zram:require-meminfo', true) %}
        ConditionPathExists=/run/qubes-service/meminfo-writer
        {%- endif %}
        After=local-fs.target
        
        [Service]
        Type=oneshot
        ExecStart=zram_start
        ExecStop=zram_stop
        RemainAfterExit=yes
        
        [Install]
        WantedBy=multi-user.target

/etc/systemd/system/multi-user.target.wants/zram_swap.service:
  file.symlink:
    - target: /usr/lib/systemd/system/zram_swap.service

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
        vm.vfs_cache_pressure=500
        vm.swappiness=100
        vm.dirty_background_ratio=1
        vm.dirty_ratio=50
        vm.oom_kill_allocating_task=1
  {% endif %}
{% endif %}
