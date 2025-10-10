{%- from "formatting.jinja" import yaml_string, systemd_escape, sha256sum %}

{%- set p = "Test of formatting jinja - " %}

{%- set systemd_escape_tests = {'': '', 'my-service': 'my\\x2dservice', '/dev/null': '-dev-null', 'me@my.place': 'me\\x40my.place' } %}

{%- set sha256_tests = {'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'this is  text': '9edf030fdd49d7c74057ee57e7c6d65626ea52433d5c38834937aafa176a48a0', ' I haz\nmultiple\n\nLINES': 'b241d7d4fb1388f09658542bbb5fa1ccd212a7794024d086a5df516ae966f821' } %}

{%- macro test_eq(test, expected, actual) %}
  {%- set success = expected == actual %}
  test.configurable_test_state:
    - changes: false
    - result: {% if expected == actual -%}
        true
      {%- else -%}
        false
    - order: last
      {%- endif %}
    - comment: {{ yaml_string('Input:    "' + test + '"\n' + 
                              'Expected: "' + expected + '"\n' +
                              'Actual:   "' + actual + '"') }}
{%- endmacro %}

{%- for test, expected in systemd_escape_tests.items() %}
{{p}}systemd_escape() test {{ loop.index }}:
  {{- test_eq(test, expected, systemd_escape(test)) }}
{%- endfor %}

{%- for test, expected in systemd_escape_tests.items() %}
{{p}}systemd_escape block test {{ loop.index }}:
{%- set actual %}
  {%- call systemd_escape() %}
    {{- test }}
  {%- endcall %}
{%- endset %}
  {{- test_eq(test, expected, actual) }}
{%- endfor %}

{%- for test, expected in sha256_tests.items() %}
{{p}}sha256sum test {{ loop.index }}:
  {{- test_eq(test, expected, sha256sum(test)) }}
{%- endfor %}
