Hunt Utilizing Specialized Hardware
====

Ansible Playbooks to benchmark network sensor performance of embedded sized hardware

# Requirements:
1. Generator machine with Ansible, tcpreplay and netmap installed
2. Ideally with a NIC that supports netmap native drivers
3. Something to test against (see inventory for examples)


### Running playbooks:
`ansible-playbook -i inventory.yml suricata-bench-playbook.yml`

### Overriding variables from command line:

`ansible-playbook -i inventory.yml -e "pps_limit=104000" suricata-bench-playbook.yml`

### Limiting to only certain hosts from inventory: 

`ansible-playbook -i inventory.yml -l nvidia pcap-bench-playbook.yml`


