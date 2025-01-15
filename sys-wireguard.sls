# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{% if grains['id'] == 'dom0' %}
  {%- from "dependents.jinja" import default_template %}
  {%- set wireguard_vms = namespace(name=salt['pillar.get']('sys-wireguard-qubes', []), template=[]) %}

  {%- for vm in wireguard_vms.name %}
    {%- set if_name = vm | replace('sys-wireguard-', '') | replace('-dvm', '') %}
    {%- set for_disposable = salt['pillar.get']('qvm:sys-wireguard-' + if_name + ':disposable', true) %}
{{ vm }} vm preferences:
  qvm.vm:
  - name: {{ vm }}
  - prefs:
    - label: red
    - template: {{ salt['pillar.get']('qvm:sys-wireguard-' + if_name + ':template', default_template()) }}
    - include-in-backups: false
    - class: AppVM
    {%- if for_disposable %}
    - template_for_dispvms: true
    - provides-network: false
    - netvm: none
    {%- else %}
    - template_for_dispvms: false
    - provides-network: true
    - netvm: {{ salt['pillar.get']('qvm:' + vm + ':netvm', 'sys-net') }}
    {%- endif %}

    {%- if for_disposable %}
{{ vm }} dvm preferences:
  qvm.vm:
  - name: {{ vm }}-dvm
  - prefs:
    - label: red
    - template: sys-wireguard-{{ if_name }}
    - include-in-backups: false
    - class: DispVM
    - provides-network: true
    - netvm: {{ salt['pillar.get']('qvm:' + vm + ':netvm', 'sys-net') }}
    {% endif %}

  {% endfor %}
{% else %}
  {% from "formatting.jinja" import salt_warning %}
  {%- set vm = grains['nodename'] %}
  {%- set if_name_guess = vm | replace('sys-wireguard-', '') | replace('-dvm', '') %}
  {%- set is_sysvm = (vm == 'sys-wireguard-' + if_name_guess) %}
  {%- set maybe_if_name = salt['pillar.get']('wg:if-name', None) %}
  {%- set if_name = maybe_if_name if maybe_if_name != None else if_name_guess %}
  {%- set allow_qube_forward = salt['pillar.get']('wg:forward', false) %}
  {%- set allow_forward_to_wan = salt['pillar.get']('wg:forward-to-wan', false) %}
  {%- set fw_mark = salt['pillar.get']('wg:fw-mark', 51820) %}
  {%- set route_table = salt['pillar.get']('wg:route-table', 123) %}
  {%- set peers = salt['pillar.get']('wg:peers', []) %}
  {%- set peers_with_lookup = peers|rejectattr('endpoint-name', 'undefined')|list() %}
  {%- set wg = salt['pillar.get']('wg', {}) %}
  {%- set resolve_boot_delay = salt['pillar.get']('wg:resolve-delay', '15s') %}
  {% macro wg_escape(key) -%}
    {{ key | replace('+', '') | replace('=', '') }}
  {%- endmacro %}

  {%- if is_sysvm or maybe_if_name != None %}
/rw/config/qubes-bind-dirs.d/50-wireguard.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
        binds+=( '/etc/wireguard/' )

/rw/usrlocal/lib/systemd/system/wg-resolve@.service:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Add dns lookup to peer
        After=wg-quick@{{ if_name }}.service
        Requires=wg-quick@{{ if_name }}.service

        [Service]
        Type=oneshot
        ExecStartPre=/bin/bash -c 'transfer=$(wg show "$${wg_if_name}" latest-handshakes | grep ^"$${wg_peer}") ; vpn_receiced=$(awk \'{ print $2 }\' <<< "$transfer") ; vpn_sent=$(awk \'{ print $3 }\' <<< "$transfer") ; [[ $vpn_receiced -eq 0 ]] && [[ $vpn_sent -ne 0 ]]'
        ExecCondition=/bin/bash -c 'latest_handshake=$(wg show {{ if_name }} latest-handshakes | grep ^"$${wg_peer}" | awk \'{ print $2 }\') ; [[ $latest_handshake -eq 0 ]] || [[ $(($(date +%%s)-$latest_handshake)) -gt 180 ]]'
        ExecStart=/bin/bash -c 'wg set "$wg_if_name" peer "$wg_peer" endpoint "$wg_endpoint"'
        RemainAfterExit=yes
        Restart=on-failure
        RestartSec=5s

        [Install]
        WantedBy=multi-user.target

      {% for peer in peers_with_lookup %}
{% set override_file = '/rw/usrlocal/lib/systemd/system/wg-resolve@' + if_name + '-' + wg_escape(peer['public-key']) + '.service.d/environment.conf' %}
{{ override_file }}:
  file.managed:
    - user: root
    - group: root
    - mode: 440
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Service]
        Environment='wg_if_name={{ if_name }}' 'wg_peer={{ peer['public-key'] }}' 'wg_endpoint={{ peer['endpoint-name'] }}'
      {% endfor %}

