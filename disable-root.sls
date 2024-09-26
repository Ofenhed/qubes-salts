# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning %}

{% if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'app' %}
/rw/config/rc.local.d/disable-root.rc:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - makedirs: true
    - dir_mode: 555
    - replace: true
    - contents: |
         #!/bin/sh
         # {{ salt_warning }}

         rm -f /etc/sudoers.d/qubes
         rm -f /etc/polkit-1/rules.d/00-qubes-allow-all.rules
{% endif %}
