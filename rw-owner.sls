# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'app' %}
  {%- set p = "Set root owner to /rw - " %}
{{p}}config:
  file.directory:
    - name: /rw/config/
    - user: root
    - group: root
    - recurse:
      - user

{{p}}/usr/local/:
  file.directory:
    - name: /rw/usrlocal/
    - user: root
    - group: root
    - recurse:
      - user

{%- endif %}
