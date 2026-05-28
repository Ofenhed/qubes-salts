{%- if grains['id'] == 'dom0' %}
{%- from "formatting.jinja" import format_shell_exec, bash_argument, salt_warning, escape_bash, yaml_string, format_exec_env_script %}
{%- from "grub.jinja" import cmdline_linux, grub_options %}

{%- set cmdline_variable_name = "uki.generator.uuid" %}

{%- set p = "Build uki - " %}
{%- set uki_options = salt['pillar.get']('uki', {}) %}
{%- set tmp_dir = salt['temp.dir']() %}
{%- set tmp_xen_verification_output = tmp_dir + '/xen_verification' %}
{%- set tmp_kernel_verification_output = tmp_dir + '/kernel_verification' %}
{%- set tmp_current_kernel_output = tmp_dir + '/kernel_version' %}
{%- set tmp_uki_config_file = tmp_dir + '/uki.conf' %}
{%- set tmp_current_elf = tmp_dir + '/current.elf' %}
{%- set tmp_initrd_image = tmp_dir + '/initrd.img' %}
{%- set tmp_dracut_uki = tmp_dir + '/dracut.uki' %}
{%- set tmp_new_elf = tmp_dir + '/new_qubes.efi' %}
{%- set tmp_new_elf_stripped = tmp_dir + '/new_qubes_stripped.efi' %}

{%- set efi_dir = '/boot/efi/EFI/qubes' %}
{%- set efi_current = 'qubes.efi' %}
{%- set efi_backup = 'qubes_working.efi' %}
{%- set efi_current_path = efi_dir + '/' + efi_current %}
{%- set efi_backup_path = efi_dir + '/' + efi_backup %}
{%- set efi_prev_working = 'qubes_working.efi' %}
{%- set efi_prev_working_path = efi_dir + '/' + efi_prev_working %}

{%- set check_plain_text_dependencies = "Check plain text dependencies" %}
{%- set verify_plain_text_dependencies = "Verify xen image" %}
{%- set create_dracut_image = "Create dracut initrd" %}
{%- set create_dracut_kernel = "Create dracut kernel" %}
{%- set create_config = "Create config" %}
{%- set create_uki = "Create unified kernel" %}
{%- set install_uki = "Install unified kernel" %}
{%- set create_efi_backup = "Create EFI backup" %}
{%- set set_nextboot = "Set nextboot to TPM enroll" %}
{%- set delete_temporary = "Delete temporary files" %}

{{- grub_options(cmdline_linux, "Add random hash to generated commandline", cmdline_variable_name + "=$(dd if=/dev/random bs=2K count=10 | sha256sum | awk '{ print $1 }')", escape = False) }}

{{p}}{{ check_plain_text_dependencies }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('check_plain_text_dependencies')) }}
    - env:
      - check_plain_text_dependencies: {% call yaml_string() %}
        set -e
        echo Hypervisor
        rpm -Vv xen-hypervisor | awk '{ if ($2 ~ /^\/boot\/efi\/EFI\/qubes\/xen-.*\.efi$/) print $1 "\t" $2 }' | tee {{ bash_argument(tmp_xen_verification_output) }}
        echo
        echo Kernel
        rpm -Vv kernel | awk '{ if ($2 ~ /^\/boot\/vmlinuz-/) print $1 "\t" $2 }' | tee {{ bash_argument(tmp_kernel_verification_output) }}
      {%- endcall %}


{{p}}{{ verify_plain_text_dependencies }}:
  cmd.run:
    {%- set checks = {'S': 'file size', '5': 'checksum', 'L': 'symbolic link', 'D': 'device', 'U': 'user', 'G': 'group', '?': 'Unreadable file' } %}
    - require:
      - cmd: {{p}}{{ check_plain_text_dependencies }}
    - name: {{ yaml_string(format_exec_env_script('verify_plain_text_dependencies')) }}
    - env:
      - verify_plain_text_dependencies: {% call yaml_string() %}
          set -e
          for input_file in {% for status_file in [tmp_xen_verification_output, tmp_kernel_verification_output] %}
            {{- bash_argument(status_file) }}
          {%- endfor %}; do
            rpm_discrepancies=$(awk '{ print $1 }' < {{ bash_argument(tmp_xen_verification_output) }}) || die "Could not read" {{ bash_argument(tmp_xen_verification_output) }}
            echo "$rpm_discrepancies"
            if false; then
                false
            {%- for check, value in checks.items() %}
            elif grep {{ bash_argument(check) }} <<< "$rpm_discrepancies" >/dev/null; then
                echo Fail in $input_file: {{ bash_argument(value) }} >&2
                exit 1
            {%- endfor %}
            fi
          done
          awk '{ print $2 }' < {{ bash_argument(tmp_kernel_verification_output) }} | sort -rV | head -n 1 | tee {{ bash_argument(tmp_current_kernel_output) }}
      {%- endcall %}

