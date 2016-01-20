DENV := test
ifneq ($(DENV),test)
ifneq ($(DENV),prod)
$(error DENV must be one of: test, prod!)
endif
endif

FLAGSYSTEM_REMOTE=git@git.dragonsector.pl:confidence-2015/flagsystem
FLAGSYSTEM_COMMIT=main-$(DENV)
CTFJAIL_REMOTE=git@github.com:google/nsjail
CTFJAIL_COMMIT=master

.PHONY: clean update virtualenv challenges

default: help

help:
	@echo "Milkcrate Deployment Script (c) (r) ORIGINAL CHARACTER DO NOT STEAL"
	@echo "All deployment commands take a DENV= env var, which can be either prod or test."
	@echo "Additionally, for ansible.infrastructure you'll need to specify a keyname with KEYPAIR="
	@echo ""
	@echo "=== Final Targets ==="
	@echo "These are not called by other targets other than its' parent (ie. update.nsjail by update)"
	@echo "make"
	@echo ' -> update                 // shorthand for .flagsystem -> .nsjail -> .challenges'
	@echo '      -> flagsystem        // redownload flagsystem from Git'
	@echo '      -> nsjail           // redownload and recompile nsjail from Git'
	@echo '      -> challenges        // redownload challenge files (meta, resources, distfiles)'
	@echo ' -> ansible                // shorthand for .infrastructure -> .software -> .tasks -> .challenges'
	@echo '      -> infrastructure    // create AWS infrastructure'
	@echo '      -> software          // install software on deployed infrastructure (excluding tasks)'
	@echo '      -> tasks             // install tasks on taskservers'
	@echo '      -> challenges        // install challenges on taskservers'
	@echo '      -> flagsystem        // install/update flagsystem (also done by .software, but quicker)'
	@echo '      -> local.infra       // first-time setup local infrastructure'
	@echo '      -> local.software    // install/update software on local infrastructure'
	@echo '      -> tasks.infra       // first-time setup tasks infrastructure'
	@echo ' -> secrets.list           // list pass-based secrets'
	@echo ' -> secrets.extract        // extract pass-based secrets to files-secret/'
	@echo ' -> secrets.pack           // package pass-based secrets from files-secret/'
	@echo ' -> vpn.connect            // start openvpn client daemon'
	@echo ' -> vpn.disconnect         // stop openvpn client daemon'
	@echo ' -> hosts.list             // list all hosts from inventory'
	@echo ''
	@echo '=== Intermediary Targets ==='
	@echo 'These can be used for debugging purposes, but are not required to be called for a proper deployment.'
	@echo ' -> challenges             // generate challenge classes into challenges/ from meta, etc and upload resources'

## Environment preparation

.venv/bin/activate:
	virtualenv --no-site-packages .venv
	( . .venv/bin/activate && pip install -r requirements.txt )
virtualenv: .venv/bin/activate

inventory/localhost: virtualenv
	@echo "[localhost]" > inventory/localhost
	@echo "localhost ansible_connection=local ansible_python_interpreter=$$(pwd)/.venv/bin/python" >> inventory/localhost

## Deployment stuff

tmp/task/%:
	rm -rf tmp/task/$(shell basename $@)
	mkdir -p tmp/task/$(shell basename $@)
	git clone -b master git@git.dragonsector.pl:confidence-2015/main-$(shell basename $@) tmp/task/$(shell basename $@)
	( cd tmp/task/$(shell basename $@) && make build && make distfiles )

distfiles/flagsystem-$(DENV):
	mkdir -p distfiles
	rm -rf distfiles/flagsystem-$(DENV)
	mkdir -p distfiles/flagsystem-$(DENV)
	git clone -b $(FLAGSYSTEM_COMMIT) $(FLAGSYSTEM_REMOTE) distfiles/flagsystem-$(DENV)
	( cd distfiles/flagsystem-$(DENV) && git rev-parse HEAD > GIT-REVISION )
	( cd distfiles/flagsystem-$(DENV) && date > BUILD-TIME )
	( cd distfiles/flagsystem-$(DENV) && uname -a > BUILD-HOST )
	( cd distfiles/flagsystem-$(DENV) && rm -rf .git )

