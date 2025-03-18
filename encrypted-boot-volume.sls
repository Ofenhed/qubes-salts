{%- if grains['id'] == 'dom0' %}
{% from "formatting.jinja" import systemd_shell, bash_argument, format_shell_exec, yaml_string %}
{%- from "dependents.jinja" import add_dependencies, trigger_as_dependency %}

{%- set p = "Encrypted boot volume - " %}

{%- macro boot_sync_unit_name(name) -%}
  boot-sync@{{name}}
{%- endmacro %}

{%- macro boot_sync_service(name) %}
  {{- boot_sync_unit_name(name) }}.service
{%- endmacro %}

{%- macro boot_sync_path(name) %}
  {{- boot_sync_unit_name(name) }}.path
{%- endmacro %}

{%- macro boot_watcher_initial_scanner_service(name) -%}
  boot-watcher-init@{{ name }}.service
{%- endmacro %}

{%- set systemd_path = "/usr/lib/systemd/system" %}
{%- set boot_watcher_service = "boot-watcher.service" %}
{%- set boot_watcher_initial_scanner_service_path = systemd_path + "/" + boot_watcher_initial_scanner_service("") %}
{%- set boot_watcher_service_path = systemd_path + "/" + boot_watcher_service %}
{%- set boot_sync_instance_service_path = systemd_path + "/" + boot_sync_service("") %}
{%- set boot_sync_instance_path_path = systemd_path + "/" + boot_sync_path("") %}
{%- set grub2_mkconfig_path = "/usr/local/sbin/grub2-mkconfig" %}

{%- set boot_shadow = '/tmp/boot_shadow' %}

{%- set watched_files = [boot_watcher_service_path, boot_watcher_initial_scanner_service_path, boot_sync_instance_service_path, boot_sync_instance_path_path] %}

{%- set enable_systemd_service = "Enable service " + boot_watcher_service %}
{%- set disable_systemd_service = "Disable service " + boot_watcher_service %}

{%- set boot_partition = salt['pillar.get']('partition:boot', none) %}
{%- set boot_efi_partition = salt['pillar.get']('partition:boot_efi', none) %}

