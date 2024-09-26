# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% if grains['id'] == 'dom0' %}
  {% from "formatting.jinja" import yaml_escape, yaml_string %}
  {% from "dependents.jinja" import add_dependencies, tasks, task_trigger_filename, task_command_filename, trigger_salt_name %}

  {% call add_dependencies('grub') %}
    - file: /etc/default/grub
  {% endcall %}

  {%- for (name, task) in tasks.items() %}
    {%- set trigger_name = trigger_salt_name(name) %}
    {%- set trigger_command_name = trigger_salt_name(name) + " command" %}
{{ yaml_string(trigger_command_name) }}:
  file.managed:
    - name: {{ yaml_string(task_command_filename(name)) }}
    - replace: True
    - mode: 666
    - user: root
    - group: root
    - makedirs: true
    - dir_mode: 750
    - contents: {{ yaml_string(task) }}

{{ yaml_string(trigger_name) }}:
  cmd.run:
    - name: {{ yaml_string(task) }}
    - order: last
    - onchanges:
      - file: {{ task_trigger_filename(name) }}
      - file: {{ yaml_string(trigger_command_name) }}
  {%- endfor %}
{% endif %}