distfiles/nsjail:
	mkdir -p distfiles
	rm -rf distfiles/nsjail
	mkdir -p distfiles/nsjail
	git clone -b $(CTFJAIL_COMMIT) $(CTFJAIL_REMOTE) distfiles/nsjail
	( cd distfiles/nsjail && make && strip nsjail )
	( cd distfiles/nsjail && git rev-parse HEAD > GIT-REVISION )
	( cd distfiles/nsjail && date > BUILD-TIME )
	( cd distfiles/nsjail && uname -a > BUILD-HOST )
	( cd distfiles/nsjail && rm -rf .git )

client-resources/%: virtualenv tmp/task/%
	( cd tmp/task/$(shell basename $@)/resources && tar c * | ( cd $(shell pwd) && mkdir -p client-resources && rm -rf $@ && mkdir -p $@ && cd $@ && tar xv ) )

meta/%: virtualenv tmp/task/%
	( cd tmp/task/$(shell basename $@)/meta && tar c * | ( cd $(shell pwd) && mkdir -p client-resources && rm -rf $@ && mkdir -p $@ && cd $@ && tar xv ) )

distfiles/%: virtualenv tmp/task/%
	( cd tmp/task/$(shell basename $@)/distfiles && tar c * | ( cd $(shell pwd) && mkdir -p client-resources && rm -rf $@ && mkdir -p $@ && cd $@ && tar xv ) )


READY_CHALLENGES = internet-of-booze-re internet-of-booze-pwn go-for-it just-another-matryoshka spoon-knife-and shiz night-sky turbo-crackme core a-hopeless-case katarzyna soaped-sql rsa1 rsa2 encrypted-png deobfuscateme polution look some-srs-crypto

challenges: virtualenv
	rm -rf challenges
	mkdir challenges
	( . .venv/bin/activate; set -e -x; for i in $(READY_CHALLENGES); do bin/generate-task.py $$i; done )

clean:
	rm -rf distfiles
	rm -rf .venv
	rm -f inventory/localhost
	rm -rf playbooks/test-*
	rm -rf files-secret
	rm -rf client-resources
	rm -rf meta

update:
	make update.nsjail
	make update.flagsystem
	make update.challenges

update.nsjail:
	rm -rf distfiles/nsjail
	make distfiles/nsjail

update.flagsystem:
	rm -rf distfiles/flagsystem-$(DENV)
	make distfiles/flagsystem-$(DENV)