{{p}}{{ boot_watcher_service_path }}:
  {%- if boot_partition == none %}
  file.absent:
    - name: {{ boot_watcher_service_path }}
    - require:
        - service: {{p}}{{ disable_systemd_service }}
  {%- else %}
  file.managed:
    - name: {{ boot_watcher_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Sync files from /boot to plain text devices
        Requires={{ boot_watcher_initial_scanner_service("-") }}
        Before={{ boot_watcher_initial_scanner_service("-") }}
        
        [Service]
        Type=forking
        # TODO: Mount boot and EFI here
        ExecStart={%- call systemd_shell() %}
          mkdir {{ boot_shadow }}
          mount -t {{ bash_argument(boot_partition.type) }} -o {{ bash_argument(boot_partition.options) }} {{ bash_argument(boot_partition.source) }} {{ boot_shadow }}
          {%- if boot_efi_partition != none %}
          mkdir {{ boot_shadow }}/efi
          mount -t {{ bash_argument(boot_efi_partition.type) }} -o {{ bash_argument(boot_efi_partition.options) }} {{ bash_argument(boot_efi_partition.source) }} {{ boot_shadow }}/efi
          {%- endif %}
          tail -f /dev/null & ln -s "/proc/$!" /tmp/parent
        {%- endcall %}
        ProtectSystem=strict
        PrivateTmp=true
        
        [Install]
        WantedBy=multi-user.target
  {%- endif %}

{{p}}{{ boot_watcher_initial_scanner_service_path }}:
  {%- if boot_partition == none %}
  file.absent:
    - name: {{ boot_watcher_initial_scanner_service_path }}
    - require:
        - service: {{p}}{{ disable_systemd_service }}
  {%- else %}
  file.managed:
    - name: {{ boot_watcher_initial_scanner_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Scan for paths to monitor in /boot/%I
        StartLimitBurst=0
        Requires={{ boot_sync_path("%i") }} {{ boot_watcher_service }}
        Before={{ boot_sync_path("%i") }}
        After={{ boot_watcher_service }}
        
        [Service]
        Type=oneshot
        WorkingDirectory=/boot/%I
        ExecStart={%- call systemd_shell() %}
          for dir in *; do
              if [ -d "$dir" ]; then
                  boot_path=$(systemd-escape --path "$(realpath --relative-to "/boot" "$dir")")
                  systemctl start "{{ boot_watcher_initial_scanner_service("$boot_path") }}"
              fi
          done
        {%- endcall %}
        
        [Install]
        WantedBy=multi-user.target
  {%- endif %}


{{p}}{{ boot_sync_instance_service_path }}:
  {%- if boot_partition == none %}
  file.absent:
    - name: {{ boot_sync_instance_service_path }}
    - require:
        - service: {{p}}{{ disable_systemd_service }}
  {%- else %}
  file.managed:
    - name: {{ boot_sync_instance_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Sync files from /boot/%I to {{ boot_partition.source }}/%I
        Requires={{ boot_watcher_service }}
        JoinsNamespaceOf={{ boot_watcher_service }}
        
        [Service]
        Type=oneshot
        Environment="BOOT_DIR=%I"
        ExecStart=nsenter --mount=/tmp/parent/ns/mnt {% call systemd_shell() %}
          (
            cd "{{ boot_shadow }}/$BOOT_DIR"
            for target_file in *; do
                if [ -f "$target_file" ] && [ ! -f "/boot/$BOOT_DIR/$target_file" ]; then
                    rm $target_file
                fi
            done
          )
          (
            cd "/boot/$BOOT_DIR"
            for source_file in *; do
                if [ -f "$source_file" ]; then
                    if [ ! -f "{{ boot_shadow }}/$BOOT_DIR/$source_file" ]; then
                        cp -ua "$source_file" "{{ boot_shadow }}/$BOOT_DIR/"
                    elif ! diff "$source_file" "{{ boot_shadow }}/$BOOT_DIR/$source_file"; then
                        cp -a "$source_file" "{{ boot_shadow }}/$BOOT_DIR/"
                    fi
                fi
            done
          )
        {%- endcall %}
        ProtectSystem=strict
        PrivateTmp=true
        
        [Install]
        WantedBy=multi-user.target
  {%- endif %}

{{p}}{{ boot_sync_instance_path_path }}:
  {%- if boot_partition == none %}
  file.absent:
    - name: {{ boot_sync_instance_path_path }}
    - require:
        - service: {{p}}{{ disable_systemd_service }}
  {%- else %}
  file.managed:
    - name: {{ boot_sync_instance_path_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Watch for changes in /boot/%I
        Requires={{ boot_watcher_service }}
        After={{ boot_watcher_service }}
        ConditionPathIsDirectory=/boot/%I
        
        [Path]
        PathChanged=/boot/%I
        TriggerLimitBurst=0
        
        [Install]
        WantedBy=multi-user.target
  {%- endif %}

{{p}}{{ grub2_mkconfig_path }}:
  {%- if boot_partition == none %}
  file.absent:
    - name: {{ grub2_mkconfig_path }}
  {%- else %}
  file.managed:
    - name: {{ grub2_mkconfig_path }}
    - user: root
    - require:
        - service: {{p}}{{ enable_systemd_service }}
    - require_in:
        - {{ trigger_as_dependency('grub') }}
    - group: root
    - mode: 555
    - replace: true
    - contents: |
        #!/bin/sh
        if [ $# -ne 2 ] || [ $1 != "-o" ]; then
          echo Usage: $0 -o filename >&2
          exit 1
        fi
        exec 5<> $2

        process_pid=$(systemctl show --property MainPID --value {{ bash_argument(boot_watcher_service) }})
        if [ $process_pid -eq 0 ]; then
          echo The service {{ bash_argument(boot_watcher_service) }} must be running for grub2-mkconfig to work >&2
          exit 1
        fi
        nsenter --mount="/proc/$process_pid/ns/mnt" {% call format_shell_exec() -%}
          unshare --propagation private --mount {% call format_shell_exec() -%}
            set -e
            mount -B /dev/null {{ bash_argument(grub2_mkconfig_path) }}
            mount -B {{ boot_shadow }}/ /boot/
            mount -t tmpfs tmpfs /tmp/
            grub2-mkconfig -o /tmp/grub.cfg
            cat < /tmp/grub.cfg >&5
          {%- endcall %}
        {%- endcall %}
  {%- endif %}

{%- call add_dependencies('daemon-reload') %}
  {%- for file in watched_files %}
  - file: {{p}}{{ file }}
  {%- endfor %}
{%- endcall %}

  {%- if boot_partition == none %}
{{p}}{{ disable_systemd_service }}:
  service.dead:
    - name: {{ boot_watcher_service }}
    - enable: false
  {%- else %}
{{p}}{{ enable_systemd_service }}:
  service.running:
    - name: {{ boot_watcher_service }}
    - enable: true
    - require:
      - {{ trigger_as_dependency('daemon-reload') }}
  {%- endif %}

{%- endif %}
