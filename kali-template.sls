{%- from "formatting.jinja" import yaml_format_exec_env_script, salt_warning %}
{%- set p = 'Create Kali VM - ' %}

{%- set kali_vm_name = "kali" %}
{%- set kali_install_working_dir = "/run/user/0/kali-template" %}

{%- set states = namespace(check_exists = p + "Check if VM aleady exist",
                           create_vm = p + "Create kali vm",
                           fetch_keys = p + "Fetch kali keys",
                           install_kali_source = p + "Install kali source",
                           remove_debian_source = p + "Remove debian source",
                           update_repo_data = p + "Update repo data",
                           upgrade_packages = p + "Upgrade packages",
                           upgrade_dist = p + "Upgrade dist",
                           patch_dpkg_status = p + "Patch dpkg status",
                           install_kali = p + "Install kali linux",
                           create_working_dir = p + "Working directory",
                           update_kali_menu = p + "Update kali menu") %}

{%- if grains['id'] == 'dom0' %}
{{ states.check_exists }}:
  cmd.run:
    - name: {{ yaml_format_exec_env_script("check_kali_template_installed") }}
    - env:
      - check_kali_template_installed: |
          qvm-ls --no-spinner "{{ kali_vm_name }}" 2>/dev/null >/dev/null
    - failhard: false

{{ states.create_vm }}:
  cmd.run:
    - onfail:
      - cmd: {{ states.check_exists }}
    - name: {{ yaml_format_exec_env_script("clone_debian_to_kali") }}
    - env:
      - clone_debian_to_kali: |
          debian_source=( $(qvm-ls debian\* --fields NAME --raw-list --class TemplateVM) )
          if [ {{'${#debian_source[@]}'}} -ne 1 ]; then
              echo "Could not chose a debian source template"
              exit 1
          fi
          set -e
          qvm-clone "$debian_source" "{{ kali_vm_name }}"
          qvm-volume resize "{{ kali_vm_name }}:root" 35GiB

{{ states.fetch_keys }}:
  cmd.run:
    - onchange:
      - cmd: {{ states.create_vm }}
    - name: {{ yaml_format_exec_env_script("copy_kali_keys") }}
    - env:
      - copy_kali_keys: |
          echo "Fetching kali keys"
          qvm-run --pass-io --dispvm "$(qubes-prefs default_dispvm)" "curl -L https://archive.kali.org/archive-key.asc" | qvm-run --user root --pass-io "{{ kali_vm_name }}" -- bash -c "cat > /etc/apt/trusted.gpg.d/kali-archive-key.asc"

{%- elif grains['id'] == kali_vm_name %}

{{ states.install_kali_source }}:
  file.managed:
    - name: /etc/apt/sources.list.d/kali.list
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
        deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/kali-archive-key.asc] http://http.kali.org/kali kali-rolling main non-free contrib non-free-firmware

{{ states.remove_debian_source }}:
  file.comment:
    - name: /etc/apt/sources.list
    - regex: |
        ^\s*[^\s#]
    - char: '#'
    - backup: false
    - ignore_missing: true

{{ states.update_repo_data }}:
  cmd.run:
    - require:
      - file: {{ states.install_kali_source }}
      - file: {{ states.remove_debian_source }}
    - name: apt-get update

{{ states.upgrade_packages }}:
  cmd.run:
    - require:
      - cmd: {{ states.update_repo_data }}
    - name: apt-get -y upgrade

{{ states.upgrade_dist }}:
  cmd.run:
    - require:
      - cmd: {{ states.upgrade_packages }}
    - name: apt-get -y dist-upgrade

{{ states.create_working_dir }}:
  file.directory:
    - name: {{ kali_install_working_dir }}
    - user: root
    - group: root

{{ states.patch_dpkg_status }}:
  cmd.run:
    - require:
      - cmd: {{ states.upgrade_dist }}
      - file: {{ states.create_working_dir }}
    - name: {{ yaml_format_exec_env_script("patch_dpkg_status") }}
    - env:
      - awk_script: |
          $1 == "Depends:" {
              sub(/python3:any\s*\((<<\s*3\.([0-9]|1[1-3])|>[>=]\s*3\.(([0-9]|1[1-3])(\.[0-9]+)?~))\)/, "python3:any", $0);
          };
          1
      - patch_dpkg_status: |
          set -e
          awk "$awk_script" </var/lib/dpkg/status >"{{ kali_install_working_dir }}"/dpkg_status
          cat <"{{ kali_install_working_dir }}"/dpkg_status >/var/lib/dpkg/status
          rm "{{ kali_install_working_dir }}"/dpkg_status

{{ states.install_kali }}:
  cmd.run:
    - require:
      - cmd: {{ states.patch_dpkg_status }}
      - cmd: {{ states.upgrade_dist }}
      - cmd: {{ states.upgrade_packages }}
      - cmd: {{ states.update_repo_data }}
    - name: apt-get install -y kali-linux-headless kali-menu

{{ states.update_kali_menu }}:
  cmd.run:
    - name: /usr/share/kali-menu/update-kali-menu
    - order: last

{%- endif %}
