{%- if grains['id'] == 'dom0' %}
{% from "formatting.jinja" import systemd_shell, systemd_string, bash_argument, format_shell_exec, yaml_string, salt_warning %}
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

{%- macro boot_sync_restart_service(name) -%}
  restart-{{- boot_sync_unit_name(name) }}.service
{%- endmacro %}

{%- macro boot_sync_initial_scanner_service(name) -%}
  boot-watcher-init@{{ name }}.service
{%- endmacro %}

{%- macro boot_sync_failed_service(name) -%}
  boot-sync-failed@.service
{%- endmacro %}

{%- set systemd_path = "/usr/lib/systemd/system" %}
{%- set boot_watcher_service = "boot-watcher.service" %}
{%- set boot_sync_initial_scanner_service_path = systemd_path + "/" + boot_sync_initial_scanner_service("") %}
{%- set boot_watcher_service_path = systemd_path + "/" + boot_watcher_service %}
{%- set boot_sync_instance_service_path = systemd_path + "/" + boot_sync_service("") %}
{%- set boot_sync_instance_restart_service_path = systemd_path + "/" + boot_sync_restart_service("") %}
{%- set boot_sync_instance_path_path = systemd_path + "/" + boot_sync_path("") %}
{%- set boot_sync_failed_service_path = systemd_path + "/" + boot_sync_failed_service('') %}
{%- set grub2_mkconfig_path = "/usr/local/sbin/grub2-mkconfig" %}
{%- set update_fstab = "Update fstab" %}

{%- set salt_pillar_base_filename = 'encrypted-boot-volumes' %}

{%- set encrypted_boot_volume_pillar_sls = '/srv/user_pillar/' + salt_pillar_base_filename + '.sls' %}
{%- set encrypted_boot_volume_pillar_top = '/srv/user_pillar/' + salt_pillar_base_filename + '.top' %}

{%- set boot_shadow = '/tmp/boot_shadow' %}
{%- set proc_parent = '/tmp/parent' %}

{%- set systemd_files = [boot_watcher_service_path, boot_sync_instance_service_path, boot_sync_instance_path_path, boot_sync_failed_service_path, boot_sync_instance_restart_service_path] %}

{%- set enable_systemd_service = "Enable service " + boot_watcher_service %}
{%- set shut_down_systemd_service = "Shut down service " + boot_watcher_service %}

{%- set is_activated = salt['pillar.get']('activate-encrypted-boot', false) %}
{%- set notify_failure_to_user = salt['pillar.get']('notify-user', none) %}
{%- set comment_prefix = '#shadow:' %}

{{p}}{{ encrypted_boot_volume_pillar_sls }}:
  file.managed:
    - name: {{ encrypted_boot_volume_pillar_sls }}
    - user: root
    - group: root
    - mode: 640
    - replace: false
    - contents: |
        {{ '{#- ' + salt_warning + '-#}' }}
        activate-encrypted-boot: true

{{p}}{{ encrypted_boot_volume_pillar_top }}:
  file.managed:
    - name: {{ encrypted_boot_volume_pillar_top }}
    - user: root
    - group: root
    - mode: 640
    - replace: false
    - contents: |
        {{ '{#- ' + salt_warning + '-#}' }}
        user:
          dom0:
            - {{ salt_pillar_base_filename }}

  {%- if not is_activated %}
{{p}} How to use:
  test.show_notification:
    - name: "Encrypted boot volume is not activated."
    - order: last
    - text: |
        To activate it, execute the following:
        qubesctl top.enable {{ salt_pillar_base_filename }} pillar=True
  {%- endif %}

