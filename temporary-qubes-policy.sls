# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- from "formatting.jinja" import salt_warning, systemd_escape, systemd_shell %}

{%- set p = "Temporary Qubes Policy - " %}
{%- set service_name = "temporary-qubes-policy.service" %}
{%- set policy_dir = "/etc/qubes/policy.d" %}
{%- macro service_name(name) -%}
  temporary-qubes-policy@{{ systemd_escape(name) }}.service
{%- endmacro %}

{%- if grains['id'] == 'dom0' %}
{{p}}service:
  file.managed:
    - name: /usr/lib/systemd/system/{{ service_name("") }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Create RAM based Qubes policy file %I
        After=basic.target
        
        [Service]
        Type=simple
        Environment="policy_name=%I"
        RemainAfterExit=true
        ExecStart={%- call systemd_shell() %}
          set -e
          if [ "$(dirname "$policy_name")" != "." ]; then
            echo "Invalid policy name $policy_name" >&2
            exit 1
          fi
          umask 077
          tmp_dir=$(mktemp -d)
          tmp_policy_file="$tmp_dir/policy"
          umask 022
          cat >"$tmp_policy_file" <<<"$default_policy_content"
          trap 'rm "$tmp_policy_file"; rmdir "$tmp_dir"' EXIT
          policy_file="{{ policy_dir }}/$policy_name.policy" 
          if [ ! -f "$policy_file" ]; then
            touch "$policy_file"
          fi
          mount -o bind "$tmp_policy_file" "$policy_file" 
          echo "$tmp_policy_file mounted to $policy_file"
        {%- endcall %}
        ExecStop={%- call systemd_shell() %}
          if [ "$(dirname "$policy_name")" != "." ]; then
            echo "Invalid policy name $policy_name" >&2
            echo "This should not be possible" >&2
            exit 1
          fi
          policy_file="{{ policy_dir }}/$policy_name.policy"
          while mountpoint --quiet "$policy_file"; do
            umount "$policy_file"
          done
          echo "$policy_file no longer mounted to RAM"
        {%- endcall %}
        
        [Install]
        WantedBy=qubes-qrexec-policy-daemon.service qubesd.service
  service.running:
    - name: {{ service_name("50-temporary") }}
    - enable: true
    - reload: true
    - require:
      - file: {{p}}service

{%- endif %}  
