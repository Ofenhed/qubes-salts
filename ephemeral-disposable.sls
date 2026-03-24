{% if grains['id'] == 'dom0' %}
  {%- from "formatting.jinja" import yaml_string, format_exec_env_script %}
Set ephemeral state for all lvm disks:
  cmd.run:
    - shell: /bin/bash
    - name: |-
        for pool in $(qvm-pool -l | tail -n +2 | awk '/\slvm_thin$/{ print $1 }'); do
          qvm-pool --set "$pool" -o ephemeral_volatile=True
        done

Set individual volumes to ephemeral or readonly:
  cmd.run:
    - shell: /bin/bash
    - failhard: False
    - name: {{ yaml_string(format_exec_env_script('set_volatile')) }}
    - env:
      - set_volatile: {% call yaml_string() -%}
          function handle_vm() {
            vm="$1"
            if [ $(qvm-volume info "$vm:root" rw) == "False" ] && \
               [ $(qvm-volume info "$vm:volatile" ephemeral) == "True" ]; then
               return 0
            fi
            if ! (qvm-volume config "$vm:root" rw False 2>/dev/null &&
                  qvm-volume config "$vm:volatile" ephemeral True 2>/dev/null); then
              if qvm-check --running --quiet "$vm"; then
                echo "Could not set volatile disk for running vm $vm"
              else
                echo "Could not set volatile disk for $vm"
              fi >&2
              return 1
            fi
          }
          vms=( $(qvm-ls --raw-list --internal n --class DispVM --prefs auto_cleanup=False) $(qvm-ls --raw-list --internal n --prefs template_for_dispvms=True) )
          workers=()
          for vm in "${vms[@]}"; do
            handle_vm "$vm" &
            workers+=( "$!" )
          done
          for worker in "${workers[@]}"; do
            if ! wait "$worker"; then
              wait
              exit 1
            fi
          done
        {%- endcall %}

{% endif %}
