# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- set install_and_run_path = "/usr/bin/install-and-exec" %}
{%- set install_cached_path = "/usr/bin/install-cached-package" %}
{%- set apt_with_repo_suffix = "-with-repo" %}
{%- macro apt_with_repo_name(subcommand = none) -%}
  apt
  {%- if subcommand is not none -%}
    -{{ subcommand }}
  {%- endif -%}
  {{ apt_with_repo_suffix }}
{%- endmacro %}
{%- macro apt_with_repo_path(subcommand = none) -%}
  /usr/bin/{{- apt_with_repo_name(subcommand = subcommand) }}
{%- endmacro %}
{%- macro apt_with_repo_state(subcommand = none) %}
  {{-p}}{{ apt_with_repo_name(subcommand = subcommand) }} script
{%- endmacro %}
{%- set install_cached_package_socket_path = "/run/install-cached-package" %}
{%- set install_and_run_env_path = "/rw/config/auto-install.env" %}
{%- set install_cached_package_base_name = 'install-cached-package' %}
{%- macro install_cached_package_service_name(name = '') -%}
  {{ install_cached_package_base_name }}@{{ name }}.service
{%- endmacro %}
{%- set install_cached_package_socket_name = install_cached_package_base_name + ".socket" %}
{%- set install_cached_package_socket_group = "auto-install" %}
{%- set install_and_run_env_prefix = "INSTALL_AND_EXEC_PACKAGE_FOR_" %}
{%- set install_and_run_env_repo_prefix = "INSTALL_AND_EXEC_REPO_FOR_" %}

