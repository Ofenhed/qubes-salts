# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

{%- if grains['id'] == 'dom0' %}
  {%- from "formatting.jinja" import salt_warning, systemd_shell %}
  
  {%- set p = "Set dom0 Xen Scheduler priority - " %}
  {%- set systemd_dir = "/usr/lib/systemd/system" %}
  {%- set dom0_priority_service_name = "dom0-priority.service" %}
  {%- set dom0_weight = 512 %}
  
{{p}}Add and enable service:
  file.managed:
    - name: /usr/lib/systemd/system/{{ dom0_priority_service_name }}
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        [Unit]
        Description=Set Dom0 priority for the Xen scheduler
        After=xen-init-dom0.service
        ConditionKernelCommandLine=!qubes.skip_autostart
        ConditionKernelCommandLine=!qubes.normal_dom0_priority
        
        [Service]
        Type=oneshot
        ExecStart={%- call systemd_shell() %}
          if xl cpupool-list | grep -q credit2; then
            if dom0_id=$(xl sched-credit2 | awk '$1 == "Domain-0" { print $2 }'); then
              echo "Setting dom0 weight to {{ dom0_weight }}"
              xl sched-credit2 -d "$dom0_id" -w {{ dom0_weight }}
            fi
          fi
        {%- endcall %}
        RemainAfterExit=yes
        
        [Install]
        WantedBy=qubesd.service

  service.running:
    - enable: True
    - reload: True
    - name: {{ dom0_priority_service_name }}
{%- endif %}
