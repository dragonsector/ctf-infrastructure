#!/bin/bash

if [ -n "$CTF_VPN_FORCEOK" ]; then
	exit 0
fi

if [ -n "$CTF_VPN_MANUAL" ]; then
	echo "Press enter after connecting VPN manually"
	read whatever
	exit 0
fi

if [ "$1" == "connect" ]; then
	sudo pidof openvpn || sudo openvpn --daemon openvpn-ctf-${DENV} --config vpn/${DENV}.conf
elif [ "$1" == "disconnect" ]; then
	sudo pkill openvpn
fi
