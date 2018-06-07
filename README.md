# Packstack-config
this repo is to record how to use packstack install OpenStack


## File Layout
```
[renyl@localhost packstack-config]$ tree -L 2
.
├── 21-server
│   ├── cinder_backup
│   ├── glance_backup
│   ├── ifcfg-br-ex.backup
│   ├── ifcfg-em1.backup
│   ├── ifcfg-em1.original.bak
│   ├── neutron_backup
│   └── nova_backup
├── 22-server
│   ├── cinder_backup
│   ├── ifcfg-br-ex.backup
│   ├── ifcfg-em1.backup
│   ├── ifcfg-em1.original.backup
│   ├── neutron_backup
│   └── nova_backup
├── answer-file.txt
├── change_passwd_centos.sh
├── change_passwd_ubuntu.sh
├── doc
│   └── OpenStack部署手册.docx
├── qemu-kvm
├── README.md
└── tools
    ├── change-volume-status.sh
    ├── create_boot_instance.sh
    ├── manager_user.sh
    ├── migrate_instance.sh
    └── uninstall_openstack.sh

11 directories, 17 files
[renyl@localhost packstack-config]$
```

## Contributors
* Yilong Ren
* ChenYang Yan

## License
This project is licensed under the GPL v2 license
