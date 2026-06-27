#!/bin/sh
set -eu

service="${1:-}"

case "$service" in
  hbbs)
    pgrep -x hbbs >/dev/null
    ss -lnt | grep -q ':21116 '
    ss -lnu | grep -q ':21116 '
    ;;
  hbbr)
    pgrep -x hbbr >/dev/null
    ss -lnt | grep -q ':21117 '
    ;;
  *)
    echo "usage: rustdesk-healthcheck hbbs|hbbr" >&2
    exit 2
    ;;
esac