{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}
  {% from "formatting.jinja" import yaml_string, unique_lines, salt_warning, systemd_shell, bash_argument, escape_bash, format_exec_env_script, trim_common_whitespace %}
  {%- set p = "Template user installed - " %}
  {%- set upgrade_all = 'Upgrade all installed packages' %}
  {%- set upgrade_arch_keyring = 'Upgrade Arch linux keyrings' %}
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
  {%- set import_gpgs = 'Import GPG keys' %}

  {%- set target = namespace(dnf_workaround = grains['os'] == 'Fedora'
                            ,apt = grains['os_family'] == 'Debian'
                            ,dnf = grains['os_family'] == 'RedHat'
                            ,pacman = grains['os_family'] == 'Arch'
                            ,arch = grains['os'] == 'Arch'
                            ,debian = grains['os'] == 'Debian'
                            ,fedora = grains['os'] == 'Fedora'
                            ,version = grains['osrelease']
                            ,installed = salt['pillar.get']('template-user-installed:installed', [])
                            ,downloaded = salt['pillar.get']('template-user-installed:downloaded', [])
                            ,purged = salt['pillar.get']('template-user-installed:purged', [])
                            ,pre_install_command = None
                            ,post_install_command = None
                            ) %}
  {%- set post_install = namespace(import_gpgs = {}) %}
  {%- macro gpg_filename(name) %}
    {%- if target.dnf -%}
      /etc/pki/rpm-gpg/RPM-GPG-KEY-{{ name }}.gpg
    {%- elif target.apt -%}
      /usr/share/keyrings/apt-keyring-{{ name }}.gpg
    {%- endif %}
  {%- endmacro %}
  {%- macro gpg_url_from_path(path) %}
    {%- if target.dnf -%}
      file://{{ path }}
    {%- else %}
      {{- path }}
    {%- endif %}
  {%- endmacro %}

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

  {%- if target.pacman %}
{{p}}{{ upgrade_arch_keyring }}:
  pkg.installed:
    - name: archlinux-keyring
    - refresh: true
    - require_in:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
  {%- endif %}

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
  {%- if target.pacman and false %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('PURGE_PACKAGES')) }}
    - env:
      - PURGE_PACKAGES: {% call yaml_string() -%}
          purge_candidates=($PACKAGES_TO_PURGE)
          pacman -Rns -- "${purge_candidates}"
    {%- endcall %}
      - PACKAGES_TO_PURGE: {% call yaml_string() -%}
      {%- call unique_lines() %}
        {%- for purge in target.purged %}
          {%- if purge is string %}
            {{ purge }}
          {%- endif %}
        {%- endfor %}
      {%- endcall %}
    {%- endcall %}
  {%- else %}
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
  {%- endif %}

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
    {%- elif target.arch %}
      - vim
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
  {%- if not (target.dnf_workaround or target.pacman) %}
  pkg.downloaded:
    - failhard: False
    - order: last
    - pkgs:
    {%- for package in packages_for_download %}
      - {{ yaml_string(package) }}
    {%- endfor %}
  {%- else %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_INSTALL_COMMAND') if target.dnf else (format_exec_env_script('PACMAN_INSTALL_COMMAND') if target.pacman else "false")) }}
    - env:
      - DNF_INSTALL_COMMAND: {% call yaml_string() -%}
          packages_to_download=($PACKAGES_TO_DOWNLOAD);
          dnf install --downloadonly --quiet -y "${packages_to_download[@]}"
    {%- endcall %}
      - PACMAN_INSTALL_COMMAND: {% call yaml_string() -%}
          packages_to_download=($PACKAGES_TO_DOWNLOAD);
          /run/qubes/bin/pacman -Sywv --noconfirm --noprogressbar -- "${packages_to_download[@]}"
    {%- endcall %}
      - PACKAGES_TO_DOWNLOAD: {% call yaml_string() -%}
      {%- for package in packages_for_download %}
        {{ package }}
      {%- endfor %}
    {%- endcall %}
  {%- endif %}
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
      - pkg: {{p}}{{ installed }}
  {%- if cache_tracking %}
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}
    - require_in:
      - cmd: {{p}}{{ remove_unused_cached_files }}
  {%- endif %}

  {#
  {%- macro apt_repo(task_name, filename, repo_type, url, ) %}
    {%- if target.apt %}
{{ yaml_string(task_name) }}:
  file.managed:
    - name: {{ yaml_string(options['name']) }}
  #}

  {%- macro maybe_with_repo(download, do_install = False) %}
    {%- set action = "Install" if do_install else "Download" %}
    {%- if download is not string and (download['name'] is defined) and (download['repo'] is defined) and (download['repo']['name'] is defined) %}
      {%- set salt_task_name_string = yaml_string(p + action + " " + download['name'] + " from external repo " + download['repo']['name']) %}
{{ salt_task_name_string }}:
      {%- set repo_options=namespace(enabled=false, gpg_key=None, gpg_key_url=None, import_gpg=False, raw_file = target.apt, options = {}, raw_options = {}) %}
      {%- for key, value in download['repo']|items %}
        {%- if key|lower == 'enabled' %}
          {%- set repo_options.enabled = value %}
        {%- elif key|lower == 'import_gpg' -%}
          {%- set repo_options.gpg_key = gpg_filename(download['repo']['name']) %}
          {%- set repo_options.gpg_key_url = gpg_url_from_path(repo_options.gpg_key) %}
          {%- do post_install.import_gpgs.update({repo_options.gpg_key: value}) %}
          {%- set repo_options.import_gpg = True %}
        {%- elif key|lower == 'gpgkey' %}
          {%- if repo_options.gpg_key == None %}
            {%- set repo_options.gpg_key = value %}
          {%- endif %}
        {%- else %}
          {%- do repo_options.options.update({key|lower: value}) %}
          {%- do repo_options.raw_options.update({key: value}) %}
        {%- endif %}
      {%- endfor %}
      {%- if repo_options.raw_file %}
  file.managed:
    - name: {{ yaml_string(("/etc/apt/sources.list.d/" + repo_options.options['name'] + ".sources") if repo_options.options['name'] is defined else repo_options.options['file']) }}
    - mode: 644
    - user: root
    - group: root
    - replace: True
    - backup: False
    - contents: {% call yaml_string() %}{%- call trim_common_whitespace() -%}
        ## {{ salt_warning }}
        {%- for key, value in repo_options.raw_options|items %}
          {%- if key|lower not in ['name'] %}
        {{ key }}: {{ value }}
          {%- endif %}
        {%- endfor %}
        Enabled: {{ "yes" if repo_options.enabled else "no" }}
        {%- if repo_options.gpg_key %}
        Signed-By: {{ repo_options.gpg_key_url }}
        {%- endif %}
        {%- endcall %}{%- endcall %}
      {%- else %}
  pkgrepo.managed:
        {%- for key, value in repo_options.raw_options|items %}
    - {{ yaml_string(key)}}: {{ yaml_string(value) }}
        {%- endfor %}
        {%- if repo_options.gpg_key %}
    - gpgkey: {{ yaml_string(repo_options.gpg_key_url if repo_options.gpg_key_url else repo_options.gpg_key) }}
        {%- endif %}
    - enabled: {{ repo_options.enabled }}
      {%- endif %}
    {%- if repo_options.import_gpg %}
    - require:
      - cmd: {{ yaml_string(p + import_gpgs + ': ' + repo_options.gpg_key) }}
    {%- endif %}
      {%- if not target.dnf_workaround and not target.apt %}
  pkg.
    {%- if do_install -%}
      installed
    {%- else -%}
      downloaded
    {%- endif %}:
    - name: {{ yaml_string(download['name']) }}
    - enablerepo: {{ yaml_string(download['repo']['name']) }}
      {%- elif target.apt %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('APT_INSTALL_COMMAND')) }}
    - env:
      - APT_REPO_NAME: {{ yaml_string(download['repo']['name']) }}
      - APT_PACKAGE_NAME: {{ yaml_string(download['name']) }}
      - APT_INSTALL_COMMAND: {{ apt_with_repo_path("get") }} --enable-repo "$APT_REPO_NAME" update && {{ apt_with_repo_path("get") }} --enable-repo "$APT_REPO_NAME" install -y --download-only "$APT_PACKAGE_NAME"
    - require:
      - file: {{ apt_with_repo_state("get") }}
      {%- elif target.dnf_workaround %}
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('DNF_INSTALL_COMMAND')) }}
    - env:
      - DNF_INSTALL_PACKAGE: {{ yaml_string(download['name']) }}
      - DNF_INSTALL_COMMAND: dnf install {%- if not do_install %} "--downloadonly" {%- endif %} "--quiet" "-y" {{ bash_argument("--enable-repo=" + download['repo']['name']) }} "$DNF_INSTALL_PACKAGE"
      {%- endif %}
    - require:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
      - pkg: {{p}}{{ installed }}
      - {{ "file" if repo_options.raw_file else "pkgrepo" }}: {{ salt_task_name_string }}
      {%- if cache_tracking %}
      - cmd: {{p}}{{ activate_cached_file_usage_tracking }}
    - require_in:
      - cmd: {{p}}{{ remove_unused_cached_files }}
      {%- endif %}
    {%- endif %}
    {{- '\n' }}
  {%- endmacro %}
  {%- for download in target.downloaded %}
    {{- maybe_with_repo(download) }}
  {%- endfor %}
  {%- for download in target.installed %}
    {{- maybe_with_repo(download, do_install=True) }}
  {%- endfor %}

  {%- for key,value in post_install.import_gpgs|items %}
    {%- set import_task_name = p + import_gpgs + ': ' + key %}
{{ yaml_string(import_task_name) }}:
  file.managed:
    - name: {{ yaml_string(key if not target.apt else (key + ".b64")) }}
    - source: {{ yaml_string(value) }}
    - user: root
    - group: root
    - mode: 644
  cmd.run:
    {%- if target.dnf %}
    - name: rpmkeys --import "$GPG_KEY_FILE"
    {%- else %}
    - name: gpg --dearmor <"$GPG_KEY_FILE.b64" >"$GPG_KEY_FILE"
    {%- endif %}
    - env:
      - GPG_KEY_FILE: {{ yaml_string(key) }}
    - onchanges:
      - file: {{ yaml_string(import_task_name) }}
    - require_in:
      - {{ upgrade_all_type }}: {{p}}{{ upgrade_all }}
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
        self_path="${BASH_SOURCE[-1]}"
        target_path="/usr${self_path#\/usr\/local}"
        if [ -f $target_path ]; then
            exec "$target_path" "$@"
        fi
        install_target="$(basename -- "$self_path")"
        {{ install_cached_path }} "${install_target}"
        exec "$target_path" "$@"

