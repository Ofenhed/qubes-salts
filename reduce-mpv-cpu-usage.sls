# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if salt['pillar.get']('qubes:type') == 'template' %}
  {%- set p = "Reduce mpv cpu usage - " %}
  {%- set create_file = "Create config file" %}
  {%- set mpv_config_file = "/etc/mpv/mpv.conf" %}
  {%- from "ordering.jinja" import package_installation_complete %}

{{p}}{{create_file}}:
  file.managed:
    - name: {{ mpv_config_file }}
    - user: root
    - group: root
    - mode: 0644
    - makedirs: true
    - dir_mode: 0755
    - replace: false
    - contents: ""

{{p}}Set mpv video output:
  file.blockreplace:
    - name: /etc/mpv/mpv.conf
    - order: {{ package_installation_complete }}
    - marker_start: "# mpv CPU reduction >>>"
    - marker_end: "# <<< mpv CPU reduction"
    - show_changes: True
    - append_if_not_found: True
    - require:
      - file: {{p}}{{create_file}}
    - content: |
         vo=x11
         profile=sw-fast
{% endif %}
