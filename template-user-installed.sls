# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- set install_and_run_path = "/usr/bin/install-and-exec" %}
{%- set install_and_run_fifo_path = "/run/install-and-exec" %}
{%- set install_and_run_env_path = "/rw/config/auto-install.env" %}
{%- set install_and_run_service_name = "install-cached-package@.service" %}
{%- set install_and_run_socket_name = "install-cached-package.socket" %}
{%- set install_and_run_env_prefix = "INSTALL_AND_EXEC_PACKAGE_FOR_" %}
{%- set install_and_run_env_repo_prefix = "INSTALL_AND_EXEC_REPO_FOR_" %}

{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}
  {% from "formatting.jinja" import yaml_string, unique_lines, salt_warning, systemd_shell, bash_argument, escape_bash, format_exec_env_script %}
  {%- set p = "Template user installed - " %}
  {%- set upgrade_all = 'Upgrade all installed packages' %}
  {%- set autoremove = 'Remove unused packages' %}
  {%- set keep_cache_for_non_template = 'Keep dnf cache for non template VMs' %}
  {%- set enable_non_template_cache_service = 'Enable dnf caching service' %}
  {%- set start_time_file = '/run/template-user-installed-start-time' %}
  {%- set activate_cached_file_usage_tracking = 'Activate cached file usage tracking' %}
  {%- set remove_unused_cached_files = 'Remove unused cache files' %}
  {%- set installed = 'Install user wanted packages' %}
  {%- set purged = 'Purging user unwanted packages' %}
  {%- set downloaded = 'Download user sometimes wanted packages' %}
  {%- set maybe_neovim = 'Neovim unless installed locally' %}
  {%- set symlink_opt_neovim = 'Install global nvim symlink to /opt/nvim' %}
  {%- set symlink_vim_to_neovim = 'Install global nvim symlink from vim' %}
  {%- set uninstall_vim = 'Uninstall vim if neovim is installed' %}

  {#- {%- set dnf_workaround = grains['os'] == 'Fedora' and grains['osrelease'] == '41' %} #}
  {%- set target = namespace(dnf_workaround = grains['os'] == 'Fedora' and grains['osrelease'] == '41'
                            ,dnf = grains['os_family'] == 'RedHat'
                            ,apt = grains['os_family'] == 'Debian'
                            ,fedora = grains['os'] == 'Fedora'
                            ,debian = grains['os'] == 'Debian'
                            ,version = grains['osrelease']
                            ,installed = salt['pillar.get']('template-user-installed:installed', [])
                            ,downloaded = salt['pillar.get']('template-user-installed:downloaded', [])
                            ,purged = salt['pillar.get']('template-user-installed:purged', [])
                            ) %}

  {%- if target.dnf %}
{{p}}{{ keep_cache_for_non_template }}:
  cmd.run:
    - name: {% call yaml_string() -%}
        gawk -i inplace '/^\[.*\]$/ {p=($0=="[main]")}; { if (!p || (p && !(/keepcache/))) print $0 ; if ($0=="[main]") print "keepcache = True" }' /etc/dnf/dnf.conf
      {%- endcall %}
    - unless: grep '^keepcache = True$' /etc/dnf/dnf.conf

  {%- endif %}

{{p}}{{ upgrade_all }}:
  {%- if target.dnf_workaround %}
  cmd.run:
    - name: dnf upgrade -y
    - unless: dnf check-update
  {%- else %}
  pkg.uptodate:
    - refresh: True
  {%- endif %}
  {%- set upgrade_all_type = 'cmd' if target.dnf_workaround else 'pkg' %}

  {%- if target.apt %}
{{p}}{{ autoremove }}:
  module.run:
    - pkg.autoremove: {}
  {%- endif %}

Notify qubes about installed updates:
  cmd.run:
    - name: /usr/lib/qubes/upgrades-status-notify
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
  {%- if target.apt %}
      - module: {{p}}{{ autoremove }}
  {%- endif %}

{{p}}{{ purged }}:
  pkg.purged:
    - require_in:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
    - pkgs:
  {%- call unique_lines() %}
    {%- for purge in target.purged %}
      {%- if purge is string %}
      - {{ yaml_string(purge) }}
      {%- endif %}
    {%- endfor %}
  {%- endcall %}

{{p}}{{ installed }}:
  pkg.installed:
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
    - pkgs:
  {%- call unique_lines() %}
    {%- for install in target.installed %}
      {%- if install is string and install != 'neovim' %}
      - {{ yaml_string(install) }}
      {%- endif %}
    {%- endfor %}
  {%- endcall %}

  {%- if 'neovim' in target.installed %}

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
    {%- if target.fedora %}
      - vim-enhanced
    {%- elif target.debian %}
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
  {%- endif %}

  {%- set packages_for_download = [] %}
  {%- for download in target.downloaded %}
    {%- if download is string %}
      {%- do packages_for_download.append(download) %}
    {%- endif %}
  {%- endfor %}
  {%- set packages_for_download = packages_for_download | unique %}

  {%- set cache_info = namespace(base_dir='/var/cache/libdnf5', touch_match='*/packages/*') if target.dnf else (namespace(base_dir='/var/cache/apt/archives', touch_match='*.deb') if target.apt and False else none) %}
  {%- set cache_tracking = cache_info is not none %}

  {%- if cache_tracking %}
{{p}}{{ activate_cached_file_usage_tracking }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_ACTIVATE_CACHE_FILE_USAGE_TRACKING')) }}
    - env:
      - DNF_ACTIVATE_CACHE_FILE_USAGE_TRACKING: {% call yaml_string() -%}
          set -e
          shopt -s nullglob
          mount -B -o atime {{ cache_info.base_dir }}/{,}
          touch {{ cache_info.base_dir }}/{{ cache_info.touch_match }} {{ start_time_file }}
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
      - AWK_FIND_UNTOUCHED_FILES: {% call yaml_string() %}
            {
              last_written=$1;
              last_access=$2;
              file_birth=$3;
              last_any=last_access;
              if (last_written > last_any) {
                  last_any=last_written;
              };
              if (file_birth > last_any) {
                  last_any=file_birth;
              };
              if (!(last_any > start_time)) {
                  printf "%s\0", substr($0, index($0, $4))
              }
            }
        {%- endcall %}
      - DNF_REMOVE_UNUSED_FILES: {% call yaml_string() %}
          set -e
          shopt -s nullglob
          start_time=$(stat --format='%X' {{ start_time_file }})
          cd {{ cache_info.base_dir }}
          stat --format='%X %Y %W %n' ./{{ cache_info.touch_match }} | awk -v "start_time=$start_time" "$AWK_FIND_UNTOUCHED_FILES" | xargs -0 -- rm -fv --
          cd /
          umount {{ cache_info.base_dir }}
      {%- endcall %}
    - require:
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}

{{p}}Trim filesystem:
  cmd.run:
    - name: fstrim /
    - require:
      - cmd: {{p}}{{ remove_unused_cached_files }}
  {%- endif %}



{{p}}{{ downloaded }}:
  {%- if not target.dnf_workaround %}
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
  {%- if cache_tracking %}
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}
    - require_in:
      - cmd: {{p}}{{ remove_unused_cached_files }}
  {%- endif %}

  {%- for download in target.downloaded %}
    {%- if download is not string and (download['name'] is defined) and (download['repo'] is defined) and (download['repo']['name'] is defined) %}
      {%- set salt_task_name_string = yaml_string(p + "Download " + download['name'] + " from external repo " + download['repo']['name']) %}
{{ salt_task_name_string }}:
  pkgrepo.managed:
      {%- set repo_options=namespace(enabled=false) %}
      {%- for key, value in download['repo']|items %}
        {%- if key == 'enabled' %}
          {%- set repo_options.enabled = value %}
        {%- else %}
    - {{ yaml_string(key) }}: {{ yaml_string(value) }}
        {%- endif %}
      {%- endfor %}
    - enabled: {{ repo_options.enabled }}
      {%- if not target.dnf_workaround %}
  pkg.downloaded:
    - name: {{ yaml_string(download['name']) }}
    - enablerepo: {{ yaml_string(download['repo']['name']) }}
      {%- else %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_INSTALL_COMMAND')) }}
    - env:
      - DNF_INSTALL_COMMAND: dnf install "--downloadonly" "--quiet" "-y" {{ bash_argument("--enablerepo=" + download['repo']['name']) }} {{ bash_argument(download['name']) }}
      {%- endif %}
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
      - pkg: {{p}}{{ installed }}
      - pkgrepo: {{ salt_task_name_string }}
      {%- if cache_tracking %}
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}
    - require_in:
      - cmd: {{p}}{{ remove_unused_cached_files }}
      {%- endif %}
    {%- endif %}
  {%- endfor %}

  {%- if target.dnf or target.apt %}
{{p}}{{ yaml_string(install_and_run_path) }}:
  file.managed:
    - name: {{ yaml_string(install_and_run_path) }}
    - mode: 755
    - user: root
    - group: root
    - replace: true
    - contents: |
        #!/bin/bash
        # {{ salt_warning }}
        set -e
        target_path="/usr${BASH_SOURCE#\/usr\/local}"
        if [ -f $target_path ]; then
            exec "$target_path" "$@"
        fi
        exec {target}> >(socat - UNIX-CONNECT:{{ install_and_run_fifo_path }} 2>/dev/null)
        socat_pid=$!
        install_target="$(basename -- "${BASH_SOURCE[0]}")"
        cat <<<"${install_target}" >&${target}
        cat <<<"" >&${target}
        wait "$socat_pid"
        exec "$target_path" "$@"