{{p}}{{ yaml_string(install_cached_path) }}:
  file.managed:
    - name: {{ yaml_string(install_cached_path) }}
    - mode: 755
    - user: root
    - group: root
    - replace: true
    - contents: |
        #!/bin/bash
        # {{ salt_warning }}
        set -e
        coproc install_service { socat - UNIX-CONNECT:{{ install_cached_package_socket_path }}; }
        socat_pid=$!
        exec {install_service_in}<&${install_service[1]}-
        exec {install_service_out}<&${install_service[0]}-
        install_target="$(basename -- "$self_path")"
        read service_name <&${install_service_out}
        while [ $# -ge 1 ]; do
            cat <<<"$1" >&${install_service_in}
            shift
        done
        exec {install_service_in}<&-
        wait "$socat_pid"
        while ! systemctl list-units --state=activating --quiet | awk -v "service=$service_name" '(index($0, service) != 0) { exit 7 }'; do
            sleep 1
        done
        systemctl is-active --quiet -- "$service_name"

{{p}}Create {{ install_cached_package_socket_group }}:
  group.present:
    - name: {{ install_cached_package_socket_group }}

{{p}}{{ install_cached_package_socket_name }}:
  file.managed:
    - name: {{ yaml_string("/usr/lib/systemd/system/" + install_cached_package_socket_name) }}
    - mode: 444
    - user: root
    - group: root
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Listen for install requests on {{ install_cached_package_socket_path }}
        [Socket]
        ListenStream={{ install_cached_package_socket_path }}
        Accept=yes
        RemoveOnStop=yes
        SocketUser=user
        SocketGroup={{ install_cached_package_socket_group }}
        SocketMode=0660

        [Install]
        WantedBy=multi-user.target qubes-core-agent.service

{{p}}Enable {{ install_cached_package_socket_name }}:
  service.enabled:
    - name: {{ install_cached_package_socket_name }}
    - require:
      - file: {{p}}{{ install_cached_package_socket_name }}

{{p}}{{ yaml_string(install_cached_package_service_name()) }}:
  file.managed:
    - name: {{ yaml_string("/usr/lib/systemd/system/" + install_cached_package_service_name()) }}
    - mode: 444
    - user: root
    - group: root
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Install cached package
        CollectMode=inactive-or-failed
        RefuseManualStart=yes
        ConditionFileNotEmpty={{ install_and_run_env_path }}

        [Service]
        Type=notify
        RemainAfterExit=no
        EnvironmentFile={{ install_and_run_env_path }}
        ExecStart={%- call systemd_shell() -%}
          if [[ "$(stat --format='%%a %%U %%G' "{{ install_and_run_env_path }}")" != "644 root root" ]]; then
            echo "Invalid permissions for {{ install_and_run_env_path }}"
            exit 1
          fi
          . {{ install_and_run_env_path }}

          coproc caller_fd { socat FD:3 -; }
          exec {caller_in}<&$${caller_fd[1]}-
          exec {caller_out}<&$${caller_fd[0]}-
          cat <<<"{{ install_cached_package_service_name('%i') }}" >&$${caller_in}
          new_packages=()
          {%- if target.apt %}
          deb_files=()
          {%- endif %}
          enabled_repos=()
          echo "Waiting for packages"
          while read -r request_line ; do
            binary_names="{{ install_and_run_env_prefix }}$${request_line//[-.]/_}[@]"
            repo_names="{{ install_and_run_env_repo_prefix }}$${request_line//[-.]/_}[@]"
            if [[ -z "$${!binary_names:-}" ]]; then
              echo "Invalid binary name $request_line" >&2
              exec $${caller_out}<&-
              exit 1
            fi
          {%- if target.dnf or target.apt %}
            for repo_name in $${!repo_names}; do
              enabled_repos+=( --enable-repo="$repo_name" )
            done
          {%- else %}
            for repo_name in $${!repo_names}; do
              enabled_repos+=( "$repo_name" )
            done
          {%- endif %}
            for binary_name in $${!binary_names}; do
          {%- if target.apt %}
              if [ -f "$binary_name" ]; then
                deb_files+=( "$binary_name" )
              else
                new_packages+=( "$binary_name" )
              fi
          {%- else %}
              new_packages+=( "$binary_name" )
          {%- endif %}
            done
          done <&$${caller_out}
          echo Installing: "$${new_packages[@]}"
          lock_file=""
          {%- set activate_lock %}
            {%- if target.apt %}
            if [[ "$lock_file" == "" ]]; then
              cat <<<"Activating lock"
              exec {lock_file}<{{ bash_argument(install_and_run_env_path, before='', after='') }}
              flock -x "$lock_file"
            fi
            {%- endif %}
          {%- endset %}
          {%- if target.apt %}
          if [[ "{{- "$${#deb_files[@]}" -}}" -gt 0 ]]; then
            {{- activate_lock }}
            cat <<<"Installing deb files $(printf '"%%s" ' "$${deb_files[@]}")"
            dpkg -i "$${deb_files[@]}"
          fi
          {%- endif %}
          if [ {{'$${#new_packages[@]}'}} -gt 0 ]; then
            {{- activate_lock }}
          {%- set install_command %}
              {%- if target.dnf -%}
                  dnf install -Cy "$${enabled_repos[@]}"
              {%- elif target.apt %}
                  {%- set apt_cmd = apt_with_repo_path("get") + " \"$${enabled_repos[@]}\" install -o DPkg::Lock::Timeout=60 --no-download --yes" %}
                  {%- set target.post_install_command = apt_cmd + " --fix-broken" %}
                  {%- set target.pre_install_command = apt_with_repo_path("get") + " \"$${enabled_repos[@]}\" update" %}
                  {{- apt_cmd }} "$${enabled_repos[@]}"
              {%- endif %} "$${new_packages[@]}"
          {%- endset %}
            cat <<<"Installing $(printf '"%%s" ' "$${new_packages[@]}") with $(printf '"%%s" ' {{ install_command }})"
            {%- if target.pre_install_command %}
              {{ target.pre_install_command }}
            {%- endif %}
            {%- if target.dnf %}
            for i in {1..30}; do
                install_output=$(({{ install_command }}) 2>&1 1>/dev/null)
                install_status=$?
                case "$install_status" in
                  0)
                    break
                  ;;
                  200)
                    echo "DNF could not acquire lock, retrying"
                  ;;
                  *)
                    if grep -i "Failed to obtain rpm transaction lock." <<<"$install_output"; then
                      echo "DNF still fucking sucks and doesn't report transaction lock failures."
                    else
                      cat <<<"$install_output" >&2
                      break
                    fi
                  ;;
                esac
                retry_delay="$$((i/10)).$$((i%%10))"
                cat <<<"Retrying in $retry_delay seconds" >&2
                sleep -- "$retry_delay"
            done
            {%- else %}
            {{ install_command }}
            install_status=$?
            {%- endif %}
            {%- if target.post_install_command %}
              {{ target.post_install_command }}
            {%- endif %}
            if [ $install_status -ne 0 ]; then
                exit 1
            fi
          fi
          systemd-notify --ready
          sleep 10
          # if [[ "$lock_file" != "" ]]; then
          #   exec {lock_file}<&-
          # fi
          # exec {caller_in}<&-
          # exec {caller_out}<&-
     {%- endcall %}
  {%- endif %}

  {%- if target.apt %}
    {%- for subcmd in ['get', 'cache'] %}
{{ apt_with_repo_state(subcmd) }}:
  file.symlink:
    - name: {{ apt_with_repo_path(subcmd) }}
    - target: {{ apt_with_repo_name() }}
    - require:
      - file: {{ apt_with_repo_state() }}
    {%- endfor %}

{{ apt_with_repo_state() }}:
  file.managed:
    - name: {{ apt_with_repo_path() }}
    - mode: 555
    - user: root
    - group: root
    - replace: true
    - contents: {% call yaml_string() %}{%- call trim_common_whitespace() %}
        # {{ salt_warning }}
        apt_path="${BASH_SOURCE[-1]%{{ apt_with_repo_suffix }}}"
        {%- set unshare_script %}
        apt_path="$0"
        apt_repos=()
        apt_args=()
        while [ $# -ge 1 ]; do
          case $1 in
            --enablerepo=*)
              apt_repos+=( "${1#--enablerepo=}" )
              ;;
            --enable-repo=*)
              apt_repos+=( "${1#--enable-repo=}" )
              ;;
            --enablerepo | --enable-repo)
              if [ $# -ge 2 ]; then
                shift
                apt_repos+=( "$1" )
              else
                echo "Need argument after --enable-repo"
                exit 1
              fi
              ;;
            *)
              apt_args+=( "$1" )
              ;;
          esac
          shift
        done
        if [ "{{ "${#apt_repos[@]}" }}" -eq 0 ]; then
            exec "$apt_path" "${apt_args[@]}"
        else
            mount -t tmpfs none /tmp
            for repo_name in "${apt_repos[@]}"; do
              if ! [ -f "/tmp/repo-$repo_name.sources" ]; then
                (grep -v 'Enabled:' <"/etc/apt/sources.list.d/$repo_name.sources"; echo 'Enabled: yes') >"/tmp/repo-$repo_name.sources"
                mount -Br "/tmp/repo-$repo_name.sources" "/etc/apt/sources.list.d/$repo_name.sources"
              fi
            done
            umount /tmp
            exec unshare -m "$apt_path" "${apt_args[@]}"
        fi
        {%- endset %}
        unshare_script={{ bash_argument(unshare_script, before='', after='') }}

        exec unshare -m /bin/bash -c "$unshare_script" "$apt_path" "$@"
     {%- endcall %}{%- endcall %}
  {%- endif %}
{%- endif %}
