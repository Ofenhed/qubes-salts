# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}
{% from "formatting.jinja" import yaml_string, unique_lines %}
{%- set upgrade_all = 'Upgrade all installed packages' %}
{%- set installed = 'Install user wanted packages' %}
{%- set downloaded = 'Download user sometimes wanted packages' %}
{%- set maybe_neovim = 'Neovim unless installed locally' %}
{%- set symlink_opt_neovim = 'Install global nvim symlink to /opt/nvim' %}
{%- set symlink_vim_to_neovim = 'Install global nvim symlink from vim' %}
{%- set uninstall_vim = 'Uninstall vim if neovim is installed' %}

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
  {%- call unique_lines() %}
    {%- for install in salt['pillar.get']('template-user-installed:installed', []) %}
      {%- if install is string %}
      - {{ yaml_string(install) }}
      {%- elif install['match_grain'] is defined and install['values'] is defined %}
        {%- if install['match'] is defined and grains[install['match_grain']] == install['match'] %}
          {%- for install in install['values'] %}
      - {{ yaml_string(install) }}
          {%- endfor %}
        {%- endif %}
      {%- endif %}
    {%- endfor %}
  {%- endcall %}

{{ symlink_opt_neovim }}:
  file.symlink:
    - target: /opt/nvim/bin/nvim
    - name: /usr/bin/nvim
    - onlyif:
      - fun: file.directory_exists
        path: /opt/nvim/

{{ maybe_neovim }}:
  pkg.installed:
    - require:
      - pkg: {{ upgrade_all }}
    - name: neovim
    - unless:
      - fun: file.directory_exists
        path: /opt/nvim/

{{ uninstall_vim }}:
  pkg.purged:
    - pkgs:
  {%- if grains['os'] == 'Fedora' %}
      - vim-enhanced
  {%- elif grains['os'] == 'Debian' %}
      - vim-tiny
  {%- endif %}
    - require_any:
      - pkg: {{ maybe_neovim }}
      - file: {{ symlink_opt_neovim }}

{{ symlink_vim_to_neovim }}:
  file.symlink:
    - target: nvim
    - name: /usr/bin/vim
    - require:
      - pkg: {{ uninstall_vim }}

{{ downloaded }}:
  {%- if not (grains['os'] == 'Fedora' and grains['osrelease'] == '41') %}
  pkg.downloaded:
    - require:
      - pkg: {{ installed }}
    - failhard: False
    - order: last
    - pkgs:
    {%- call unique_lines() %}
      {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
        {%- if download is string %}
      - {{ yaml_string(download) }}
        {%- elif download['match_grain'] is defined and download['values'] is defined %}
          {%- if download['match'] is defined and grains[download['match_grain']] == download['match'] %}
            {%- for download in download['values'] %}
      - {{ yaml_string(download) }}
            {%- endfor %}
          {%- endif %}
        {%- endif %}
      {%- endfor %}
    {%- endcall %}
  {%- else %}
  module.run:
    - cmd.run:
      - cmd:
        - dnf5
        - install
        - "--downloadonly"
        - "-y"
    {%- call unique_lines() %}
      {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
        {%- if download is string %}
        - {{ yaml_string(download) }}
        {%- elif download['match_grain'] is defined and download['values'] is defined %}
          {%- if download['match'] is defined and grains[download['match_grain']] == download['match'] %}
            {%- for download in download['values'] %}
        - {{ yaml_string(download) }}
            {%- endfor %}
          {%- endif %}
        {%- endif %}
      {%- endfor %}
    {%- endcall %}
  {%- endif %}


  {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
    {%- if download is not string and download['name'] is defined and download['repo'] is defined and download['repo']['name'] is defined %}
{{ yaml_string("Download " + download['name'] + " from external repo " + download['repo']['name']) }}:
  pkgrepo.managed:
    - enabled: false
      {%- for key, value in download['repo']|items %}
    - {{ yaml_string(key) }}: {{ yaml_string(value) }}
      {%- endfor %}
      {%- if not (grains['os'] == 'Fedora' and grains['osrelease'] == '41') %}
  pkg.downloaded:
    - require:
      - pkg: {{ installed }}
    - name: {{ yaml_string(download['name']) }}
    - enablerepo: {{ yaml_string(download['repo']['name']) }}
      {%- else %}
  module.run:
    - cmd.run:
      - cmd:
        - dnf5
        - install
        - "--downloadonly"
        - "-y"
        - {{ yaml_string("--enablerepo=" + download['repo']['name']) }}
        - {{ yaml_string(download['name']) }}
      {%- endif %}
    {%- endif %}
  {%- endfor %}
{%- endif %}
