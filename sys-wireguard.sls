# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- set qubes_dns_servers = ['10.139.1.1', '10.139.1.2'] %}
{%- set vm_type = salt['pillar.get']('qubes:type') %}
{%- set p = "Wireguard - " %}
{%- macro vm_task_name(vm) %}
  {{- p + vm }} vm definition
{%- endmacro %}

{%- if grains['id'] == 'dom0' %}
  {%- from "dependents.jinja" import default_template %}
  {%- set wireguard_vms = namespace(name=salt['pillar.get']('sys-wireguard-qubes', []), template=[]) %}

  {%- for vm in wireguard_vms.name %}
    {%- set if_name = vm | replace('sys-wireguard-', '') | replace('-dvm', '') %}
    {%- set for_disposable = salt['pillar.get']('qvm:sys-wireguard-' + if_name + ':disposable', true) %}
    {%- set vm_name = vm if not for_disposable else vm + '-dvm' %}
{{ vm_task_name(vm_name) }}:
  qvm.vm:
  - name: {{ vm_name }}
  - actions:
    - present
    - prefs
{%- set vm_preferences = {
    'label': 'red',
    'template': salt['pillar.get']('qvm:sys-wireguard-' + if_name + ':template', default_template()),
    'include-in-backups': 'false',
    'maxmem': 0,
    'memory': 512,
    'vcpus': 1,
    'class': 'AppVM'
} %}

  - present:
    {%- for key, value in vm_preferences.items() %}
    - {{ key }}: {{ value }}
    {%- endfor %}
  - prefs:
    - include-in-backups: false
    {%- for key, value in vm_preferences.items() %}
    - {{ key }}: {{ value }}
    {%- endfor %}

    {%- if not for_disposable %}
    - template_for_dispvms: false
    {%- else %}
    - template_for_dispvms: true
    - provides-network: false
    - netvm: none

  {%- set netvm = salt['pillar.get']('qvm:' + vm + ':netvm', 'sys-net') %}

  {%- if netvm not in wireguard_vms.name %}
{{ vm_task_name(netvm) }}:
  qvm.exists:
    - name: {{ netvm }}
  {%- endif %}

{%- set dvm_preferences = {
    'label': 'red',
    'template': 'sys-wireguard-' + if_name + '-dvm',
    'include-in-backups': 'false',
    'maxmem': 0,
    'memory': 512,
    'vcpus': 1,
    'class': 'DispVM'
} %}
{{ vm_task_name(vm) }}:
  qvm.vm:
  - name: {{ vm }}
  - require:
    - qvm: {{ vm_task_name(netvm) }}
    - qvm: {{ vm_task_name(dvm_preferences['template']) }}
  - actions:
    - present
    - prefs

  - present:
    {%- for key, value in dvm_preferences.items() %}
    - {{ key }}: {{ value }}
    {%- endfor %}
  - prefs:
    - include-in-backups: false
    {%- for key, value in dvm_preferences.items() %}
    - {{ key }}: {{ value }}
    {%- endfor %}
    {%- endif %}
    - netvm: {{ salt['pillar.get']('qvm:' + vm + ':netvm', 'sys-net') }}
    - provides-network: true
    - features:
        - enable:
            - qubes-firewall

  {%- endfor %}
{%- elif vm_type == 'template' %}
{%- from "ordering.jinja" import user_package_install %}

{{p}}wireguard-tools:
  pkg.installed:
    - order: {{ user_package_install }}
    - pkgs:
      - wireguard-tools

{{p}}/etc/wireguard:
  file.directory:
    - name: /etc/wireguard
    - user: root
    - group: systemd-network
    - mode: 550

