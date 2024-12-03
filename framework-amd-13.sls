# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "grub.jinja" import grub_options, grub_list_option, cmdline_xen, cmdline_linux, apply_grub %}

{% if grains['id'] == 'dom0' %}
  {{ grub_options(cmdline_linux, 'Quiet boot', 'quiet', 'quiet-boot') }}
  {{ grub_options(cmdline_linux, 'Disable dom0 graphics', 'video=efifb:off nomodeset', 'disable-dom0-graphics', False) }}
  {{ grub_options(cmdline_xen, 'Fix shutdown issue', 'ioapic_ack=new', 'fix-shutdown-issue') }}
{% endif %}
