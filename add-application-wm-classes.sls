# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning %}
{%- from "ordering.jinja" import package_installation_complete %}
{%- set p = "Add WM_CLASS to application launchers - " %}

{%- if salt['pillar.get']('qubes:type') == 'template' %}
  {%- for application, wm_class in salt['pillar.get']('user:applications:wm-classes', {}).items() %}
    {%- set filename = "/usr/share/applications/" + application + ".desktop" %}
{{p}}Modify {{ filename }}:
  file.blockreplace:
    - name: {{ filename }}
    - order: {{ package_installation_complete }}
    - onlyif:
      - test -f {{ filename }}
    - backup: false
    - marker_start: |
        # Salt injected StartupWMClass start
    - marker_end: |
        # Salt injected StartupWMClass end
    - content: |
        StartupWMClass={{ wm_class }}
    - insert_after_match: |
        \[Desktop Entry\]
  {%- endfor %}
{%- endif %}
