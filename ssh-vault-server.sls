# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

/rw/home/user/.config/autostart/ssh-add.desktop:
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

/rw/config/rc.local.d/copy-qubes-rpc.rc:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        cp /rw/config/qubes-rpc/qubes.SshAgent /etc/qubes-rpc/

/rw/config/qubes-rpc/qubes.SshAgent:
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
