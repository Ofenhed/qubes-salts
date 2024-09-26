# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% set vault_vm = salt['pillar.get']('qvm:' + grains['nodename'] + ':ssh-vault', '') %}
{% if vault_vm == "" %}
show-personal-info:
  test.show_notification:
    - name: "No vault defined, see ssh-vault-client.sls"
    - text: |
        Create the file /srv/pillar/user/ssh-vault-{{ grains['nodename'] }}.top with the following content:
        > base:
        >   dom0:
        >     - match: nodegroup
        >     - user.ssh-vault
        >   {{ grains['nodename'] }}:
        >     - user.ssh-vault
        Create the file /srv/pillar/user/ssh-vault-{{ grains['nodename'] }}.sls with the following content:
        > qvm:
        >     {{ grains['nodename'] }}:
        >         ssh-vault: "vault" # Replace this with the name of the vault 
{% endif %}

/rw/config/rc.local.d/ssh-agent.rc:
{% if vault_vm != "" %}
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
        SSH_VAULT_VM="{{ vault_vm }}"

        if [ "$SSH_VAULT_VM" != "" ]; then
          export SSH_SOCK="/home/user/.SSH_AGENT_$SSH_VAULT_VM"
          rm -f "$SSH_SOCK"
          sudo -u user /bin/sh -c "umask 177 && exec socat 'UNIX-LISTEN:$SSH_SOCK,fork' 'EXEC:qrexec-client-vm $SSH_VAULT_VM qubes.SshAgent'" &
        fi
{% else %}
  file.absent: []
{% endif %}

bash_rc_split_ssh:
  file.blockreplace:
    - name: /rw/home/user/.bashrc
    - marker_start: "# SPLIT SSH CONFIGURATION >>>"
    - marker_end: "# <<< SPLIT SSH CONFIGURATION"
    - append_if_not_found: True
    - show_changes: True
    - backup: '.bak'
{% if vault_vm != "" %}
    - content: |
        # replace "vault" with your AppVM name which stores the ssh private key(s)
        SSH_VAULT_VM="{{ vault_vm }}"

        if [ "$SSH_VAULT_VM" != "" ]; then
          export SSH_AUTH_SOCK="/home/user/.SSH_AGENT_$SSH_VAULT_VM"
        fi
{% else %}
    - content: ""
{% endif %}
