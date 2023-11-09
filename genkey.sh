#!/bin/bash
[ -z "$1" ] && echo "$0 <USERNAME>" && exit 2

. ./env

if [ -z "$ADDRESS_NET" ] || [ -z "$FIRST_IP" ] || [ -z "$DNS_SERVERS" ] || [ -z "$ENDPOINT_IP" ] || [ -z "$ENDPOINT_PORT" ] || [ -z "$ENDPOINT_PUBLICKEY" ]; then
	echo 'ERROR: check environment variables' 
	exit 2
fi

NAME=$1
if compgen -G "$NAME.*" > /dev/null ; then
  echo "ERROR: files for \"$NAME\" already exist. Remove it first."
  exit 1
fi

echo "[*] generating keys for $NAME..."

if wg genkey | tee "$NAME".key | wg pubkey > "$NAME".pubkey ; then
	KEY=$(cat "$NAME".key)
	PUB_KEY=$(cat "$NAME".pubkey)
	if compgen -G "*.conf" >/dev/null ; then
		IP=$(($(awk '/Address/ {print $3}' ./*.conf | sort -t . -k 4 -n | tail -n1 | sed -Ee 's/[0-9]+\.[0-9]+\.[0-9]+\.([0-9]+)\/24.*/\1/g') + 1))
		if [ -n "$ADDRESS_NET_V6" ] ; then
			IPV6="$(($(awk '/Address/ {print $3 $4}' ./*.conf | grep "${ADDRESS_NET_V6/x/.*}" | sort -t . -k 4 -n | tail -n1 | sed -Ee "s/.*"${ADDRESS_NET_V6/x\\//([0-9]+)\\\/}".*/\1/g") + 1))"
		fi
	else
		echo "[!] no configs, IP address will be $FIRST_IP"
		IP=$FIRST_IP
		if [ -n "$ADDRESS_NET_V6" ] ; then
			IPV6=$FIRST_IP
		fi

	fi
	ALLOWIP=${ADDRESS_NET/x*/$IP\/32}
	IP=${ADDRESS_NET/x/$IP}
	if [ -n "$ADDRESS_NET_V6" ] ; then
		#IPV6="$((`awk '/Address/ {print $3 $4}' *.conf | grep "${ADDRESS_NET_V6/x/.*}" | sort -t . -k 4 -n | tail -n1 | sed -Ee "s/.*"${ADDRESS_NET_V6/x\\//([0-9]+)\\\/}".*/\1/g"` + 1))"
		GWV6=',::/0'
		ALLOWIPV6=",${ADDRESS_NET_V6/x*/$IPV6\/128}"
		IPV6=",${ADDRESS_NET_V6/x/$IPV6}"
	fi
	echo "[*] generating config $NAME.conf with IP ${IP}${IPV6}"
	cat >"$NAME".conf<<EOF
[Interface]
PrivateKey = $KEY
Address = ${IP}${IPV6}
DNS = $DNS_SERVERS

[Peer]
PublicKey = $ENDPOINT_PUBLICKEY
Endpoint = $ENDPOINT_IP:$ENDPOINT_PORT
AllowedIPs = 0.0.0.0/0${GWV6}
EOF
	if [ -n "$WGCONF" ]; then
		echo "[*] adding peer to system config $WGCONF"
		cat >>"$WGCONF"<<EOF

[Peer]
PublicKey = $PUB_KEY
AllowedIPs = ${ALLOWIP}${ALLOWIPV6}
EOF
		echo "[!] restarting wireguard: systemctl restart wg-quick@wg0.service"
		systemctl restart wg-quick@wg0.service
	fi

  if command -v qrencode &>/dev/null ; then
    echo "[*] generating qr-code $NAME.png"
    qrencode -t ansiutf8 -o "$NAME".png -r "$NAME".conf -t png
    qrencode -t ansiutf8 -r "$NAME".conf
  fi
	if [ "$MT_CLIENT" -eq 1 ] ; then
		echo "[!] add peer on RouterOS router:"
		echo "  /interface wireguard add comment=ZVPN listen-port=$MT_CLIENT_PORT mtu=1420 name=wg1 private-key=\"$KEY\""
		echo "  /interface wireguard peers add allowed-address=0.0.0.0/0 comment=$NAME interface=wg1 endpoint-address=$ENDPOINT_IP endpoint-port=$ENDPOINT_PORT public-key=\"$ENDPOINT_PUBLICKEY\""
		echo "  /ip address add address=$IP interface=wg1"
		echo "[!] now manually route traffic via wg1"
	fi
fi
