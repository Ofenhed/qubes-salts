# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning %}

{% if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'app' and grains['os_family'] == 'RedHat' %}
/rw/config/rc.local.d/10-disable-root.rc:
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

         dnf remove --noautoremove -y qubes-core-agent-passwordless-root
{% endif %}