{{p}}{{ update_fstab }}:
  {%- if is_activated %}
  file.comment:
  {%- else %}
  file.uncomment:
  {%- endif %}
    - name: /etc/fstab
    - regex: ^[^#\s]+\s+/boot(/efi)?\s+
    - char: {{ yaml_string(comment_prefix + ' ') }}

{{p}}{{ boot_sync_failed_service_path }}:
  file.managed:
    - name: {{ boot_sync_failed_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Notify the user about boot disk being full
        Requires=graphical.target
        After=graphical.target
        RefuseManualStart=true
        StopWhenUnneeded=true

        [Service]
        Type=oneshot
        Environment="DISPLAY=:0"
        Environment="FULL_BOOT_PATH=/boot/%I"
        ExecStart={%- call systemd_shell() %}
            users="$(who | awk '{ print $1 }' | sort -u)"
            for user in $(who | awk '{ print $1 }' | sort -u); do
            (
                set -e
                uid="$(id -u "$user")"
                dbus="/run/user/$uid/bus"
                set +e
                boot_path=$(realpath -- "$FULL_BOOT_PATH" 2>/dev/null || cat <<< "$FULL_BOOT_PATH")
                set -e
                function userdo() {
                    sudo DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$dbus" -u "$user" "$@"
                }
                if [ "$(userdo notify-send --urgency critical --action=explore=Explore "Could not write file to $boot_path")" == "explore" ]; then
                    userdo xdg-open "$FULL_BOOT_PATH"
                fi
            ) &
            done
            wait
        {%- endcall %}

{{p}}{{ boot_watcher_service_path }}:
  {%- if not is_activated %}
  file.absent:
    - name: {{ boot_watcher_service_path }}
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
        Requires={{ boot_sync_service("-") }} local-fs.target
        After=local-fs.target
        Before={{ boot_sync_service("-") }}

        [Service]
        Type=forking
        Environment={{ systemd_string("BOOT_SHADOW=" + boot_shadow) }}
        ExecStart={%- call systemd_shell() %}
          set -e
          mkdir "$BOOT_SHADOW"
          export fstab_prefix={{ bash_argument(comment_prefix, before='', after='') }}
          boot_mount_args=$(awk '{ if ($1 == ENVIRON["fstab_prefix"] && $3 == "/boot") { print "-t " $4 " -o " $5 " " $2 } }' < /etc/fstab)
          mount $boot_mount_args "$BOOT_SHADOW"
          boot_efi_mount_args=$(awk '{ if ($1 == ENVIRON["fstab_prefix"] && $3 == "/boot/efi") { print "-t " $4 " -o " $5 " " $2 } }' < /etc/fstab)
          if [ "$boot_efi_mount_args" != "" ]; then
            efi_path="$BOOT_SHADOW/efi"
            mkdir -p "$efi_path"
            mount $boot_efi_mount_args "$efi_path"
          fi
          sleep infinity & ln -s "/proc/$!" {{ proc_parent }}
        {%- endcall %}
        ExecStartPost=nsenter --mount={{ proc_parent }}/ns/mnt df -h "$BOOT_SHADOW" "$BOOT_SHADOW/efi/"
        ExecStop=nsenter --mount={{ proc_parent }}/ns/mnt df -h "$BOOT_SHADOW" "$BOOT_SHADOW/efi/"
        ProtectSystem=strict
        PrivateTmp=true

        [Install]
        WantedBy=multi-user.target
  {%- endif %}

{{p}}{{ boot_sync_initial_scanner_service_path }}:
  file.absent:
    - name: {{ boot_sync_initial_scanner_service_path }}

{{p}}{{ boot_sync_instance_restart_service_path }}:
  {%- if not is_activated %}
  file.absent:
    - name: {{ boot_sync_instance_restart_service_path }}
  {%- else %}
  file.managed:
    - name: {{ boot_sync_instance_restart_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Restart {{ boot_sync_service("%i") }}
        Conflicts={{ boot_sync_service("%i") }}

        [Service]
        Type=oneshot
        ExecStart=sleep 1
        ExecStopPost=systemctl start {{ boot_sync_service("%i") }}
  {%- endif %}

{{p}}{{ boot_sync_instance_service_path }}:
  {%- if not is_activated %}
  file.absent:
    - name: {{ boot_sync_instance_service_path }}
  {%- else %}
  file.managed:
    - name: {{ boot_sync_instance_service_path }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        [Unit]
        Description=Sync files from root mount /boot/%I to boot disk
        Requires={{ boot_watcher_service }} local-fs.target
        Wants={{ boot_sync_path("%i") }}
        JoinsNamespaceOf={{ boot_watcher_service }}
        After=local-fs.target {{ boot_watcher_service }}
        OnFailure={{ boot_sync_failed_service("%i") }}

        [Service]
        Type=notify
        Environment="BOOT_DIR=%I"
        Environment={{ systemd_string("BOOT_SHADOW=" + boot_shadow) }}
        ExecStart=nsenter --mount={{ proc_parent }}/ns/mnt {% call systemd_shell() %}
          set -e
          shopt -s nullglob
          if [ $BOOT_DIR == "lost+found" ] || [ $BOOT_DIR == "efi/lost+found" ]; then
              echo "Ignoring lost+found"
              systemctl mask "{{ boot_sync_path("%i") }}" "{{ boot_sync_service("%i") }}"
              systemctl stop "{{ boot_sync_path("%i") }}"
              systemd-notify --ready
              exit
          fi
          if cd "/boot/$BOOT_DIR" 2>/dev/null; then
              for source_file in * .[^.]*; do
                  if [ -d "$source_file" ]; then
                      mkdir -p "$BOOT_SHADOW/$BOOT_DIR/$source_file"
                      boot_path=$(systemd-escape --path "$(realpath --relative-to "/boot" "$source_file")" 2>/dev/null)
                      systemctl start --no-block "{{ boot_sync_service("$boot_path") }}" || true
                  fi
              done
              systemd-notify --ready
              exec sleep infinity
          fi
        {%- endcall %}
        ExecStop=nsenter --mount={{ proc_parent }}/ns/mnt {% call systemd_shell() %}
          set -e
          shopt -s nullglob
          result=0
          if cd "/boot/$BOOT_DIR" 2>/dev/null; then
              mkdir -p "$BOOT_SHADOW/$BOOT_DIR"
              for source_file in * .[^.]*; do
                  if [ -f "$source_file" ]; then
                      if [ ! -f "$BOOT_SHADOW/$BOOT_DIR/$source_file" ]; then
                          echo "Copying /boot/$BOOT_DIR/$source_file"
                          if ! cp -a "$source_file" "$BOOT_SHADOW/$BOOT_DIR/"; then
                              echo "Failed to copy /boot/$BOOT_DIR/$source_file"
                              nonlocal result=1
                          fi
                      elif ! diff -q "$source_file" "$BOOT_SHADOW/$BOOT_DIR/$source_file" >/dev/null; then
                          echo "Replacing /boot/$BOOT_DIR/$source_file"
                          if ! cp -a "$source_file" "$BOOT_SHADOW/$BOOT_DIR/"; then
                              echo "Failed to copy /boot/$BOOT_DIR/$source_file"
                              result=1
                          fi
                      fi
                  fi
              done
          fi
          if cd "$BOOT_SHADOW/$BOOT_DIR" 2>/dev/null; then
              for target_file in * .[^.]*; do
                  if [ -f "$target_file" ] && [ ! -f "/boot/$BOOT_DIR/$target_file" ]; then
                      echo "Removing /boot/$BOOT_DIR/$target_file"
                      rm $target_file
                  elif [ -d "$target_file" ] && [ ! -d "/boot/$BOOT_DIR/$target_file" ]; then
                      boot_path=$(systemd-escape --path "$(realpath --relative-to "$BOOT_SHADOW" "$target_file")" 2>/dev/null)
                      systemctl start --wait "{{ boot_sync_service("$boot_path") }}" || true
                      systemctl stop --wait "{{ boot_sync_service("$boot_path") }}"
                  fi
              done
              if [ ! -d "/boot/$BOOT_DIR" ]; then
                  echo "Removing /boot/$BOOT_DIR/"
                  systemctl stop "{{ boot_sync_path("%i") }}"
                  rmdir -- "$BOOT_SHADOW/$BOOT_DIR"
              fi
          fi
          exit "$result"
        {%- endcall %}
        ProtectSystem=strict
        PrivateTmp=true
  {%- endif %}

{{p}}{{ boot_sync_instance_path_path }}:
  {%- if not is_activated %}
  file.absent:
    - name: {{ boot_sync_instance_path_path }}
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
        Requires={{ boot_watcher_service }} local-fs.target
        After=local-fs.target
        Before={{ boot_watcher_service }}
        ConditionPathIsDirectory=/boot/%I

        [Path]
        PathChanged=/boot/%I
        Unit={{ boot_sync_restart_service("%i") }}
        TriggerLimitIntervalSec=0
  {%- endif %}

{{p}}{{ grub2_mkconfig_path }}:
  {%- if not is_activated %}
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
  {%- for file in systemd_files %}
  - file: {{p}}{{ file }}
  {%- endfor %}
{%- endcall %}

{{p}}{{ shut_down_systemd_service }}:
  service.dead:
    - name: {{ boot_watcher_service }}
  {%- if not is_activated %}
    - enable: false
  {%- endif %}
    - onchanges:
  {%- for file in systemd_files %}
        - file: {{p}}{{ file }}
  {%- endfor %}


  {%- if is_activated %}
{{p}}{{ enable_systemd_service }}:
  service.running:
    - name: {{ boot_watcher_service }}
    - enable: true
    - require:
      - {{ trigger_as_dependency('daemon-reload') }}
      - service: {{p}}{{ shut_down_systemd_service }}
  {%- endif %}

{%- endif %}
