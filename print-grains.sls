Show all grains for {{ grains['id'] }}:
  test.show_notification:
    - text: |
{%- for (key, item) in grains.items() %}
  {{- ("\n%s:\n%s\n") | format(key, item) | indent(10) }}
{%- endfor %}

