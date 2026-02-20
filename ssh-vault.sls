# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning, qube_name, yaml_string %}
{%- from "ordering.jinja" import user_package_install %}
{%- set p = "SSH Vault - " %}
{%- set policy_file = "/etc/qubes/policy.d/50-ssh.policy" %}
{%- set vm_type = salt['pillar.get']('qubes:type') %}

{%- if grains['id'] == 'dom0' %}
{{p}}{{ policy_file }}:
  file.managed:
    - name: {{ policy_file }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
  {%- set allowed_vms = salt['pillar.get']('user:ssh-vault:allow', {}) %}
  {%- set maybe_allowed_vms = salt['pillar.get']('user:ssh-vault:ask', {}) %}
  {%- set tab = '\t' %}
  {%- macro write_entry(qvm_name, vault_name, action) %}
     {%- set target = {'allow': 'target', 'ask': 'default_target'} %}
     {%- set e_vault_name = qube_name(vault_name) %}
        qubes.SshAgent {{- tab + "*" + tab + qube_name(qvm_name) + tab + e_vault_name + tab + action + " " + target[action] + "=" + e_vault_name }}
  {%- endmacro %}
  {%- for (qvm_entry, vault) in allowed_vms.items() %}
    {{- write_entry(qvm_entry, vault, "allow") }}
  {%- endfor %}
  {%- for (qvm_entry, vault) in maybe_allowed_vms.items() %}
    {{- write_entry(qvm_entry, vault, "ask") }}
  {%- endfor %}

{%- elif vm_type == 'template' %}
{{p}}Add ssh-askpass:
  pkg.installed:
    - order: {{ user_package_install }}
    - pkgs:
  {%- if grains['os_family'] == 'Debian' %}
      - ssh-askpass-gnome
  {%- elif grains['os_family'] == 'RedHat' %}
      - openssh-askpass
  {%- endif %}

{%- elif vm_type == 'app' %}
  {%- set vault_table = salt['pillar.get']('user:ssh-vault', {}) %}
  {%- set vault_allowed = vault_table['allow']|d({}) %}
  {%- set vault_maybe_allowed = vault_table['ask']|d({}) %}
  {%- set vault_vm = (vault_allowed[grains['id']]|d(none)) or (vault_maybe_allowed[grains['id']]|d(none)) %}
  {%- set state = namespace(is_server=false, is_client=vault_vm is not none, vault_vm = vault_vm) %}
  {%- for (vm, vm_vault) in (vault_allowed|items|list) + (vault_maybe_allowed|items|list) %}
    {%- if (not state.is_server) and vm_vault == grains['id'] %}
      {%- set state.is_server = true %}
    {%- endif %}
  {%- endfor %}

{{p}}Autostart ssh-add:
  {%- if not state.is_server %}
  file.absent:
  {%- else %}
  file.managed:
    - user: user
    - group: user
    - mode: 600
    - makedirs: true
    - dir_mode: 700
    - replace: false
    - contents: |
        # {{ salt_warning }}
        [Desktop Entry]
        Name=ssh-add
        Exec=ssh-add -c
        Type=Application
  {%- endif %}
    - name: /rw/home/user/.config/autostart/ssh-add.desktop

{{p}}Install qubes-rpc service qubes.SshAgent on boot:
  {%- if not state.is_server %}
  file.absent:
  {%- else %}
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}
        ln -s /rw/bind-dirs/etc/qubes-rpc/qubes.SshAgent /etc/qubes-rpc/
  {%- endif %}
    - name: /rw/config/rc.local.d/90-copy-qubes-rpc.rc

{{p}}Create qubes-rpc service qubes.SshAgent:
  {%- if not state.is_server %}
  file.absent:
  {%- else %}
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}
        # Qubes App Split SSH Script

        # safeguard - Qubes notification bubble
        notify-send "[$(qubesdb-read /name)] SSH agent access from: $QREXEC_REMOTE_DOMAIN"

        # SSH connection
        socat - "UNIX-CONNECT:$SSH_AUTH_SOCK"
  {%- endif %}
    - name: /rw/bind-dirs/etc/qubes-rpc/qubes.SshAgent

{{p}}Autostart ssh-agent:
  {%- if not state.is_client %}
  file.absent:
  {%- else %}
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}
        # SPLIT SSH CONFIGURATION
        # replace "vault" with your AppVM name which stores the ssh private key(s)
        SSH_VAULT_VM="{{ state.vault_vm }}"

        if [ "$SSH_VAULT_VM" != "" ]; then
          export SSH_SOCK="/var/run/user/1000/.SSH_AGENT_$SSH_VAULT_VM"
          rm -f "$SSH_SOCK"
          pkexec --user user env SSH_VAULT_VM="$SSH_VAULT_VM" SSH_SOCK="$SSH_SOCK"  /bin/sh -c 'umask 177 && exec socat "UNIX-LISTEN:$SSH_SOCK,fork" "EXEC:qrexec-client-vm $SSH_VAULT_VM qubes.SshAgent" &'
        fi
  {% endif %}
    - name: /rw/config/rc.local.d/89-ssh-agent.rc

{{p}}bashrc split SSH configuration:
  {%- set start_marker = "# SPLIT SSH CONFIGURATION >>>" %}
  {%- set end_marker =  "# <<< SPLIT SSH CONFIGURATION"%}
  file.blockreplace:
    - name: /rw/home/user/.bashrc
    - marker_start: {{ yaml_string(start_marker) }}
    - marker_end: {{ yaml_string(end_marker) }}
    - show_changes: True
    - backup: '.bak'
  {%- if state.is_client %}
    - append_if_not_found: True
    - content: |
        # replace "vault" with your AppVM name which stores the ssh private key(s)
        SSH_VAULT_VM="{{ state.vault_vm }}"

        if [ "$SSH_VAULT_VM" != "" ]; then
          export SSH_AUTH_SOCK="/var/run/user/1000/.SSH_AGENT_$SSH_VAULT_VM"
        fi
  {%- else %}
    - append_if_not_found: False
    - content: ""
  {%- endif %}
{%- endif %}