{{p}}{{ install_and_run_socket_name }}:
  file.managed:
    - name: {{ yaml_string("/usr/lib/systemd/system/" + install_and_run_socket_name) }}
    - mode: 444
    - user: root
    - group: root
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Listen for install requests on {{ install_and_run_fifo_path }}
        ConditionFileNotEmpty={{ install_and_run_env_path }}
        [Socket]
        ListenStream={{ install_and_run_fifo_path }}
        Accept=yes
        RemoveOnStop=yes
        SocketUser=user
        SocketGroup=user
        SocketMode=0600

        [Install]
        WantedBy=multi-user.target

{{p}}Enable {{ install_and_run_socket_name }}:
  service.enabled:
    - name: {{ install_and_run_socket_name }}
    - require:
      - file: {{p}}{{ install_and_run_socket_name }}

{{p}}{{ yaml_string(install_and_run_service_name) }}:
  file.managed:
    - name: {{ yaml_string("/usr/lib/systemd/system/" + install_and_run_service_name) }}
    - mode: 444
    - user: root
    - group: root
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Install cached package
        CollectMode=inactive-or-failed

        [Service]
        Type=oneshot
        RemainAfterExit=no
        EnvironmentFile={{ install_and_run_env_path }}
        ExecStart={%- call systemd_shell() -%}
          if [[ "$(stat --format='%%a %%U %%G' "{{ install_and_run_env_path }}")" != "644 root root" ]]; then
            echo "Invalid permissions for {{ install_and_run_env_path }}"
            exit 1
          fi
          . {{ install_and_run_env_path }}
          exec {caller_fd}< <(socat FD:3 -)
          new_packages=()
          {%- if target.apt %}
          deb_files=()
          {%- endif %}
          enabled_repos=()
          while read -r request_line <&$${caller_fd}; do
            if [[ -z $request_line ]]; then
              echo "Got empty line"
              break
            fi
            binary_name="{{ install_and_run_env_prefix }}$${request_line//-/_}[@]"
            repo_name="{{ install_and_run_env_repo_prefix }}$${request_line//-/_}[@]"
            echo "Read $${binary_name} (value: $${!binary_name:-UNDEFINED})"
            if [[ -z "$${!binary_name:-}" ]]; then
              echo "Invalid binary name $request_line" >&2
              exec $${caller_fd}<&-
              exit 1
            fi
          {%- if target.dnf %}
            if [[ ! -z "$${!repo_name:-}" ]]; then
              enabled_repos+=( --enablerepo="$${!repo_name}" )
            fi
          {%- endif %}
          {%- if target.apt %}
            if [ -f "$${!binary_name}" ]; then
              deb_files+=( "$${!binary_name}" )
            else
              new_packages+=( "$${!binary_name}" )
            fi
          {%- else %}
            new_packages+=( "$${!binary_name}" )
          {%- endif %}
          done
          lock_file=""
          {%- set activate_lock %}
            if [[ "$lock_file" == "" ]]; then
              cat <<<"Activating lock"
              exec {lock_file}<{{ bash_argument(install_and_run_env_path, before='', after='') }}
              flock -x "$lock_file"
            fi
          {%- endset %}
          {%- if target.apt %}
          if [[ "{{- "$${#deb_files[@]}" -}}" -gt 0 ]]; then
            {{- activate_lock }}
            cat <<<"Installing deb files $(printf '"%%s" ' "$${deb_files[@]}")"
            dpkg -i "$${deb_files[@]}"
            apt-get install -f --no-download --yes
          fi
          {%- endif %}
          if [ {{'$${#new_packages[@]}'}} -gt 0 ]; then
            {{- activate_lock }}
            cat <<<"Installing $(printf '"%%s" ' "$${new_packages[@]}")"
          {%- if target.dnf %}
                dnf install -Cy "$${enabled_repos[@]}"
          {%- elif target.apt %}
                apt-get install --no-download --yes
          {%- endif %} "$${new_packages[@]}"
          fi
          if [[ "$lock_file" != "" ]]; then
            exec {lock_file}<&-
          fi
          exec {caller_fd}<&-
        {%- endcall %}
  {%- endif %}
{%- endif %}
