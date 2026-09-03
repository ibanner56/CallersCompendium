#!/bin/sh
set -eu

host=${1:?usage: smoke_test.sh <host> [https-port] [http-port]}
https_port=${2:-443}
http_port=${3:-80}
credential=${ATHENAEUM_CREDENTIAL:?set ATHENAEUM_CREDENTIAL to a valid encoded sync credential}
http_body=$(mktemp)
https_headers=$(mktemp)
https_post_body=$(mktemp)
https_get_body=$(mktemp)
trap 'rm -f "$http_body" "$https_headers" "$https_post_body" "$https_get_body"' EXIT

http_status=$(
  curl --silent --show-error --max-time 10 --max-redirs 0 \
    --output "$http_body" --write-out '%{http_code}' \
    "http://${host}:${http_port}/v1/store" || true
)
case "$http_status" in
  4??|5??) ;;
  *)
    echo "plaintext /v1 was not refused (HTTP ${http_status:-000})" >&2
    exit 1
    ;;
esac
if grep -Eiq '"error"|application/json' "$http_body"; then
  echo "plaintext /v1 returned an Athenaeum backend response" >&2
  exit 1
fi

https_post_status=$(
  curl --silent --show-error --max-time 10 --max-redirs 0 \
    --request POST --header "Authorization: Bearer ${credential}" \
    --dump-header "$https_headers" --output "$https_post_body" \
    --write-out '%{http_code}' "https://${host}:${https_port}/v1/store"
)
case "$https_post_status" in
  201|409) ;;
  *)
    echo "HTTPS create did not reach Athenaeum (HTTP $https_post_status)" >&2
    exit 1
    ;;
esac

https_get_status=$(
  curl --silent --show-error --max-time 10 --max-redirs 0 \
    --request GET --header "Authorization: Bearer ${credential}" \
    --output "$https_get_body" --write-out '%{http_code}' \
    "https://${host}:${https_port}/v1/store"
)
if [ "$https_get_status" != 200 ] || ! grep -Eq '"epoch"' "$https_get_body"; then
  echo "HTTPS lookup did not return an Athenaeum store (HTTP $https_get_status)" >&2
  exit 1
fi
grep -Fqi 'strict-transport-security:' "$https_headers"
echo "W16 proxy smoke checks passed"
