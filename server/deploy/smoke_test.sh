#!/bin/sh
set -eu

host=${1:?usage: smoke_test.sh <host> [https-port] [http-port]}
https_port=${2:-443}
http_port=${3:-80}
credential=${ATHENAEUM_CREDENTIAL:?set ATHENAEUM_CREDENTIAL to a new encoded sync credential}
http_body=$(mktemp)
https_headers=$(mktemp)
https_post_body=$(mktemp)
https_get_body=$(mktemp)
large_body=$(mktemp)
oversized_body=$(mktemp)
raw_body=$(mktemp)
compressed_body=$(mktemp)
compressed_boundary_raw=$(mktemp)
compressed_boundary=$(mktemp)
boundary_response=$(mktemp)
created_credentials=$(mktemp)
cleanup_failures=$(mktemp)
apache_config=${ATHENAEUM_APACHE_CONFIG:?set ATHENAEUM_APACHE_CONFIG to the active Apache vhost}
apachectl_bin=${ATHENAEUM_APACHECTL:-apachectl}
run_id=$(od -An -N8 -tx1 /dev/urandom | tr -d '[:space:]')

curl_local() {
  curl \
    --resolve "${host}:${https_port}:127.0.0.1" \
    --resolve "${host}:${http_port}:127.0.0.1" \
    "$@"
}

cleanup() {
  set +e
  if [ -s "$created_credentials" ]; then
    while IFS= read -r token; do
      status=$(curl_local --silent --max-time 10 --request DELETE \
        --header "Authorization: Bearer ${token}" \
        --output /dev/null --write-out '%{http_code}' \
        "https://${host}:${https_port}/v1/store" 2>/dev/null || printf '000')
      if [ "$status" = 429 ]; then
        sleep 60
        status=$(curl_local --silent --max-time 10 --request DELETE \
          --header "Authorization: Bearer ${token}" \
          --output /dev/null --write-out '%{http_code}' \
          "https://${host}:${https_port}/v1/store" 2>/dev/null || printf '000')
      fi
      if [ "$status" != 204 ] && [ "$status" != 404 ]; then
        printf '%s\n' "$token" >> "$cleanup_failures"
      fi
    done < "$created_credentials"
  fi
  if [ -s "$cleanup_failures" ]; then
    echo "cleanup incomplete; credentials retained in $cleanup_failures" >&2
  else
    rm -f "$cleanup_failures"
  fi
  rm -f "$http_body" "$https_headers" "$https_post_body" "$https_get_body" \
    "$large_body" "$oversized_body" "$raw_body" "$compressed_body" \
    "$compressed_boundary_raw" "$compressed_boundary" \
    "$boundary_response" \
    "$created_credentials"
}
trap cleanup EXIT

https_url="https://${host}:${https_port}"
"$apachectl_bin" -t >/dev/null

expect_status() {
  expected=$1
  label=$2
  shift 2
  status=$(curl_local --silent --show-error --max-time 10 --max-redirs 0 \
    --output /dev/null --write-out '%{http_code}' "$@")
  if [ "$status" != "$expected" ]; then
    echo "${label}: expected HTTP ${expected}, got ${status}" >&2
    exit 1
  fi
}

expect_json_status() {
  expected=$1
  label=$2
  output=$3
  shift 3
  status=$(curl_local --silent --show-error --max-time 10 --max-redirs 0 \
    --output "$output" --write-out '%{http_code}' "$@")
  if [ "$status" != "$expected" ] || ! grep -Eq '"error"' "$output"; then
    echo "${label}: expected Athenaeum JSON HTTP ${expected}, got ${status}" >&2
    exit 1
  fi
}

http_status=$(
  curl_local --silent --show-error --max-time 10 --max-redirs 0 \
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
echo "plaintext /v1 refusal: HTTP ${http_status}"

echo "checking real proxy client buckets and header overwrite"
for attempt in $(seq 1 20); do
  expect_status 401 "loopback client A failure ${attempt}" \
    --interface 127.0.0.2 \
    --header 'X-Forwarded-For: 198.51.100.1' \
    --header 'Authorization: Bearer malformed' \
    "${https_url}/v1/store"
done
expect_status 429 "loopback client A alternate forwarded value" \
  --interface 127.0.0.2 \
  --header 'X-Forwarded-For: 203.0.113.1' \
  --header 'Authorization: Bearer malformed' \
  "${https_url}/v1/store"
sleep 6
expect_status 401 "loopback client A refill" \
  --interface 127.0.0.2 \
  --header 'X-Forwarded-For: 203.0.113.1' \
  --header 'Authorization: Bearer malformed' \
  "${https_url}/v1/store"
expect_status 429 "loopback client A second refill request" \
  --interface 127.0.0.2 \
  --header 'X-Forwarded-For: 203.0.113.1' \
  --header 'Authorization: Bearer malformed' \
  "${https_url}/v1/store"
expect_status 401 "independent loopback client B" \
  --interface 127.0.0.3 \
  --header 'X-Forwarded-For: 198.51.100.1' \
  --header 'Authorization: Bearer malformed' \
  "${https_url}/v1/store"
echo "proxy address/header overwrite: passed"

echo "checking remaining server-wide failure budget (978 after 22 prior failures)"
for index in $(seq 0 977); do
  third=$((index / 254 + 1))
  fourth=$((index % 254 + 1))
  expect_status 401 "server-wide failure ${index}" \
    --interface "127.1.${third}.${fourth}" \
    --header 'Authorization: Bearer malformed' \
    "${https_url}/v1/store"
done
expect_status 429 "server-wide failure budget" \
  --interface 127.2.0.1 \
  --header 'Authorization: Bearer malformed' \
  "${https_url}/v1/store"
echo "server-wide failure budget: passed"

printf '%s\n' "$credential" >> "$created_credentials"
https_post_status=$(
  curl_local --silent --show-error --max-time 10 --max-redirs 0 \
    --request POST --header "Authorization: Bearer ${credential}" \
    --dump-header "$https_headers" --output "$https_post_body" \
    --write-out '%{http_code}' "https://${host}:${https_port}/v1/store"
)
case "$https_post_status" in
  201) ;;
  *)
    echo "HTTPS create did not reach Athenaeum (HTTP $https_post_status)" >&2
    exit 1
    ;;
