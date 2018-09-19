#!/bin/bash
vagrant up
vagrant ssh -c 'cd /vagrant && CARGO_TARGET_DIR=centos-build/ PQ_LIB_DIR=/usr/pgsql-10/lib cargo build -p mccraft_web_server'
vagrant ssh -c 'cd /vagrant && tar czvf mccraft-1.0.0.tar.gz centos-build/release/mccraft_web_server mccraft_frontend/dist/'
vagrant ssh-config > vagrant.sshconfig
scp -F vagrant.sshconfig default:/vagrant/mccraft-1.0.0.tar.gz mccraft.tar.gz
