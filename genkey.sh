#!/bin/bash
[ -z "$1" ] && echo "$0 <USERNAME>" && exit 2

. ./env

if [ -z "$ADDRESS_NET" ] || [ -z "$FIRST_IP" ] || [ -z "$DNS_SERVERS" ] || [ -z "$ENDPOINT" ] || [ -z "$ENDPOINT_PUBLICKEY" ]; then
	echo 'ERROR: check environment variables' 
	exit 2
fi

NAME=$1
echo "[*] generating keys for $NAME..."

if wg genkey | tee $NAME.key | wg pubkey > $NAME.pubkey ; then
	KEY=`cat $NAME.key`
	PUB_KEY=`cat $NAME.pubkey`
	if compgen -G "*.conf" >/dev/null ; then
		IP=$((`awk '/Address/ {print $3}' *.conf | sort -t . -k 4 -n | tail -n1 | sed -Ee 's/[0-9]+\.[0-9]+\.[0-9]+\.([0-9]+)\/24.*/\1/g'` + 1))
		if [ ! -z "$ADDRESS_NET_V6" ] ; then
			IPV6="$((`awk '/Address/ {print $3 $4}' *.conf | grep "${ADDRESS_NET_V6/x/.*}" | sort -t . -k 4 -n | tail -n1 | sed -Ee "s/.*"${ADDRESS_NET_V6/x\\//([0-9]+)\\\/}".*/\1/g"` + 1))"
		fi
	else
		echo "[!] no configs, IP address will be $FIRST_IP"
		IP=$FIRST_IP
		if [ ! -z "$ADDRESS_NET_V6" ] ; then
			IPV6=$FIRST_IP
		fi

	fi
	ALLOWIP=${ADDRESS_NET/x*/$IP\/32}
	IP=${ADDRESS_NET/x/$IP}
	if [ ! -z "$ADDRESS_NET_V6" ] ; then
		#IPV6="$((`awk '/Address/ {print $3 $4}' *.conf | grep "${ADDRESS_NET_V6/x/.*}" | sort -t . -k 4 -n | tail -n1 | sed -Ee "s/.*"${ADDRESS_NET_V6/x\\//([0-9]+)\\\/}".*/\1/g"` + 1))"
		GWV6=',::/0'
		ALLOWIPV6=",${ADDRESS_NET_V6/x*/$IPV6\/128}"
		IPV6=",${ADDRESS_NET_V6/x/$IPV6}"
	fi
	echo "[*] generating config $NAME.conf with IP ${IP}${IPV6}"
	cat >$NAME.conf<<EOF
[Interface]
PrivateKey = $KEY
Address = ${IP}${IPV6}
DNS = $DNS_SERVERS

[Peer]
PublicKey = $ENDPOINT_PUBLICKEY
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0${GWV6}
EOF
	if [ -n "$WGCONF" ]; then
		echo "[*] adding peer to system config $WGCONF"
		cat >>$WGCONF<<EOF

[Peer]
PublicKey = $PUB_KEY
AllowedIPs = ${ALLOWIP}${ALLOWIPV6}
EOF
		echo "[!] restart wireguard: systemctl restart wg-quick@wg0.service"
	fi

	echo "[*] generating qr-code $NAME.png"
	qrencode -t ansiutf8 -o $NAME.png -r $NAME.conf -t png
	qrencode -t ansiutf8 -r $NAME.conf
	if [ $MT_CLIENT -eq 1 ] ; then
		echo "[!] now add peer on router:"
		echo "/interface wireguard peers add allowed-address=$ADDRESS_NET.$IP/32 comment=$NAME interface=wg1 public-key=\"$PUB_KEY\""
	fi
fi
