# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "grub.jinja" import grub_options, cmdline_xen, cmdline_linux %}

{%- if grains['id'] == 'dom0' %}
  {{ grub_options(cmdline_linux, 'Force systemd measurements', 'systemd.setenv=SYSTEMD_FORCE_MEASURE=1', 'force-systemd-measurements') }}
{%- endif %}

