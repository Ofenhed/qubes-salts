{%- from "formatting.jinja" import yaml_string, systemd_escape %}

Show all grains for {{ grains['id'] }}:
  test.show_notification:
    - text: |
{%- for (key, item) in grains.items() %}
  {{- ("\n%s:\n%s\n") | format(key, item) | indent(10) }}
{%- endfor %}

Show all pillars for {{ grains['id'] }}:
  test.show_notification:
    - text: {{ yaml_string(pillar['qubes']) }}

Test cmd state:
  cmd.run:
    - name: echo hi

Available salt fields:
  test.show_notification:
    - text: |
        Available: 
    {%- for test, value in salt.items() %}
      {%- if loop.index > 1 %}, {% endif -%}
        {{ test }}
    {%- endfor %}
