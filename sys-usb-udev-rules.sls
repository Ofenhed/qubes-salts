{%- from "formatting.jinja" import salt_warning %}

{%- set sys_usb_dvm_template = salt['pillar.get']('usb-usb:dvm-template:name', 'sys-usb-template') %}

{%- if grains['id'] == 'dom0' %}

{%- from "dependents.jinja" import default_template %}

{%- set create_sys_usb_dvm = "Create " + sys_usb_dvm_template %}
{{ create_sys_usb_dvm }}:
  qvm.vm:
    - name: {{ sys_usb_dvm_template }}
    - present:
      - label: black
      - template: {{ salt['pillar.get']('qvm:sys-usb:template', default_template()) }}
    - prefs:
      - template_for_dispvms: true
      - class: AppVM
      - provides-network: false
      - netvm: none

Use {{ sys_usb_dvm_template }} in sys-usb:
  qvm.vm:
    - name: sys-usb
    - present:
    - require:
      - qvm: {{ create_sys_usb_dvm }}
    - present:
      - include-in-backups: false
    - prefs:
      - template: {{ sys_usb_dvm_template }}
      - class: DispVM
      - provies-network: false
      - netvm: none
{%- elif grains['id'] == sys_usb_dvm_template %}
/usr/local/lib/udev/rules.d/89-disable-inputs.rules:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - dir_mode: 755
    - makedirs: true
    - replace: true
    - contents: |
        # {{ salt_warning }}
    {%- filter indent(8, first = True) %}
      {{- '\n' }}
      {%- for rule in salt['pillar.get']('sys-usb:udev-rules') %}
        {{- rule + '\n' }}
      {%- endfor %}
    {%- endfilter %}

{%- endif %}
