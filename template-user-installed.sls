# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}
  {% from "formatting.jinja" import yaml_string, unique_lines, salt_warning, systemd_shell, bash_argument, escape_bash, format_exec_env_script %}
  {%- set p = "Template user installed - " %}
  {%- set upgrade_all = 'Upgrade all installed packages' %}
  {%- set keep_cache_for_non_template = 'Keep dnf cache for non template VMs' %}
  {%- set enable_non_template_cache_service = 'Enable dnf caching service' %}
  {%- set keep_cache_for_non_template_service = 'keep-dnf-cache.service' %}
  {%- set start_time_file = '/run/template-user-installed-start-time' %}
  {%- set activate_cached_file_usage_tracking = 'Activate cached file usage tracking' %}
  {%- set remove_unused_cached_files = 'Remove unused cache files' %}
  {%- set installed = 'Install user wanted packages' %}
  {%- set downloaded = 'Download user sometimes wanted packages' %}
  {%- set maybe_neovim = 'Neovim unless installed locally' %}
  {%- set symlink_opt_neovim = 'Install global nvim symlink to /opt/nvim' %}
  {%- set symlink_vim_to_neovim = 'Install global nvim symlink from vim' %}
  {%- set uninstall_vim = 'Uninstall vim if neovim is installed' %}
  {%- set dnf_workaround = grains['os'] == 'Fedora' and grains['osrelease'] == '41' %}

  {% if grains['os_family'] == 'RedHat' %}
/usr/lib/systemd/system/{{ keep_cache_for_non_template_service }}:
  file.absent: []

{{p}}{{ keep_cache_for_non_template }}:
  cmd.run:
    - name: {% call yaml_string() -%}
        gawk -i inplace '/^\[.*\]$/ {p=($0=="[main]")}; { if (!p || (p && !(/keepcache/))) print $0 ; if ($0=="[main]") print "keepcache = True" }' /etc/dnf/dnf.conf
      {%- endcall %}
    - unless: grep '^keepcache = True$' /etc/dnf/dnf.conf

  {%- endif %}

{{p}}{{ upgrade_all }}:
  {%- if dnf_workaround %}
  cmd.run:
    - name: dnf upgrade -y
    - unless: dnf check-update
  {%- else %}
  pkg.uptodate:
    - refresh: True
  {%- endif %}
  {%- set upgrade_all_type = 'cmd' if dnf_workaround else 'pkg' %}
{#
{%- if grains['os'] == 'Debian' %}
  module.run:
    - name: aptpkg.autoremove
{%- endif %}
#}


Notify qubes about installed updates:
  cmd.run:
    - name: /usr/lib/qubes/upgrades-status-notify
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}

{{p}}{{ installed }}:
  pkg.installed:
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
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

{{p}}{{ symlink_opt_neovim }}:
  file.symlink:
    - target: /opt/nvim/bin/nvim
    - name: /usr/bin/nvim
    - onlyif:
      - fun: file.directory_exists
        path: /opt/nvim/

{{p}}{{ maybe_neovim }}:
  pkg.installed:
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
    - name: neovim
    - unless:
      - fun: file.directory_exists
        path: /opt/nvim/

{{p}}{{ uninstall_vim }}:
  pkg.purged:
    - pkgs:
  {%- if grains['os'] == 'Fedora' %}
      - vim-enhanced
  {%- elif grains['os'] == 'Debian' %}
      - vim-tiny
  {%- endif %}
    - require_any:
      - pkg: {{p}}{{ maybe_neovim }}
      - file: {{p}}{{ symlink_opt_neovim }}

