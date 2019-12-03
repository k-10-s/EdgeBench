Hunt Utilizing Specialized Hardware
====

Ansible Playbooks to benchmark network sensor performance of embedded sized hardware

# Requirements:
1. Generator machine with Ansible installed & ideally with a NIC that supports netmap native drivers
2. Something to test against (see inventory for examples)


### Build inventory.yml with sensors specific variables

```yaml
sensors: 
        children:
            rpi:
                hosts:
                    rpi3bp:
                        send_interface: eth7
                        capture_interface: eth0
                    rpi4:
                        send_interface: eth8
                        capture_interface: eth0
                vars:
                    ansible_user: pi
                    ansible_become_method: sudo
                    sensor_dir: /sensor
                    ansible_python_interpreter: /usr/bin/python
              
            nvidia:
                hosts:
                    tx1:
                        capture_interface: eth0
                        send_interface: eth3
                    tx2:
                        capture_interface: eth1
                        send_interface: eth6
                    xavier:
                        capture_interface: eth0
                        send_interface: eth4
                vars:
                    ansible_user: nvidia
                    ansible_become_method: sudo
                    sensor_dir: /sensor
			traditional:
				hosts:
					maas-1:
						capture_interface: eth1
					maas-2:
						capture_interface: eth1
				vars:                
                    ansible_user: maas-user
                    ansible_become_method: sudo
                    sensor_dir: /sensor
```


### Add sensor IP addresses to your hosts file for name resolution, i.e. 

```
nano /etc/hosts...
10.0.0.1        tx1
10.0.0.2        tx2
10.0.0.3        rpi3bp
10.0.0.4        rpi4
10.0.0.5        xavier
10.10.10.60		maas-1
10.10.10.61		maas-2
```

### Generate some SSH keys if you don't have them already
`ssh-keygen`

### First time connecting run the prep playbook to setup SSH keys and dependencies
`ansible-playbook -i inventory.yml --ask-pass --ask-become-pass  prep-playbook.yml`

### Running playbooks:
`ansible-playbook -i inventory.yml suricata-bench-playbook.yml`

### Overriding variables from command line:
`ansible-playbook -i inventory.yml -e "pps_limit=104000" suricata-bench-playbook.yml`

### Limiting to only certain hosts from inventory: 
`ansible-playbook -i inventory.yml -l nvidia pcap-bench-playbook.yml`


