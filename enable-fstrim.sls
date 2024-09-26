# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "grub.jinja" import grub_options, grub_list_option, cmdline_linux, cmdline_xen, apply_grub %}

{% if grains['id'] == 'dom0' %}
Activate LVM disk trimming in LVM:
  file.replace:
    - name: /etc/lvm/lvm.conf
    - pattern: '^([ \t]*issue_discards[ \t]*=[ \t]*)0$'
    - repl: '\g<1>1'
    - ignore_if_missing: True

  {{ grub_list_option(cmdline_linux, 'Activate cryptsetup disk trimming kernel option', 'rd.luks.options', ['discard'], 'enable-cryptfs-discard') }}
{% endif %}
