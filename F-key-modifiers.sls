# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] == 'dom0' %}
  {%- set p = "F key modifiers - " %}
  {%- from "formatting.jinja" import salt_warning, yaml_string %}
{{p}}Replace keycodes:
  file.replace:
    - name: /usr/share/X11/xkb/symbols/inet
    - flags: 0
    - pattern: |
        (//)?([ \t]*key\s+<FK(13|14)>[ \t]*\{[ \t]*\[)([ \t]*[^\s]+)?([ \t]*][ \t]*};)
    - repl: |
       \2 F\3 \5

  {%- for mod, f_key in {'Mod2': '13', 'Mod3': '14'}.items() %}
  {%- set task_name = p + "Add " + mod + " modifier" %}
  {%- set not_found_prepend = "// Could not modify F" + f_key + " key" %}
{{ task_name }}:
  file.replace:
    - name: /usr/share/X11/xkb/symbols/pc
    - flags: 0
    - pattern: |
        ([ \t]*modifier_map\s+{{ mod | regex_escape }}\s*\{)[^}]*(}\s*;)
    - repl: |
        \1 F{{f_key}} \2
    - ignore_if_missing: True
    - prepend_if_not_found: True
    - not_found_content: {{ yaml_string(not_found_prepend) }}

{{p}}Append modifier F{{f_key}}:
  file.replace:
    - name: /usr/share/X11/xkb/symbols/pc
    - flags:
        - MULTILINE
    - pattern: |
        {{ not_found_prepend }}\n((\n|.)*xkb_symbols\s+"pc105"\s*\{)
    - require:
      - file: {{ task_name }}
    - ignore_if_missing: True
    - repl: |
        \1\n  modifier_map {{ mod }} { F{{f_key}} };
  {%- endfor %}


{%- endif %}
