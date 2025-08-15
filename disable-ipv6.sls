{%- if grains['id'] != 'dom0' and salt['pillar.get']('qubes:type') == 'template' %}
  {%- from "formatting.jinja" import salt_warning %}
/etc/sysctl.d/50-disable-ipv6.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 444
    - replace: true
    - contents: |
        # {{ salt_warning }}
        net.ipv6.conf.all.disable_ipv6 = 1
        net.ipv6.conf.default.disable_ipv6 = 1
        net.ipv6.conf.lo.disable_ipv6 = 1
{%- endif %}
