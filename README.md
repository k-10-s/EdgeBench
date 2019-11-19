Hunt Utilizing Specialized Hardware
====

Ansible Playbooks to benchmark network sensor performance of embedded sized hardware

# Requirements:
1. Generator machine with Ansible, tcpreplay and netmap installed
2. Ideally with a NIC that supports netmap native drivers
3. Something to test against (see inventory for examples)

### Add eveything to your hosts file for name resolution, i.e. 

```
nano /etc/hosts...
10.0.0.1        tx1
10.0.0.2        tx2
10.0.0.3        rpi3bp
10.0.0.4        rpi4
10.0.0.5        xavier
```

### Generate some SSH keys if you don't have them already
`ssh-keygen`

### First time connecting will need a password, afterwards your SSH keys will be used
`ansible-playbook -i inventory.yml --ask-pass --ask-become-pass  prep-playbook.yml`

### Running playbooks:
`ansible-playbook -i inventory.yml suricata-bench-playbook.yml`

### Overriding variables from command line:
`ansible-playbook -i inventory.yml -e "pps_limit=104000" suricata-bench-playbook.yml`

### Limiting to only certain hosts from inventory: 
`ansible-playbook -i inventory.yml -l nvidia pcap-bench-playbook.yml`