/rw/usrlocal/lib/systemd/system/wg-resolve.service:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Add dns lookup to peer
        After=wg-quick@{{ if_name }}.service
        {%- for peer in peers_with_lookup -%}
          {{ ' ' }} wg-resolve@{{ if_name }}-{{ wg_escape(peer['public-key']) }}.service
        {%- endfor %}
        Requires=wg-quick@{{ if_name }}.service
        {%- for peer in peers_with_lookup -%}
          {{ ' ' }} wg-resolve@{{ if_name }}-{{ wg_escape(peer['public-key']) }}.service
        {%- endfor %}

        [Service]
        Type=oneshot
        ExecStart=/bin/true
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target

    {% if (peers_with_lookup | length) > 0 %}
/rw/usrlocal/lib/systemd/system/wg-resolve.timer:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: false
    - contents: |
        # {{ salt_warning }}
        [Timer]
        OnBootSec={{ resolve_boot_delay }}
    {%- endif %}

/rw/bind-dirs/etc/wireguard/{{ if_name }}.conf:
  file.managed:
    - user: root
    - group: systemd-network
    - mode: 440
    - makedirs: true
    - show_changes: false
    - replace: true
    - dir_mode: 550
    - contents: |
        # {{ salt_warning }}
        [Interface]
        Address = {{ wg['address'] }}
        PrivateKey = {{ wg['private-key'] }}
    {%- if wg['port'] is defined %}
        Port = wg['port']
    {%- endif %}
        FwMark = {{ fw_mark }}
        Table = {{ route_table }}
        PostUp = ip rule add not fwmark {{ fw_mark }} table {{ route_table }}
        {%- if allow_forward_to_wan or allow_qube_forward %} ; ip rule add iif %i table main {%- endif %}
        PreDown = ip rule delete not fwmark {{ fw_mark }} table {{ route_table }}
        {%- if allow_forward_to_wan or allow_qube_forward %}  ; ip rule delete iif %i table main {%- endif %}
    {%- if wg['dns'] is defined %}
        DNS = {{ wg['dns'] }}
    {%- endif %}
    {%- if wg['mtu'] is defined %}
        MTU = {{ wg['mtu'] }}
    {%- endif %}

    {%- for peer in peers %}

        [Peer]
        PublicKey = {{ peer['public-key'] }}
      {%- if peer['preshared-key'] is defined %}
        PresharedKey = {{ peer['preshared-key'] }}
      {%- endif %}
      {%- if peer['allowed-ips'] is defined %}
        AllowedIPs = {{ peer['allowed-ips'] }}
      {%- endif %}
      {%- if peer['endpoint'] is defined %}
        Endpoint = {{ peer['endpoint'] }}
      {%- endif %}
      {%- if peer['keep-alive'] is defined %}
        PersistentKeepAlive = {{ peer['keep-alive'] }}
      {%- endif %}
    {%- endfor %}

/rw/config/qubes-firewall.d/10-wireguard.nft:
  file.managed:
    - user: root
    - group: systemd-network
    - mode: 550
    - dir_mode: 555
    - makedirs: true
    - replace: true
    - contents: |
         #!/usr/sbin/nft -f
         # {{ salt_warning }}
         table inet wireguard_tunnel
         delete table inet wireguard_tunnel
         table inet wireguard_tunnel {
           chain only_forward_with_wireguard {
             type filter hook forward priority filter;
             iifname != "{{ if_name }}" oifname != "{{ if_name }}" return
    {%- if allow_forward_to_wan %}
             # Forward traffic from the VPN
             iifname "{{ if_name }}" ct direction original counter oifgroup 1 counter accept
    {%- endif %}
    {%- if allow_qube_forward %}
             iifname "{{ if_name }}" ct direction reply counter oifgroup 2 counter accept
             oifname "{{ if_name }}" counter accept
    {%- endif %}
             counter drop
           }
    {%- if allow_forward_to_wan %}
           chain nat_wan_forward {
             type nat hook postrouting priority srcnat;
             oifgroup 1 masquerade
           }
    {%- endif %}
         }

/rw/config/rc.local.d/20-wireguard.rc:
  file.managed:
    - user: root
    - group: root
    - mode: 555
    - makedirs: true
    - dir_mode: 555
    - replace: true
    - contents: |
        #!/bin/bash
        # {{ salt_warning }}
        systemctl enable --now wg-quick@{{ if_name }}.service
    {%- if peers_with_lookup|length() > 0 %}
        systemctl enable --now wg-resolve.timer
    {%- endif %}
  {%- endif %}
{% endif %}
