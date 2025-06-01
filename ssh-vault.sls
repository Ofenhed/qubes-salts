# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning, qube_name %}
{%- set p = "ssh-vault" %}
{%- set policy_file = "/etc/qubes/policy.d/50-ssh.policy" %}
{%- set vm_type = salt['pillar.get']('qubes:type') %}

{%- if grains['id'] == 'dom0' %}
{{ p }}{{ policy_file }}:
  file.managed:
    - name: {{ policy_file }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
  {%- set vms = salt['pillar.get']('qvm', {}) %}
  {%- set tab = '\t' %}
  {%- for (qvm_entry, attributes) in vms.items() %}
    {%- set ssh_vault = attributes['ssh-vault'] %}
    {%- if ssh_vault is defined %}
      {%- set vault_name = qube_name(ssh_vault) %}
        qubes.SshAgent {{- tab + "*" + tab + qube_name(qvm_entry) + tab + vault_name + tab + "allow target=" + vault_name }}
    {%- endif %}
  {%- endfor %}

{%- elif vm_type == 'template' %}
add_ssh_askpass:
  pkg.installed:
    - pkgs:
  {%- if grains['os_family'] == 'Debian' %}
      - ssh-askpass-gnome
  {%- elif grains['os_family'] == 'RedHat' %}
      - openssh-askpass
  {%- endif %}

{%- elif vm_type == 'app' %}
  {%- set vault_vm = salt['pillar.get']('qvm:' + grains['id'] + ':ssh-vault', none) %}
  {%- set state = namespace(is_server=false, is_client=vault_vm is not none, vault_vm = vault_vm) %}
  {%- set pillar_qvm = salt['pillar.get']('qvm', {}) %}
  {%- for (vm, options) in pillar_qvm.items() %}
    {%- if (not state.is_server) and 'ssh-vault' in options and options['ssh-vault'] == grains['id'] %}
      {%- set state.is_server = true %}
    {%- endif %}
  {%- endfor %}

/rw/home/user/.config/autostart/ssh-add.desktop:
  {%- if not state.is_server %}
  file.absent: []
  {%- else %}
  file.managed:
    - user: user
    - group: user
    - mode: 600
    - makedirs: true
    - dir_mode: 700
    - replace: false
    - contents: |
        [Desktop Entry]
        Name=ssh-add
        Exec=ssh-add -c
        Type=Application
  {%- endif %}

/rw/config/rc.local.d/copy-qubes-rpc.rc:
  {%- if not state.is_server %}
  file.absent: []
  {%- else %}
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        ln -s /rw/bind-dirs/etc/qubes-rpc/qubes.SshAgent /etc/qubes-rpc/
  {%- endif %}

/rw/bind-dirs/etc/qubes-rpc/qubes.SshAgent:
  {%- if not state.is_server %}
  file.absent: []
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
        # Qubes App Split SSH Script

        # safeguard - Qubes notification bubble
        notify-send "[$(qubesdb-read /name)] SSH agent access from: $QREXEC_REMOTE_DOMAIN"

        # SSH connection
        socat - "UNIX-CONNECT:$SSH_AUTH_SOCK"
  {%- endif %}

/rw/config/rc.local.d/ssh-agent.rc:
  {%- if not state.is_client %}
  file.absent: []
  {%- else %}
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        # SPLIT SSH CONFIGURATION
        # replace "vault" with your AppVM name which stores the ssh private key(s)
        SSH_VAULT_VM="{{ state.vault_vm }}"

        if [ "$SSH_VAULT_VM" != "" ]; then
          export SSH_SOCK="/home/user/.SSH_AGENT_$SSH_VAULT_VM"
          rm -f "$SSH_SOCK"
          sudo -u user /bin/sh -c "umask 177 && exec socat 'UNIX-LISTEN:$SSH_SOCK,fork' 'EXEC:qrexec-client-vm $SSH_VAULT_VM qubes.SshAgent'" &
        fi
  {% endif %}

bash_rc_split_ssh:
  file.blockreplace:
    - name: /rw/home/user/.bashrc
    - marker_start: "# SPLIT SSH CONFIGURATION >>>"
    - marker_end: "# <<< SPLIT SSH CONFIGURATION"
    - show_changes: True
    - backup: '.bak'
  {% if state.is_client %}
    - append_if_not_found: True
    - content: |
        # replace "vault" with your AppVM name which stores the ssh private key(s)
        SSH_VAULT_VM="{{ vault_vm }}"

        if [ "$SSH_VAULT_VM" != "" ]; then
          export SSH_AUTH_SOCK="/home/user/.SSH_AGENT_$SSH_VAULT_VM"
        fi
  {% else %}
    - append_if_not_found: False
    - content: ""
  {% endif %}
{%- endif %}