{{p}}{{ create_dracut_image }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script('build_dracut_image')) }}
    - env:
      - build_dracut_image: {% call yaml_string() %}
          {%- set build_command = salt['pillar.get']('salt-build-targets:dracut', none) %}
          {%- if build_command is none %}
          echo "Pillar salt-build-targets:dracut not set"
          exit 1
          {%- else %}
          {%- do build_command.pop(0) %}
          kernel_image=$(cat < {{ bash_argument(tmp_current_kernel_output) }})
          build_command='dracut '{{ bash_argument(tmp_initrd_image, before='', after='') }}
          {%- for argument in build_command %}
            {{- bash_argument(argument, before="' '", after='') }}
          {%- endfor %}" --kver $(grep -Po '(?<=/boot/vmlinuz-).*' <<< "$kernel_image")"
          /bin/bash <<< "$build_command"
          {%- endif %}
        {%- endcall %}

{{p}}{{ create_config }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script("create_config")) }}
    - env:
      - create_config: |
            (
            set -e
            . /etc/default/grub
            cat <<EOF
            [global]
            default=qubes
            [qubes]
            options=noexitboot=1 mapbs=1 $GRUB_CMDLINE_XEN_DEFAULT
            kernel=vmlinuz root=/dev/mapper/qubes_dom0-root $GRUB_CMDLINE_LINUX
            EOF
            {%- for (name, options) in salt['pillar.get']('uki:configs', {}).items() %}
            cat <<EOF
            [{{- name -}}]
            options=$GRUB_CMDLINE_XEN_DEFAULT
              {%- if 'options' in options %}
                {{- " " + options['options'] }}
              {%- endif %}
            kernel=vmlinuz root=/dev/mapper/qubes_dom0-root $GRUB_CMDLINE_LINUX
              {%- if 'kernel' in options %}
                {{- " " + options['kernel'] }}
              {%- endif %}
            EOF
            {%- endfor %}
            ) > {{ bash_argument(tmp_uki_config_file) }}

{{p}}{{ create_uki }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script("create_uki")) }}
    - require:
      - cmd: {{p}}{{ create_config }}
      - cmd: {{p}}{{ verify_plain_text_dependencies }}
      - cmd: {{p}}{{ create_dracut_image }}
    - env:
      - create_uki: {% call yaml_string() %}
          set -e
          xen_image=$(awk '{ print $2 }' < {{ bash_argument(tmp_xen_verification_output) }})
          initrd_image='{{ tmp_initrd_image }}'
          kernel_image=$(cat < {{ bash_argument(tmp_current_kernel_output) }})
          echo initrd: {{ bash_argument(tmp_initrd_image) }}
          uki_generate_args=()
          {%- set cpu_ucode = bash_argument(uki_options['cpu-ucode']) if 'cpu-ucode' in uki_options else none %}
          {%- if cpu_ucode is not none %}
          if [ -f {{ cpu_ucode }} ]; then
              uki_generate_args+=( --custom-section ucode {{ cpu_ucode }} )
          else
              echo "Could not find ucode image" {{ cpu_ucode }}
          fi
          {%- endif %}
          echo "Xen image: $xen_image"
          echo "Kernel image: $kernel_image"
          echo "Initrd image: $initrd_image"
          echo "Config:"
          cat {{ bash_argument(tmp_uki_config_file) }}
          echo

          {%- for prefix in ["printf '\"%s\" '", ""] %}
          {{ prefix }} /usr/lib/qubes/uki-generate "${uki_generate_args[@]}" "$xen_image" {{ bash_argument(tmp_uki_config_file) }} "$kernel_image" "$initrd_image" {{ bash_argument(tmp_new_elf) }}
          {{ prefix }} objcopy --remove-section=.ramdisk -- {{ bash_argument(tmp_new_elf) }} {{ bash_argument(tmp_new_elf_stripped) }}
          {%- endfor %}
        {%- endcall %}

