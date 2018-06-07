#!/bin/sh
passwd centos<<EOF
rootroot
rootroot
EOF
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
service sshd restart || service ssh restart
