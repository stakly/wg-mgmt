#!/bin/bash
[ -z "$1" ] && echo no input && exit 2
qrencode -t ansiutf8 < $1
