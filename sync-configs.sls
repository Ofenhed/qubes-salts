
{%- from "formatting.jinja" import yaml_string, sha256sum %}
{%- set p = 'Sync config files between VMs - ' %}


{%- set storage_salt_dir = 'sync-configs' %}
{%- set storage_dir = '/srv/user_salt/' + storage_salt_dir %}

{%- macro storage_path(config_dir, source_vm, base="/srv/user_salt") %}
  {{- base }}/{{ storage_salt_dir }}/{{ sha256sum(source_vm + ":" + config_dir) }}.tar.gz
{%- endmacro %}

{%- set configs = salt['pillar.get']('sync-configs', {}) %}

{%- if grains['id'] == 'dom0' %}
{%- set state_directory_task = p + "State directory" %}

{{ yaml_string(state_directory_task) }}:
  file.directory:
    - name: {{ yaml_string(storage_dir) }}
    - user: root
    - group: root
    - dir_mode: 640

  {%- for target,source_vm in configs | items %}
{{ yaml_string(p + "Fetch config " + target) }}:
  cmd.run:
    - name: qvm-run --pass-io "$source_vm" -- /bin/bash -c 'cd /home/user && tar cf - "$1" | gzip -c' -- "$config_dir" > "$storage_path"
    - require:
      - file: {{ yaml_string(state_directory_task) }}
    - env:
      - source_vm: {{ yaml_string(source_vm) }}
      - config_dir: {{ yaml_string(target) }}
      - storage_path: {{ yaml_string(storage_path(target, source_vm)) }}
  {%- endfor %}
{%- else %}
  {%- for target,source_vm in configs | items %}
{{ yaml_string(p + "Unpack config " + target) }}:
  archive.extracted:
    - name: /home/user/
    - user: user
    - group: user
    - source: {{ yaml_string(storage_path(target, source_vm, 'salt:/')) }}
    - keep_source: False
    - options: o
    - overwrite: True
  {%- endfor %}
{%- endif %}
