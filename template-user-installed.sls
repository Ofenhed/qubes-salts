# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}
{% from "formatting.jinja" import yaml_string %}
{%- set upgrade_all = 'Upgrade all installed packages' %}
{%- set installed = 'Install user wanted packages' %}
{%- set downloaded = 'Download user sometimes wanted packages' %}

{{ upgrade_all }}:
  pkg.uptodate:
    - refresh: True
{%- if grains['os'] == 'Debian' %}
  module.run:
    - name: aptpkg.autoremove
{%- endif %}


Notify qubes about installed updates:
  cmd.run:
    - name: /usr/lib/qubes/upgrades-status-notify
    - onchanges:
      - pkg: {{ upgrade_all }}

{{ installed }}:
  pkg.installed:
    - require:
      - pkg: {{ upgrade_all }}
    - pkgs:
  {%- for install in salt['pillar.get']('template-user-installed:installed', []) %}
      - {{ yaml_string(install) }}
  {%- endfor %}

{{ downloaded }}:
  pkg.downloaded:
    - require:
      - pkg: {{ installed }}
    - failhard: False
    - order: last
    - pkgs:
  {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
    {%- if download is string %}
      - {{ yaml_string(download) }}
    {%- endif %}
  {%- endfor %}

  {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
    {%- if download is not string and download['name'] is defined and download['repo'] is defined and download['repo']['name'] is defined %}
{{ yaml_string("Download " + download['name'] + " from external repo " + download['repo']['name']) }}:
  pkgrepo.managed:
    - enabled: false
      {%- for key, value in download['repo']|items %}
    - {{ yaml_string(key) }}: {{ yaml_string(value) }}
      {%- endfor %}
  pkg.downloaded:
    - require:
      - pkg: {{ installed }}
    - name: {{ yaml_string(download['name']) }}
    - enablerepo: {{ yaml_string(download['repo']['name']) }}
    {%- endif %}
  {%- endfor %}
{%- endif %}
