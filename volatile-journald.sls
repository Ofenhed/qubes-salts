# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning %}

{%- set vm_type = salt['pillar.get']('qubes:type') %}
{%- set p = "Volatile journald - " %}

{%- if vm_type == 'template' %}
{%- set task_name = "/var/log/journal tmpfs mount" %}

{{p}}{{ task_name }}:
  file.managed:
    - name: /usr/lib/systemd/system/var-log-journal.mount
    - user: root
    - group: root
    - makedirs: true
    - dir_mode: 755
    - mode: 444
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Before=systemd-journal-flush.service
        After=qubes-bind-dirs.service
        Wants=qubes-bind-dirs.service
        DefaultDependencies=no
        ConditionPathIsMountPoint=!/var/log/journal

        [Mount]
        What=tmpfs
        Where=/var/log/journal
        Type=tmpfs
        
        [Install]
        WantedBy=systemd-journal-flush.service
  service.enabled:
    - name: var-log-journal.mount
    - require:
      - file: {{p}}{{ task_name }}

{%- elif vm_type == 'app' %}
{{p}}Persistent logs:
  file.managed:
    - name: /rw/config/qubes-bind-dirs.d/10-persistent-journal.conf
    - user: root
    - group: root
    - makedirs: true
    - dir_mode: 755
    - mode: 444
    - contents: |
        # {{ salt_warning }}
        bind+=( /var/log/journal )
  
{%- endif %}