esac

encode_id() {
  printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=[:space:]'
}

echo "checking store-creation budget (60 successes, 61st refusal)"
for index in $(seq 1 59); do
  token=$(encode_id "w16-smoke-${run_id}${index}-store")
  printf '%s\n' "$token" >> "$created_credentials"
  expect_status 201 "store creation ${index}" \
    --request POST --header "Authorization: Bearer ${token}" \
    "${https_url}/v1/store"
done
extra_token=$(encode_id "w16-over${run_id}-budget-store")
printf '%s\n' "$extra_token" >> "$created_credentials"
expect_status 429 "store creation budget" \
  --request POST --header "Authorization: Bearer ${extra_token}" \
  "${https_url}/v1/store"
echo "store-creation budget: passed"

https_get_status=$(
  curl_local --silent --show-error --max-time 10 --max-redirs 0 \
    --request GET --header "Authorization: Bearer ${credential}" \
    --output "$https_get_body" --write-out '%{http_code}' \
    "https://${host}:${https_port}/v1/store"
)
if [ "$https_get_status" != 200 ] || ! grep -Eq '"epoch"' "$https_get_body"; then
  echo "HTTPS lookup did not return an Athenaeum store (HTTP $https_get_status)" >&2
  exit 1
fi
grep -Fqi 'strict-transport-security:' "$https_headers"
hsts_max_age=$(grep -Eio 'max-age=[0-9]+' "$https_headers" | head -n 1 | cut -d= -f2)
if [ -z "$hsts_max_age" ] || [ "$hsts_max_age" -lt 15552000 ]; then
  echo "HSTS max-age is below the six-month minimum" >&2
  exit 1
fi
echo "authenticated HTTPS create/lookup and HSTS: passed"

if grep -Eiq 'mod_deflate|SetInputFilter|RequestHeader[[:space:]]+.*Content-Encoding' "$apache_config"; then
  echo "active Apache vhost contains a request decompression directive" >&2
  exit 1
fi
echo "active Apache vhost preserves request compression: passed"

echo "checking 16 MiB request boundary"
dd if=/dev/zero of="$large_body" bs=1048576 count=16 2>/dev/null
dd if=/dev/zero of="$oversized_body" bs=1048576 count=16 2>/dev/null
printf '\0' >> "$oversized_body"
expect_json_status 400 "16 MiB body reaches Athenaeum" "$boundary_response" \
  --request PUT --header "Authorization: Bearer ${credential}" \
  --header 'Content-Type: application/json' \
  --data-binary "@${large_body}" "${https_url}/v1/manifests/device-one"
expect_status 413 "body over 16 MiB is refused" \
  --request PUT --header "Authorization: Bearer ${credential}" \
  --header 'Content-Type: application/json' \
  --data-binary "@${oversized_body}" "${https_url}/v1/manifests/device-one"
echo "16 MiB request boundary: passed"

echo "checking compressed-body preservation"
printf '%s' \
  '{"v":1,"kind":"setting","id":"default_program_band","updatedAt":"2026-09-03T00:00:00.000Z","deletedAt":null,"existenceAt":"2026-09-03T00:00:00.000Z","body":{"value":"w16"}}' \
  > "$raw_body"
gzip -c "$raw_body" > "$compressed_body"
blob_hash=$(sha256sum "$raw_body" | awk '{print $1}')
expect_status 201 "compressed blob upload" \
  --request PUT --header "Authorization: Bearer ${credential}" \
  --header 'Content-Type: application/octet-stream' \
  --header 'Content-Encoding: gzip' \
  --data-binary "@${compressed_body}" \
  "${https_url}/v1/blobs/${blob_hash}"
dd if=/dev/urandom of="$compressed_boundary_raw" bs=1048576 count=16 2>/dev/null
gzip -c "$compressed_boundary_raw" > "$compressed_boundary"
expect_json_status 400 "compressed 16 MiB body reaches Athenaeum" \
  "$boundary_response" \
  --request PUT --header "Authorization: Bearer ${credential}" \
  --header 'Content-Type: application/json' \
  --header 'Content-Encoding: gzip' \
  --data-binary "@${compressed_boundary}" \
  "${https_url}/v1/manifests/device-one"
echo "compressed-body preservation: passed"
echo "W16 proxy conformance checks passed"