{%- elif vm_type == 'app' %}
  {%- from "formatting.jinja" import salt_warning, systemd_shell %}
  {%- set vm = grains['nodename'] %}
  {%- set if_name_guess = vm | replace('sys-wireguard-', '') | replace('-dvm', '') %}
  {%- set is_sysvm = (vm == 'sys-wireguard-' + if_name_guess or vm == 'sys-wireguard-' + if_name_guess + '-dvm') %}
  {%- set maybe_if_name = salt['pillar.get']('wg:if-name', None) %}
  {%- set if_name = maybe_if_name if maybe_if_name != None else if_name_guess %}
  {%- set allow_qube_forward = salt['pillar.get']('wg:forward', false) %}
  {%- set allow_forward_to_wan = salt['pillar.get']('wg:forward-to-wan', false) %}
  {%- set redirect_dns = salt['pillar.get']('wg:redirect-dns', true) %}
  {%- set fw_mark = salt['pillar.get']('wg:fw-mark', 51820) %}
  {%- set dns_mark = salt['pillar.get']('wg:dns-mark', 0x515320) %}
  {%- set route_table = salt['pillar.get']('wg:route-table', 123) %}
  {%- set peers = salt['pillar.get']('wg:peers', []) %}
  {%- set peers_with_lookup = peers|rejectattr('endpoint-name', 'undefined')|list() %}
  {%- set wg = salt['pillar.get']('wg', {}) %}
  {%- set resolve_boot_delay = salt['pillar.get']('wg:resolve-delay', '30s') %}
  {%- macro wg_escape(key) %}
    {{- key | replace('+', '') | replace('=', '') }}
  {%- endmacro %}

  {%- if is_sysvm or maybe_if_name != None %}
{{p}}bind dirs config:
  file.managed:
    - name: /rw/config/qubes-bind-dirs.d/50-wireguard.conf
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
        binds+=( '/etc/wireguard/' )

{{p}}Resolve service instance:
  file.managed:
    - name: /rw/usrlocal/lib/systemd/system/wg-resolve@.service
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
        StopWhenUnneeded=yes

        [Service]
        Type=oneshot
        {#
        ExecStartPre={%- call systemd_shell() %}
          transfer=$(wg show "$${wg_if_name}" latest-handshakes | grep ^"$${wg_peer}")
          vpn_receiced=$(awk '{ print $2 }' <<< "$transfer")
          vpn_sent=$(awk '{ print $3 }' <<< "$transfer")
          echo "Sent $vpn_sent, received $vpn_receiced"
          [[ $vpn_receiced -eq 0 ]] && [[ $vpn_sent -ne 0 ]]
        {%- endcall %}
        #}
        ExecStartPre={%- call systemd_shell() %}
          resolve_uid=$(id -u systemd-resolve)
          ip rule add uidrange "$resolve_uid-$resolve_uid" lookup main
        {%- endcall %}
        ExecStopPost=-{%- call systemd_shell() %}
          resolve_uid=$(id -u systemd-resolve)
          ip rule del uidrange "$resolve_uid-$resolve_uid" lookup main
        {%- endcall %}
        ExecCondition={%- call systemd_shell() %}
          latest_handshake=$(wg show {{ if_name }} latest-handshakes | awk -v "wg_peer=$${wg_peer}" '$1 == wg_peer { print $2; exit }')
          [[ $latest_handshake -eq 0 ]] || [[ $(($(date +%%s)-$latest_handshake)) -gt 180 ]]
        {%- endcall %}
        ExecStart={%- call systemd_shell() %}
          wg set "$wg_if_name" peer "$wg_peer" endpoint "$wg_endpoint"
        {%- endcall %}
        RemainAfterExit=yes
        Restart=on-failure
        RestartSec=5s

        [Install]
        WantedBy=multi-user.target

      {%- for peer in peers_with_lookup %}
{%- set override_file = '/rw/usrlocal/lib/systemd/system/wg-resolve@' + if_name + '-' + wg_escape(peer['public-key']) + '.service.d/environment.conf' %}
{{p}}Resolve override file:
  file.managed:
    - name: {{ override_file }}
    - user: root
    - group: root
    - mode: 440
    - makedirs: true
    - dir_mode: 755
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Service]
        Environment="wg_if_name={{ if_name }}"
        Environment="wg_peer={{ peer['public-key'] }}"
        Environment="wg_endpoint={{ peer['endpoint-name'] }}"
        Environment="wg_original_endpoint={{ peer['endpoint'] }}"
      {%- endfor %}

{{p}}Resolve service:
  file.managed:
    - name: /rw/usrlocal/lib/systemd/system/wg-resolve.service
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
        StopWhenUnneeded=yes

        [Service]
        Type=oneshot
        ExecStart=/bin/true
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target

    {%- if (peers_with_lookup | length) > 0 %}
{{p}}Resolve timer:
  file.managed:
    - name: /rw/usrlocal/lib/systemd/system/wg-resolve.timer
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

{{p}}Wireguard config for {{ if_name }}:
  file.managed:
    - name: /rw/bind-dirs/etc/wireguard/{{ if_name }}.conf
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
        DNS = {{ (wg['dns'] | join(', ')) if wg['dns'] is sequence else wg['dns'] }}
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

