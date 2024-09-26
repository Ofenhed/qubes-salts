# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% from "formatting.jinja" import salt_warning %}

{% set p = "Qubes tweaks - " %}

{% if grains['id'] == 'dom0' %}
{{p}} Appmenu that isn't affected by the mouse:
  file.managed:
    - name: /usr/local/bin/qubes-app-menu-nomouse
    - user: root
    - group: root
    - mode: 755
    - makedirs: false
    - replace: true
    - contents: |
        #!/bin/sh
        # {{ salt_warning }}

        xdotool mousemove_relative 0 -10000
        exec qubes-app-menu "$@"

{{p}} do not wait for qubes to start before multi-user:
  file.managed:
    - name: /usr/lib/systemd/system/qubes-vm@.service.d/dont-wait-for-completion.conf
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir mode: 755
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Service]
        Type=exec
{% endif %}