{{p}}{{ create_efi_backup }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script("create_efi_backup")) }}
    - stateful: True
    - require:
      - cmd: {{p}}{{ create_uki}}
    - env:
      - awk_script_extract_uid: {% call yaml_string() %}
          {
            for (i=1; i<=NF; i++) {
              if ($i ~ /^{{ cmdline_variable_name | regex_escape }}/) {
                split($i,f,"=");
                print f[2];
                exit 0
              }
            }
          }
      {%- endcall %}
      - create_efi_backup: {% call yaml_string() %}
          set -e
          cp {{ bash_argument(efi_current_path) }} {{ bash_argument(tmp_current_elf) }}
          {%- macro extract_uid(filename) -%}
          $(awk "$awk_script_extract_uid" < {{ bash_argument(filename) }})
          {%- endmacro %}
          current_uid={{- extract_uid('/proc/cmdline') }}
          if [ "$current_uid" == "" ]; then
            echo {{ bash_argument({"changed": false, "comment": "Current kernel not started with a " + cmdline_variable_name + " parameter"} | tojson()) }}
            exit 1
          fi
          objcopy -O binary --only-section=.config {{ bash_argument(tmp_current_elf) }}
          target_elf_uid={{- extract_uid(tmp_current_elf) }}
          if [[ $current_uid == $target_elf_uid ]]; then
            cp {{ bash_argument(efi_current_path) }} {{ bash_argument(efi_backup_path) }}
            echo '{"changed": true, "comment": "'"$(sha256sum -- {{ bash_argument(efi_backup_path) }})"'"}'
          else
            echo '{"changed": false, "comment": "Not booted from '{{ bash_argument(efi_current_path, before='', after='') }}'"}'
          fi
        {%- endcall %}

{{p}}{{ install_uki }}:
  file.copy:
    - name: {{ yaml_string(efi_current_path) }}
    - source:  {{ yaml_string(tmp_new_elf) }}
    - force: true
    - user: root
    - group: root
    - mode: 755
    - require:
      - cmd: {{p}}{{ create_uki }}
      - cmd: {{p}}{{ create_efi_backup }}

{{p}}{{ set_nextboot }}:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script("set_nextboot")) }}
    - stateful: True
    - require:
      - file: {{p}}{{ install_uki}}
    - env:
      - set_nextboot: {% call yaml_string() %}
          #!/bin/sh

          set -e

          if [ $(id -u) != 0 ]; then
              cat <<< "This must run as a privileged user" >&2
              exit 1
          fi

          if bootnext=$(efibootmgr -u | awk '/enroll_tpm$/ { if (match($1, /Boot([0-9]+)([^0-9]|$)/, m)) { print m[1] } }'); then
              if [[ "$bootnext" != "" ]]; then
                  if efibootmgr --bootnext "$bootnext" 2>&1 >/dev/null; then
                      echo '{"changed": true, "comment": "Set next boot to '"$bootnext"'. Reboot to complete the installation."}'
                      exit
                  else
                      echo '{"changed": false, "comment": "efibootmgr --bootnext failed"}'
                      exit 1
                  fi
              fi
          fi
          echo '{"changed": false, "comment": "Boot entry for enroll_tpm not found."}'
        {%- endcall %}

{{p}}{{ delete_temporary }}:
  file.absent:
    - name: {{ yaml_string(tmp_dir) }}
    - order: last

{{p}}Show nextboot information:
  cmd.run:
    - name: {{ yaml_string(format_exec_env_script("show_notification")) }}
    - env:
      - show_notification: {% call yaml_string() %}
          #!/bin/sh

          users=( $(for user in $(users); do echo "$user"; done | awk '!seen[$0]++ { print $0 }') )
          for user in "${users[@]}"; do
              sudo -u "$user" notify-send --urgency=critical --expire-time=0 "Reboot" "to use the new UKI"
          done
        {%- endcall %}
    - onchanges:
      - cmd: {{p}}{{ set_nextboot }}
    - require:
      - file: {{p}}{{ delete_temporary }}


{%- endif %}
