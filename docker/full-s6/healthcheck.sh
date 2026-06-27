#!/bin/sh
set -eu

/command/s6-svstat /run/s6-rc/servicedirs/hbbr | grep -q '^up ' || exit 1
/command/s6-svstat /run/s6-rc/servicedirs/hbbs | grep -q '^up ' || exit 1
/command/s6-svstat /run/s6-rc/servicedirs/api | grep -q '^up ' || exit 1
curl -fsS http://127.0.0.1:21114/api/version >/dev/null || exit 1
