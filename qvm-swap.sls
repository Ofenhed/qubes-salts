# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning, systemd_shell %}
{%- set p = "VM swap settings - " %}

{% if salt['pillar.get']('qubes:type') == 'template' %}
{%- set create_service = p + "Add zswap activation service" %}
{{ create_service }}:
  file.managed:
    - name: /usr/lib/systemd/system/zswap.service
    - user: root
    - group: root
    - mode: 444
    - contents: |
        # {{ salt_warning }}
        [Unit]
        BindsTo=swap.target
        After=swap.target

        [Service]
        ExecStart={% call systemd_shell() %}
          cat >/sys/module/zswap/parameters/compressor <<<lz4
          cat >/sys/module/zswap/parameters/shrinker_enabled <<<1
          cat >/sys/module/zswap/parameters/enabled <<<1
        {%- endcall %}
        ExecStop={% call systemd_shell() %}
          cat >/sys/module/zswap/parameters/shrinker_enabled <<<0
          cat >/sys/module/zswap/parameters/enabled <<<0
        {%- endcall %}
        RemainAfterExit=yes

        [Install]
        WantedBy=swap.target
  service.enabled:
    - name: zswap.service
    - require:
      - file: {{ create_service }}
        
{{p}}Add swap discard:
  file.replace:
    - name: /etc/fstab
    - append_if_not_found: false
    - pattern: |-
        ^(?P<before>[^\s]+\s+(swap|none)\s+swap\s+(?:(?(3),)(?!discard)([^\s,]+))+)(?P<after>\s+\d+\s+\d+\s*)$
    - repl: |-
        \g<before>,discard\g<after>
{% endif %}

