{% if grains['id'] == 'dom0' %}
Set ephemeral state for all lvm disks:
  cmd.run:
    - shell: /bin/bash
    - name: for pool in $(qvm-pool -l | tail -n +2 | awk '/\slvm_thin$/{ print $1 }') ; do qvm-pool --set "$pool" -o ephemeral_volatile=True ; done

{% endif %}