{%- set dynamic_forward_chain = "dynamic-forward" %}
{%- set wireguard_table = "wireguard-tunnel" %}

{{p}}General forward firewall rules (part 1):
  file.managed:
    - name: /rw/config/qubes-firewall.d/49a-general-forward.nft
    - user: root
    - group: systemd-network
    - mode: 550
    - dir_mode: 555
    - makedirs: true
    - replace: true
    - contents: |
         #!/usr/sbin/nft -f
         # {{ salt_warning }}
         {%- if redirect_dns %}
           {%- for ip in ["ip", "ip6"] %}
         create chain {{ip}} qubes-firewall {{ dynamic_forward_chain }}
         add rule {{ip}} qubes-firewall forward jump {{ dynamic_forward_chain }}
         rename chain {{ip}} qubes-firewall forward forward-hook
           {%- endfor %}
         {%- endif %}

{{p}}General forward firewall rules (part 2):
  file.managed:
    - name: /rw/config/qubes-firewall.d/49b-general-forward.nft
    - user: root
    - group: systemd-network
    - mode: 550
    - dir_mode: 555
    - makedirs: true
    - replace: true
    - contents: |
         #!/usr/sbin/nft -f
         # {{ salt_warning }}
         {%- if redirect_dns %}
           {%- for ip in ["ip", "ip6"] %}
         rename chain {{ip}} qubes-firewall {{ dynamic_forward_chain }} forward
           {%- endfor %}
         {%- endif %}

{{p}}Wireguard failsafe firewall rules:
  file.managed:
    - name: /rw/config/qubes-firewall.d/10-wireguard-failsafe.nft
    - user: root
    - group: systemd-network
    - mode: 550
    - dir_mode: 555
    - makedirs: true
    - replace: true
    - contents: |
         #!/usr/sbin/nft -f
         # {{ salt_warning }}
         table inet {{ wireguard_table }} {
           chain init_failed {
             type nat hook prerouting priority dstnat - 10; policy drop;
           }
         }

{{p}}Main firewall rules:
  file.managed:
    - name: /rw/config/qubes-firewall.d/50-wireguard.nft
    - user: root
    - group: systemd-network
    - mode: 550
    - dir_mode: 555
    - makedirs: true
    - replace: true
    - contents: |
         #!/usr/sbin/nft -f
         # {{ salt_warning }}
         {%- if redirect_dns %}
         table ip qubes {
           chain custom-input {
             ct mark {{ dns_mark }} accept
           }
         }
         chain ip qubes-firewall input-with-forward-rules
         delete chain ip qubes-firewall input-with-forward-rules
         table ip qubes-firewall {
           chain test-dns-forward-rules-early {
             type nat hook prerouting priority dstnat - 10; policy accept;
             iifgroup 2 ip daddr { {{ qubes_dns_servers | join(', ') }} } meta l4proto {tcp, udp} th dport domain ct mark set {{ dns_mark }} counter jump forward
           }
         }

         {%- endif %}
         table inet {{ wireguard_table }}
         delete table inet {{ wireguard_table }}
         table inet {{ wireguard_table }} {
           chain only-forward-with-wireguard {
             type filter hook forward priority filter;
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

    {%- if redirect_dns %}
           chain redirect-dns {
             type nat hook prerouting priority dstnat - 9; policy accept;
             ct mark {{ dns_mark }} counter dnat ip to 127.0.0.54
           }
    {%- endif %}

    {%- if allow_forward_to_wan %}
           chain nat-wan-forward {
             type nat hook postrouting priority srcnat;
             oifgroup 1 masquerade
           }
    {%- endif %}
         }

         table ip qubes {
           chain custom-forward {
             tcp flags syn / syn,rst tcp option maxseg size set rt mtu
           }
         }

{{p}}Redirect to localhost firewall rules:
  {%- if not redirect_dns %}
  file.absent:
    - name: /rw/config/rc.local.d/30-allow-redirect-to-localhost.rc
  {%- else %}
  file.managed:
    - name: /rw/config/rc.local.d/30-allow-redirect-to-localhost.rc
    - user: root
    - group: root
    - mode: 555
    - makedirs: true
    - dir_mode: 555
    - replace: true
    - contents: |
        #!/bin/bash
        # {{ salt_warning }}
        echo 1 > /proc/sys/net/ipv4/conf/all/route_localnet
  {%- endif %}

{{p}}Wireguard service starter:
  file.managed:
    - name: /rw/config/rc.local.d/20-wireguard.rc
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
{%- endif %}
