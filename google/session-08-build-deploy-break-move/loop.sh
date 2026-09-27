#!/usr/bin/env bash
# A fleet dispatcher asking for a fare quote twice a second.
#
#   ./loop.sh            run until Ctrl-C, one line per request
#   ./loop.sh 60         run for 60 seconds, then print a summary
#
# Each line is the time, the HTTP status or ERR, the model version, the pod
# that answered, and the milliseconds the quote took. Start it in a second
# terminal at step 5 and leave it running through step 7.
set -u
IP="$(kubectl get service fare-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
[ -n "$IP" ] || { echo "The Service has no external IP yet. Wait and run again."; exit 1; }
END=$(( $(date +%s) + ${1:-999999} ))
ok=0; err=0
while [ "$(date +%s)" -lt "$END" ]; do
  body="$(curl -s -m 2 -w ' %{http_code}' "http://$IP/quote?pickup=132&dropoff=236")"
  code="${body##* }"
  if [ "$code" = "200" ]; then
    ok=$((ok + 1))
    printf '%s  200  %s\n' "$(date +%H:%M:%S)" \
      "$(printf '%s' "${body% *}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"], d["pod"], str(d["ms"])+"ms")')"
  else
    err=$((err + 1))
    printf '%s  ERR  %s\n' "$(date +%H:%M:%S)" "${code:-timeout}"
  fi
  sleep 0.5
done
echo "summary: $ok answered, $err failed"
