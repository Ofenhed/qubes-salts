# -*- coding: utf-8 -*-
# vim: set syntax=yaml ts=2 sw=2 sts=2 et :

add_ssh_askpass:
  pkg.installed:
    - pkgs:
{% if grains['os_family'] == 'Debian' %}
      - ssh-askpass-gnome
{% elif grains['os_family'] == 'RedHat' %}
      - openssh-askpass
{% endif %}

