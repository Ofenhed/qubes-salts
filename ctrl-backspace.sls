# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] == 'dom0' or salt['pillar.get']('qubes:type') == 'template' %}
  {%- set p = "Ctrl Backspace" %}
  {%- from "formatting.jinja" import salt_warning %}
{{p}}Inputrc:
  file.blockreplace:
    - name: /etc/inputrc
    - append_if_not_found: True
    - marker_start: "# Start Ctrl+Backspace deletes word"
    - marker_end: "# End Ctrl+Backspace deletes word"
    - content: |
        # {{ salt_warning }}
        "\C-h": backward-kill-word
        "\e[3;5~": kill-word
{%- endif %}