{{p}}{{ symlink_vim_to_neovim }}:
  file.symlink:
    - target: nvim
    - name: /usr/bin/vim
    - require:
      - pkg: {{p}}{{ uninstall_vim }}

  {%- set packages_for_download = [] %}
  {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
    {%- if download is string %}
      {%- do packages_for_download.append(download) %}
    {%- elif download['match_grain'] is defined and download['values'] is defined %}
      {%- if download['match'] is defined and grains[download['match_grain']] == download['match'] %}
        {%- for download in download['values'] %}
          {%- do packages_for_download.append(download) %}
        {%- endfor %}
      {%- endif %}
    {%- endif %}
  {%- endfor %}
  {%- set packages_for_download = packages_for_download | unique %}

{{p}}{{ activate_cached_file_usage_tracking }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_ACTIVATE_CACHE_FILE_USAGE_TRACKING')) }}
    - env:
      - DNF_ACTIVATE_CACHE_FILE_USAGE_TRACKING: {% call yaml_string() -%}
          set -e
          mount -B -o atime /var/cache/libdnf5/{,}
          touch /var/cache/libdnf5/*/packages/* {{ start_time_file }}
          start_time=$(stat --format='%X' {{ start_time_file }})
          while [[ $(date +%s) -eq $start_time ]]; do
              sleep 0.05
          done
        {%- endcall %}
    - require:
      - pkg: {{p}}{{ installed }}

{{p}}{{ remove_unused_cached_files }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_REMOVE_UNUSED_FILES')) }}
    - env:
      - DNF_REMOVE_UNUSED_FILES: {% call yaml_string() -%}
      start_time=$(stat --format='%X' {{ start_time_file }})
      cd /var/cache/libdnf5/
      stat --format='%X %Y %n' ./*/packages/* | awk -v "start_time=$start_time" {% call escape_bash() -%}
        {
          last_written=$1;
          last_access=$2;
          last_any=last_access;
          if (last_written > last_any) {
              last_any=last_written;
          };
          if (!(last_any > start_time)) {
              printf "%s\0", substr($0, index($0, $3))
          }
        }
      {%- endcall %} | xargs -0 -- rm -fv --
      cd /
      umount /var/cache/libdnf5
      {%- endcall %}
    - require:
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}


{{p}}{{ downloaded }}:
  {%- if not dnf_workaround %}
  pkg.downloaded:
    - failhard: False
    - order: last
    - pkgs:
    {%- for package in packages_for_download %}
      - {{ yaml_string(package) }}
    {%- endfor %}
  {%- else %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_INSTALL_COMMAND')) }}
    - env:
      - DNF_INSTALL_COMMAND: dnf install --downloadonly --quiet -y
    {%- for package in packages_for_download %}
      {{- bash_argument(package) }}
    {%- endfor %}
  {%- endif %}
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
      - pkg: {{p}}{{ installed }}
  {%- if grains['os_family'] == 'RedHat' %}
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}
    - require_in:
      - cmd: {{p}}{{ remove_unused_cached_files }}
  {%- endif %}

  {%- for download in salt['pillar.get']('template-user-installed:downloaded', []) %}
    {%- if download is not string and download['name'] is defined and download['repo'] is defined and download['repo']['name'] is defined %}
{{ yaml_string(p + "Download " + download['name'] + " from external repo " + download['repo']['name']) }}:
  pkgrepo.managed:
    - enabled: false
      {%- for key, value in download['repo']|items %}
    - {{ yaml_string(key) }}: {{ yaml_string(value) }}
      {%- endfor %}
      {%- if not dnf_workaround %}
  pkg.downloaded:
    - name: {{ yaml_string(download['name']) }}
    - enablerepo: {{ yaml_string(download['repo']['name']) }}
      {%- else %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_INSTALL_COMMAND')) }}
    - env:
      - DNF_INSTALL_COMMAND: dnf install "--downloadonly" "--quiet" "-y" {{ bash_argument("--enablerepo=" + download['repo']['name']) }} {{ bash_argument(download['name']) }}
      {%- endif %}
    {%- endif %}
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
      - pkg: {{p}}{{ installed }}
    {%- if grains['os_family'] == 'RedHat' %}
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}
    - require_in:
      - cmd: {{p}}{{ remove_unused_cached_files }}
    {%- endif %}
  {%- endfor %}
{%- endif %}
