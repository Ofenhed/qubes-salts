{%- if grains['id'] == 'dom0' %}
{% from "formatting.jinja" import systemd_shell, bash_argument %}
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

{%- set watched_files = [boot_watcher_service_path, boot_watcher_initial_scanner_service_path, boot_sync_instance_service_path, boot_sync_instance_path_path] %}

{%- set enable_systemd_service = "Enable systemd service" %}

{{p}}{{ boot_watcher_service_path }}:
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
          mkdir /tmp/boot_shadow
          mount -t {{ bash_argument(salt['pillar.get']('partition:boot:type')) }} -o {{ bash_argument(salt['pillar.get']('partition:boot:options')) }} {{ bash_argument(salt['pillar.get']('partition:boot:source')) }} /tmp/boot_shadow
          mkdir /tmp/boot_shadow/efi
          mount -t {{ bash_argument(salt['pillar.get']('partition:boot_efi:type')) }} -o {{ bash_argument(salt['pillar.get']('partition:boot_efi:options')) }} {{ bash_argument(salt['pillar.get']('partition:boot_efi:source')) }} /tmp/boot_shadow/efi
          tail -f /dev/null & ln -s "/proc/$!" /tmp/parent
        {%- endcall %}
        ExecStopPre=find /tmp/boot_shadow -type f
        ProtectSystem=strict
        PrivateTmp=true
        
        [Install]
        WantedBy=multi-user.target

{{p}}{{ boot_watcher_initial_scanner_service_path }}:
  file.managed:
    - name: {{ boot_watcher_initial_scanner_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Sync files from /boot/%I to /not_boot/%I
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


{{p}}{{ boot_sync_instance_service_path }}:
  file.managed:
    - name: {{ boot_sync_instance_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Detect when /boot/%I changes
        Requires={{ boot_watcher_service }}
        JoinsNamespaceOf={{ boot_watcher_service }}
        
        [Service]
        Type=oneshot
        Environment="BOOT_DIR=%I"
        ExecStart=nsenter --mount=/tmp/parent/ns/mnt {% call systemd_shell() %}
          (
            cd "/tmp/boot_shadow/$BOOT_DIR"
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
                    if [ ! -f "/tmp/boot_shadow/$BOOT_DIR/$source_file" ]; then
                        cp -ua "$source_file" "/tmp/boot_shadow/$BOOT_DIR/"
                    elif ! diff "$source_file" "/tmp/boot_shadow/$BOOT_DIR/$source_file"; then
                        cp -a "$source_file" "/tmp/boot_shadow/$BOOT_DIR/"
                    fi
                fi
            done
          )
        {%- endcall %}
        ProtectSystem=strict
        PrivateTmp=true
        
        [Install]
        WantedBy=multi-user.target

{{p}}{{ boot_sync_instance_path_path }}:
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

{%- call add_dependencies('daemon-reload') %}
  {%- for file in watched_files %}
  - file: {{p}}{{ file }}
  {%- endfor %}
{%- endcall %}

{{p}}{{ enable_systemd_service }}:
  service.running:
    - name: {{ boot_watcher_service }}
    - watch:
      - {{ trigger_as_dependency('daemon-reload') }}

{%- endif %}
