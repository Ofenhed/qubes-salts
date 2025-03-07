# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning %}

{% if salt['pillar.get']('qubes:type') == 'template' %}
set mpv video output:
  file.append:
    - name: /etc/mpv/mpv.conf
    - contents: |
         vo=x11
         profile=sw-fast
{% endif %}