update.challenges:
	rm -rf tmp/*
	rm -rf meta/*
	rm -rf distfiles/*
	rm -rf client-resources/*
	( set -e -x ; for i in $(READY_CHALLENGES); do make distfiles/$$i; make meta/$$i; make client-resources/$$i; done )

## Secret management using pass

export PASSWORD_STORE_DIR=$(shell pwd)/secrets

.PHONY: secrets.list secrets.extract secrets.pack

secrets.list:
	pass list

secrets.extract:
	mkdir -p files-secret
	for f in secrets/*; do ( f2=`echo $$f|sed -e 's/\.gpg$$//'`; echo $$f2; pass $$(basename $$f2) > files-secret/$$(basename $$f2) ); done

secrets.pack:
	for f in files-secret/*; do ( cat $$f | pass insert -m -f $$(basename $$f) ); done

files-secret/flagsystem-config-prod.php files-secret/flagsystem-config-test.php:
	make secrets.extract

hosts.list: export EC2_INI_PATH=$(shell pwd)/ec2-private.ini
hosts.list: virtualenv inventory/localhost
	$(if $(KEYPAIR),,$(error "Please set KEYPAIR to an AWS keypair name"))
	@( . .venv/bin/activate && python inventory/ec2.py --hosts-list $(DENV) )

## Ansible and shit

export KEYPAIR

.PHONY: ansible.infrastructure ansible.software ansible.local.infra ansible.local.software

playbooks/test-%: playbooks/prod-%
	cat $< | sed 's/Production/Testing/' | sed 's/production/testing/' | sed 's/Prod/Test/' | sed 's/prod/test/' | sed 's/enable_htpasswd=false/enable_htpasswd=true/' > $@

ansible:
	@echo "CHOO CHOO! Time to hop on the deployment train."
	make ansible.infrastructure
	make ansible.software
	make ansible.challenges

ansible.infrastructure: export EC2_INI_PATH=$(shell pwd)/ec2-public.ini
ansible.infrastructure: virtualenv inventory/localhost playbooks/$(DENV)-01-infra.yaml
	$(if $(KEYPAIR),,$(error "Please set KEYPAIR to an AWS keypair name"))
	( . .venv/bin/activate && ansible-playbook -i inventory/ playbooks/$(DENV)-01-infra.yaml )

ansible.local.infra: virtualenv playbooks/$(DENV)-04-localinfra.yaml
	( . .venv/bin/activate && ansible-playbook -i inventory/local.ini playbooks/$(DENV)-04-localinfra.yaml)

ansible.tasks.infra: virtualenv playbooks/$(DENV)-015-tasksinfra.yaml
	( . .venv/bin/activate && ansible-playbook -i inventory/local.ini playbooks/$(DENV)-015-tasksinfra.yaml)

ansible.local.software: virtualenv playbooks/$(DENV)-05-localsoftware.yaml
	( . .venv/bin/activate && ansible-playbook -i inventory/local.ini playbooks/$(DENV)-05-localsoftware.yaml)

ansible.software: export EC2_INI_PATH=$(shell pwd)/ec2-private.ini
ansible.software: virtualenv inventory/localhost distfiles/flagsystem-$(DENV) playbooks/$(DENV)-02-software.yaml files-secret/flagsystem-config-$(DENV).php challenges
	( . .venv/bin/activate && ansible-playbook -i inventory/ playbooks/$(DENV)-02-software.yaml )

_distfiles__tasks: $(shell for i in $(READY_CHALLENGES); do echo "distfiles/$$i "; done)

ansible.tasks: export EC2_INI_PATH=$(shell pwd)/ec2-private.ini
ansible.tasks: virtualenv inventory/localhost distfiles/nsjail _distfiles__tasks playbooks/$(DENV)-03-tasks.yaml files-secret/soaped-sql-db_connect-$(DENV).php
	( . .venv/bin/activate && ansible-playbook -i inventory/ playbooks/$(DENV)-03-tasks.yaml )

ansible.challenges: export EC2_INI_PATH=$(shell pwd)/ec2-private.ini
ansible.challenges: virtualenv inventory/localhost challenges playbooks/$(DENV)-challenges.yaml
	( . .venv/bin/activate && ansible-playbook -i inventory/ playbooks/$(DENV)-challenges.yaml )

ansible.flagsystem: export EC2_INI_PATH=$(shell pwd)/ec2-private.ini
ansible.flagsystem: virtualenv inventory/localhost distfiles/flagsystem-$(DENV) playbooks/$(DENV)-flagsystem.yaml files-secret/flagsystem-config-$(DENV).php challenges update.flagsystem
	( . .venv/bin/activate && ansible-playbook -i inventory/ playbooks/$(DENV)-flagsystem.yaml )

ansible.pkgupgrade: export EC2_INI_PATH=$(shell pwd)/ec2-private.ini
ansible.pkgupgrade: virtualenv inventory/localhost playbooks/$(DENV)-pkgupgrade.yaml
	( . .venv/bin/activate && ansible-playbook -i inventory/ playbooks/$(DENV)-pkgupgrade.yaml )

# i'm a lazy fuck
vpn/test.conf: export EC2_INI_PATH=$(shell pwd)/ec2-public.ini
vpn/test.conf: vpn/test-ca.crt vpn/test-client.crt vpn/test-client.key vpn/client.conf.template
	cat vpn/client.conf.template | sed 's/{{ENV}}/test/' | sed 's/{{REMOTE}}/$(shell .venv/bin/python inventory/ec2.py --list | jq -r '.tag_Role_ctf_test_role_jumpbox[0]')/' > $@

vpn/prod.conf: export EC2_INI_PATH=$(shell pwd)/ec2-public.ini	
vpn/prod.conf: vpn/prod-ca.crt vpn/prod-client.crt vpn/prod-client.key vpn/client.conf.template
	cat vpn/client.conf.template | sed 's/{{ENV}}/prod/' | sed 's/{{REMOTE}}/$(shell .venv/bin/python inventory/ec2.py --list | jq -r '.tag_Role_ctf_prod_role_jumpbox[0]')/' > $@

.PHONY: vpn.connect vpn.disconnect

export DENV
export CTF_VPN_MANUAL CTF_VPN_FORCEOK

vpn.connect: vpn/$(DENV).conf
	@bash vpn/manage.sh connect

vpn.disconnect:
	@bash vpn/manage.sh disconnect
