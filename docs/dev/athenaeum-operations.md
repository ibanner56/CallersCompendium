# Athenaeum operations runbook

This runbook is the W16 reference deployment for the Device Sync service. The
supported topology is a Linux host running Apache and a Docker container with
`--network host`. Apache terminates TLS on `:443` and proxies `/v1/` to the
container's loopback listener on `127.0.0.1:33333`. Do not use a bridged
container for this configuration: it changes the socket peer and invalidates
the loopback-only forwarded-address trust boundary.

## First deployment

1. Install Docker, Apache 2.4.40 or newer, and the Apache modules `ssl`,
   `headers`, `proxy`, `proxy_http`, `reqtimeout`, and `rewrite`.

   Then check that the root filesystem is not mounted with `discard`:

   ```sh
   findmnt -no OPTIONS /
   ```

   Some VPS images set it (Hostinger's Ubuntu 26 image did). With it, ext4 sends
   the disk a discard for the freed blocks after every large deletion, and on a
   slow virtual disk the journal then waits behind it: on the reference KVM
   host, synced 4 KB writes fell from about 700 a second to about 5 for over
   half an hour after one `rm -rf` of a large directory. The server's
   hourly sweep deletes expired stores' blob directories, so production hits
   this too. If the output contains `discard`, turn it off now and in
   `/etc/fstab`, and let the weekly `fstrim.timer` trim in one batch at a quiet
   hour instead:

   ```sh
   sudo mount -o remount,nodiscard /
   sudo sed -i.bak -e '/[[:space:]]\/[[:space:]]/ s/discard,//' \
     -e '/[[:space:]]\/[[:space:]]/ s/,discard\([[:space:]]\)/\1/' \
     -e '/[[:space:]]\/[[:space:]]/ s/\([[:space:]]\)discard\([[:space:]]\)/\1defaults\2/' /etc/fstab
   sudo systemctl daemon-reload && sudo findmnt --verify
   sudo install -d /etc/systemd/system/fstrim.timer.d
   printf '%s\n' '[Timer]' 'OnCalendar=' 'OnCalendar=Sun 04:00' \
     'RandomizedDelaySec=0' 'Persistent=false' |
     sudo tee /etc/systemd/system/fstrim.timer.d/override.conf >/dev/null
   sudo systemctl daemon-reload && sudo systemctl enable --now fstrim.timer
   ```

   Check the root line of `/etc/fstab` afterwards: a reboot with `discard`
   still there turns it back on. A remount does not cancel discards already
   queued; a reboot drops them. To check the disk, time 200 synced writes
   before and after deleting a large directory; on a healthy disk each run
   takes well under a second:

   ```sh
   sudo dd if=/dev/zero of=/var/lib/dd-sync-test bs=4k count=200 oflag=dsync
   sudo rm -f /var/lib/dd-sync-test
   ```
2. Create a dedicated directory owned by the container user for the three
   SQLite databases and blob directory:

   ```sh
   sudo install -d -o 65534 -g 65534 -m 700 /var/lib/athenaeum
   openssl rand -base64 32 | sudo tee /root/athenaeum.pepper >/dev/null
   sudo chmod 600 /root/athenaeum.pepper
   sudo sh -c 'printf "ATHENAEUM_PEPPER=%s\n" "$(cat /root/athenaeum.pepper)" > /root/athenaeum.env'
   sudo chmod 600 /root/athenaeum.env
   ```

   Reserve the listener port across host restarts without discarding any
   existing reservations:

   ```sh
   port_reserved() {
     awk -v reserved="$1" -v port=33333 '
       BEGIN {
         count = split(reserved, entries, ",")
         for (i = 1; i <= count; i++) {
           bounds = split(entries[i], range, "-")
           low = range[1] + 0
           high = (bounds == 2 ? range[2] : range[1]) + 0
           if (low <= port && port <= high) exit 0
         }
         exit 1
       }'
   }
   reserved=$(cat /proc/sys/net/ipv4/ip_local_reserved_ports)
   if ! port_reserved "$reserved"; then
     reserved="${reserved:+$reserved,}33333"
   fi
   printf 'net.ipv4.ip_local_reserved_ports=%s\n' "$reserved" |
     sudo tee /etc/sysctl.d/99-athenaeum-port.conf >/dev/null
   sudo sysctl --system
   port_reserved "$(cat /proc/sys/net/ipv4/ip_local_reserved_ports)"
   ```

3. Build the image from the repository root:

   ```sh
   docker build --file server/Dockerfile --tag callers-compendium-athenaeum:0.1 .
   ```

4. Install the redacting error logger and status page, then copy
   `server/deploy/athenaeum.conf` into Apache's sites directory:

   ```sh
   sudo install -m 755 server/deploy/athenaeum-error-log \
     /usr/local/sbin/athenaeum-error-log
   sudo install -d -m 755 /var/www/athenaeum
   sudo install -m 644 server/deploy/status/index.html \
     server/deploy/status/icon.svg /var/www/athenaeum/
   ```

   Replace `sync.example.invalid` in the vhost with the deployment hostname,
   install a matching certificate, enable the site, and reload Apache. The
   `:80` vhost may serve ACME challenges, but `/v1` must remain refused and must
   never redirect or proxy. Both vhosts serve the status page at `/` and proxy
   the `/heartbeat` liveness check (which takes no sync ID); only the TLS vhost proxies
   `/v1/`.
5. Start the container with host networking and the persistent volume:

   ```sh
   sudo docker run --detach --name athenaeum \
     --network host \
     --restart unless-stopped \
     --read-only \
     --tmpfs /tmp:rw,noexec,nosuid,size=64m \
     --mount type=bind,src=/var/lib/athenaeum,dst=/var/lib/athenaeum \
     --env-file /root/athenaeum.env \
     callers-compendium-athenaeum:0.1
   ```

   Use a Docker/host secret manager instead of the env file in production; do
   not put the pepper in command history or an image layer. The service runs as
   the unprivileged `nobody` user.
   Verify the reservation before every first start with the range-aware
   `port_reserved` check from step 2 (not an exact-token grep). Port `33333`
   must not be published or exposed on a non-loopback interface.
6. Install the alert forwarder, which emails each alert line the container
   writes (see *Alerts* under Operations). It needs a working `mail` command;
   with msmtp:

   ```sh
   sudo apt install msmtp msmtp-mta bsd-mailx
   sudo install -m 755 server/deploy/athenaeum-alert-email \
     /usr/local/sbin/athenaeum-alert-email
   sudo install -m 644 server/deploy/athenaeum-alert-email.service \
     /etc/systemd/system/athenaeum-alert-email.service
   ```

   Set `ATHENAEUM_ALERT_TO` in the unit to the on-call address. Configure
   `/etc/msmtprc` (mode 600) for the SMTP account and keep its password in a
   separate mode-600 file read with `passwordeval`, never in the unit. Answer
   **No** when the msmtp package asks about AppArmor: its profile stops
   `passwordeval` from running `cat` on a file under `/root`, and sending then
   fails with `cat: Permission denied` and sendmail exit 78. Then enable the
   unit and send a test through the same path:

   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now athenaeum-alert-email.service
   printf '%s\n' '{"alert":{"kind":"sweep_failure","source":"manual_test","errorType":"Test"}}' |
     sudo ATHENAEUM_ALERT_TO=on-call@example.invalid /usr/local/sbin/athenaeum-alert-email
   ```

   The forwarder reads the container log from its end, so an alert written
   while it is not running is never sent: install it before the service takes
   traffic, and on a move to a new host, before cutover. While the container
   is stopped the unit restarts every five seconds; that is expected.

## Proxy and security contract

The vhost must preserve `Authorization`, allow a 32 MiB wire body (the
application enforces the 16 MiB decoded manifest limit and also caps gzip
bytes on the wire per route, so `LimitRequestBody` is defence in depth), avoid decompressing
request bodies, overwrite `X-Forwarded-For` with the connecting client
address, and proxy only over loopback. The application trusts that header only
when the socket peer is loopback, and then reads only the rightmost entry, so a
client-supplied prefix cannot choose the rate-limit key even behind a proxy that
appends instead of overwriting. The reference vhost sets it from the
underlying connection peer (`CONN_REMOTE_ADDR`) and turns off mod_proxy's own
forwarding headers with `ProxyAddHeaders Off`. Both are needed: with mod_proxy's
default (`ProxyAddHeaders On`), Apache appends a second entry after the one
`RequestHeader set` wrote, that entry is `REMOTE_ADDR` *after* any host-level
`mod_remoteip` rewrite, and it is the rightmost entry the application reads. On
a host with `mod_remoteip` enabled, the rate-limit key would then be whatever
address remoteip resolved, which is client-chosen if remoteip trusts a header
the client can send. With no forwarded header the application uses its peer
address. Either way the
rate-limit key is the IPv4 address, or for IPv6 the /64 (the address's first 64
bits), because one IPv6 subscriber can present 2^64 addresses inside its
delegated /64; an IPv4-mapped IPv6 address (`::ffff:a.b.c.d`) is keyed as its
IPv4 address. A deployment that enforces a per-IP limit in the proxy too should
apply the same /64 rule. The
limits are independent: 5 requests per IP per second with a burst of 300, 15
requests per store per second with a burst of 600, 10 failures per IP per
minute, a burst of 20 failures per IP, 1,000 failures per minute server-wide,
5 store creations per IP (refilled at 5 an hour), and 60 store creations per
minute server-wide. There is deliberately no server-wide request-rate limit
(spec §5.4); `server/tool/load_test.dart` measures what the host sustains. A
saturated server-wide failure budget must not block requests that resolve an
existing store. Large-body requests (manifest and blob uploads, and
`POST /v1/blobs/missing`) are also counted while in flight: 4 per IP, then
`429`, and 16 server-wide, then `503`. See *Server-wide limits* below for how to
change these and the free-space floor.

**Existing hosts:** a vhost installed before `ProxyAddHeaders Off` was added to
the reference configuration does not have it, and nothing deploys it for you:
the release workflow replaces the container, not the Apache configuration. Add
the line by hand inside the Athenaeum `*:443` vhost, next to the
`RequestHeader set X-Forwarded-For` directive, then check and reload:

```sh
# Edit the file behind the enabled site; sudoedit will not follow the symlink.
sudoedit "$(readlink -f /etc/apache2/sites-enabled/athenaeum.conf)"
sudo apachectl -t && sudo systemctl reload apache2
```

The smoke test below refuses a vhost without it.

Use a no-redirect probe after every Apache change in a direct-origin or staging
deployment:

```sh
ATHENAEUM_CREDENTIAL='encoded-sync-id-of-a-new-disposable-store' \
  ATHENAEUM_APACHE_CONFIG=/etc/apache2/sites-enabled/athenaeum.conf \
  sh server/deploy/smoke_test.sh sync.example.invalid
curl --max-time 10 --max-redirs 0 --include http://sync.example.invalid/v1/store
curl --max-time 10 --include https://sync.example.invalid/v1/store
```

The encoded sync ID must be new and belong to a disposable test store; the script
deletes stores it creates. If cleanup is rate-limited after the failure-budget
probe, it retries after the rolling 60-second window before reporting failure.
The first request must be a refusal (not 3xx and not an Athenaeum response).
The script refuses a vhost whose TLS vhost lacks `ProxyAddHeaders Off`, then
exercises real client buckets and forwarded-header overwrite through Apache
(including forged `X-Forwarded-For`, `X-Real-IP`, `CF-Connecting-IP`,
`True-Client-IP`, `X-Client-IP`, and any `RemoteIPHeader` named in the vhost or
in `conf-enabled/` or `mods-enabled/` under `ATHENAEUM_APACHE_ROOT`, default
`/etc/apache2`; sent from a loopback client, none of them may change its
rate-limit key. The probe catches a vhost that does not overwrite the header,
but an appended remoteip-resolved entry shows up there only where
`mod_remoteip` trusts loopback, so on hosts that trust only CDN ranges the
`ProxyAddHeaders Off` check is the guard), the 1,000-failure budget, the
5-per-IP and 60-per-minute creation budgets, the inclusive 16 MiB boundary,
compressed-body preservation, and
Athenaeum create/lookup responses over HTTPS with
`Strict-Transport-Security`. The harness also inspects the active vhost
configuration to ensure no request decompression directive is enabled;
the successful gzip upload then exercises the backend's own gzip decoder.
Run it against a freshly restarted staging container because the failure
and creation budgets are in memory. Save the labeled output as release
evidence. The harness uses curl `--resolve` to connect both listeners to
host loopback while preserving the configured hostname for Host/SNI.

## Cloudflare proxy topology

Cloudflare proxying is an optional topology change, not a DNS-only change. It
changes the Apache connection peer from the client to a Cloudflare address, so
the vhost must be configured before the DNS record is proxied.

In Cloudflare, configure the zone to use **Full (strict)** TLS, leave **Pseudo
IPv4** off, and add a cache-bypass rule whose filter matches both the exact
`/v1` path and every `/v1/` descendant. For example:

```txt
(http.host eq "sync.example.invalid" and
 (http.request.uri.path eq "/v1" or starts_with(http.request.uri.path, "/v1/")))
```

Do not attach a Worker route that matches `/v1` or `/v1/*`. A zone-wide HTTPS
redirect must exclude both paths: plaintext Device Sync requests must remain
refusals, not redirects.

Enable Apache's `remoteip` module, then fetch Cloudflare's published trusted
proxy ranges. Write the IPv4 and IPv6 lists separately: the IPv4 endpoint does
not guarantee a trailing newline, and concatenating them directly can create
an invalid CIDR. Do not replace the existing list unless both downloads
succeed; a partial list collapses affected clients into a Cloudflare-edge
rate-limit bucket.

```sh
sudo a2enmod remoteip headers
sudo install -d -m 755 /etc/apache2/cloudflare
sudo tee /usr/local/sbin/athenaeum-refresh-cloudflare-proxies >/dev/null <<'EOF'
#!/bin/sh
set -eu

directory=/etc/apache2/cloudflare
target=$directory/trusted-proxies.conf
candidate=$(mktemp "$directory/.trusted-proxies.conf.XXXXXX")
previous=
cleanup() {
  [ -z "$candidate" ] || rm -f "$candidate"
  [ -z "$previous" ] || rm -f "$previous"
}
trap cleanup EXIT HUP INT TERM

curl --fail --silent --show-error https://www.cloudflare.com/ips-v4 > "$candidate"
printf '\n' >> "$candidate"
curl --fail --silent --show-error https://www.cloudflare.com/ips-v6 >> "$candidate"
chmod 644 "$candidate"

if [ -e "$target" ]; then
  previous=$(mktemp "$directory/.trusted-proxies.previous.XXXXXX")
  cp -p "$target" "$previous"
fi
mv -f "$candidate" "$target"
candidate=

if apachectl configtest && systemctl reload apache2; then
  exit 0
fi

if [ -n "$previous" ]; then
  mv -f "$previous" "$target"
  previous=
else
  rm -f "$target"
fi
if ! apachectl configtest || ! systemctl reload apache2; then
  echo "previous trusted-proxy list restored, but Apache reload failed" >&2
fi
exit 1
EOF
sudo chmod 755 /usr/local/sbin/athenaeum-refresh-cloudflare-proxies
sudo /usr/local/sbin/athenaeum-refresh-cloudflare-proxies
sudo tee /etc/systemd/system/athenaeum-cloudflare-proxies.service >/dev/null <<'EOF'
[Unit]
Description=Refresh Cloudflare trusted proxy ranges for Athenaeum
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/athenaeum-refresh-cloudflare-proxies
EOF
sudo tee /etc/systemd/system/athenaeum-cloudflare-proxies.timer >/dev/null <<'EOF'
[Unit]
Description=Weekly Athenaeum Cloudflare trusted proxy range refresh

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now athenaeum-cloudflare-proxies.timer
```

The updater downloads both address families into a same-directory candidate and
atomically replaces the live list only after both succeed. If Apache rejects
the candidate or cannot reload, it restores the previous list. The timer runs
weekly after downtime and the service exits nonzero on every failed download,
config test, or Apache reload; route that service failure to the host's
operator-alert path.

Inside only the Athenaeum `*:443` vhost, configure the trusted client address
and replace the reference `RequestHeader` directive:

```apache
RemoteIPHeader CF-Connecting-IP
RemoteIPTrustedProxyList /etc/apache2/cloudflare/trusted-proxies.conf
RequestHeader set X-Forwarded-For expr=%{REMOTE_ADDR}
```

`CF-Connecting-IP` is a single client address. Apache accepts it only when the
socket peer is in the published Cloudflare ranges; it then derives
`X-Forwarded-For` from the resolved `REMOTE_ADDR`. Do not use an incoming
`X-Forwarded-For` value, and do not use Cloudflare Pseudo IPv4's **Overwrite
Headers** mode.

When the host also serves non-Cloudflare sites on `:80` or `:443`, do not add a
host-wide Cloudflare-only firewall rule. Instead, require Cloudflare
Authenticated Origin Pulls only in the Athenaeum HTTPS vhost. Download
Cloudflare's global Origin Pull CA:

```sh
sudo curl --fail --silent --show-error \
  https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  --output /etc/apache2/cloudflare/origin-pull-ca.pem
```

Add the following after `SSLCertificateKeyFile` in that `*:443` vhost, initially
using `optional`:

```apache
SSLCACertificateFile /etc/apache2/cloudflare/origin-pull-ca.pem
SSLVerifyClient optional
SSLVerifyDepth 1
```

Reload Apache, enable **Global Authenticated Origin Pulls** under
**SSL/TLS > Origin Server** in Cloudflare, and confirm the proxied HTTPS
endpoint still returns the expected `401` for a request without a sync ID. Then change
`SSLVerifyClient optional` to `SSLVerifyClient require` and reload Apache.
Global Origin Pulls causes Cloudflare to present its certificate for proxied
hostnames in the zone; enforcement remains Athenaeum-only because this vhost
alone requires client authentication.

Verify both paths after enforcement. Substitute the origin's real public IP:

```sh
curl --max-time 15 --max-redirs 0 --include \
  http://sync.example.invalid/v1/store
curl --max-time 15 --include \
  https://sync.example.invalid/v1/store
curl --noproxy '*' --connect-timeout 5 --max-time 15 \
  --resolve sync.example.invalid:443:ORIGIN_IP \
  --include https://sync.example.invalid/v1/store
```

The public HTTP request must be a refusal rather than a redirect, and public
HTTPS must return Athenaeum's `401` for a request without a sync ID. The direct HTTPS request
must fail TLS client-certificate verification without returning an HTTP
response. The standard smoke harness intentionally connects to loopback, so it
cannot run while `SSLVerifyClient require` is enforced; use a direct/staging
topology for that harness and a disposable public create/lookup/delete round
trip for the Cloudflare path. That lifecycle probe does not prove that
Cloudflare client-IP handling works.

To verify the Cloudflare client-IP path, use two real external clients with
different public egress addresses during a quiet maintenance window. From each
client, first record the address Cloudflare sees:

```sh
curl --silent https://sync.example.invalid/cdn-cgi/trace |
  awk -F= '$1 == "ip" { print $2 }'
```

Leave client A idle for two minutes so its burst bucket is full. Then send 21
invalid requests concurrently and change the supplied `X-Forwarded-For` value
on the immediate follow-up. The concurrent batch must contain exactly 20
`401` responses and one `429`; the changed-header follow-up must also return
`429`. This proves that a client cannot escape its rate-limit bucket by
spoofing that header.

```sh
sleep 120
endpoint='https://sync.example.invalid/v1/store'
request_status() {
  curl --noproxy '*' --silent --show-error --max-time 15 \
    --output /dev/null --write-out '%{http_code}\n' \
    --header 'Authorization: Bearer invalid-credential' \
    --header "$1" "$endpoint"
}

responses=$(mktemp -d)
cleanup_responses() {
  find "$responses" -type f -delete
  rmdir "$responses"
}
trap cleanup_responses EXIT HUP INT TERM
for attempt in $(seq 1 21); do
  request_status 'X-Forwarded-For: 198.51.100.1' > "$responses/$attempt" &
done
wait
test "$(grep -hcx 401 "$responses"/* | awk '{ total += $1 } END { print total + 0 }')" = 20
test "$(grep -hcx 429 "$responses"/* | awk '{ total += $1 } END { print total + 0 }')" = 1
test "$(request_status 'X-Forwarded-For: 203.0.113.1')" = 429
```

While client A is still rate-limited, send one request from client B with the
same invalid authorization. It must return `401`, not `429`. Correlate each
request with the redacted Apache access log by timestamp: its `%h` client
address must match the address reported by `/cdn-cgi/trace`, never a
Cloudflare range. This verifies both independent client buckets and the
trusted `CF-Connecting-IP` path without logging sync IDs or request
headers.

```sh
curl --noproxy '*' --silent --show-error --max-time 15 \
  --output /dev/null --write-out '%{http_code}\n' \
  --header 'Authorization: Bearer invalid-credential' \
  --header 'X-Forwarded-For: 203.0.113.1' \
  https://sync.example.invalid/v1/store
```

## Server-wide limits

Every store quota is per store, so three limits protect the server as a whole
(spec §5.4). Each is set by an environment variable or the matching
command-line option; the defaults suit the reference host.

| Variable | Option | Default | What it does |
| --- | --- | --- | --- |
| `ATHENAEUM_MIN_FREE_BYTES` | `--min-free-bytes` | `1073741824` (1 GiB) | Blob and manifest uploads answer `507` while the filesystem holding `/var/lib/athenaeum` has less free space than this. Lookups, downloads, `POST /v1/blobs/missing`, store creation, every delete, and a manifest upload no larger than the one that device already has keep working, so a user can still shrink a device's share by turning on *Skip unused imported dances*. `0` turns the floor off. |
| `ATHENAEUM_MAX_LARGE_BODIES` | `--max-large-bodies` | `16` | Manifest `PUT`s, blob `PUT`s (single and batch) and `POST /v1/blobs/missing` requests handled at once, server-wide; one more answers `503` with `Retry-After: 5`. Each can hold up to 16 MiB in memory while it is read and stored. |
| `ATHENAEUM_MAX_LARGE_BODIES_PER_IP` | `--max-large-bodies-per-ip` | `4` | The same requests one client address (an IPv4 address or an IPv6 /64) may have in flight; one more answers `429` with `Retry-After: 5`. |

Set them in `/root/athenaeum.env` beside the pepper, one `NAME=value` line
each, and restart the container. Prefer the variables to the options: the
release workflow's deploy recreates the container with the env file and the
image's default arguments, so options passed after the image name are lost at
the next release, while the env file is kept. A counted request whose body has
not arrived whole after 60 seconds has its connection closed and its slot
released, so a client sending its body slowly, or not at all, cannot hold a
slot for longer than that; the deadline is not configurable.

The container reads free space with `statvfs(3)` on the bind-mounted data
directory, which reports the host filesystem behind the mount. If the server
cannot read it, it writes `Athenaeum cannot read free space on this platform;
the --min-free-bytes floor is not enforced` to stderr at startup and admits
every write; the reference image on 64-bit Linux always can. Keep the floor
above what the large-body requests in flight can write at once
(`ATHENAEUM_MAX_LARGE_BODIES` × 16 MiB): a write admitted just above the floor
can still land.

A `507` from the floor raises a `quota_exhaustion` alert whose `source` is
`free_space_floor` and `errorType` is `FreeSpaceBelowFloor`. Clients show it as
a full store, the nearest message they have, and do not retry a `507` by
themselves (spec §5.3). Grow the disk, or free space on the host: the hourly
sweep deletes the blob files of expired stores, but SQLite reuses the pages
their rows held rather than returning them to the filesystem, so reaping does
not shrink `athenaeum.sqlite`. Each user's next sync that they start then
succeeds.

The server-wide cap refusing a request raises a `capacity_exhaustion` alert
(`source` `large_bodies`). Occasional ones mean the cap is tight for the load;
a steady stream with ordinary traffic means clients are holding slots open, and
the Apache access log shows from where. Reinstall
`server/deploy/athenaeum-alert-email` from step 6 of the first deployment so the
forwarder sends this kind too.

## Operations

- **Logs:** retain only the redacted Apache access/error logs and container
  stderr according to the host's retention policy. The safe access format
  excludes request targets and headers, so sync IDs, in plain or encoded
  form, are not written. Restrict log access to operators.
- **Alerts:** route JSON lines with `alert.kind` of `quota_exhaustion`,
  `sweep_failure` or `capacity_exhaustion` from container stderr to the
  on-call notification path. A
  `quota_exhaustion` alert with `source` `free_space_floor` means the host's
  disk is below the free-space floor (see *Server-wide limits*), not that one
  store is full. The
  reference path is the email forwarder installed in step 6 of the first
  deployment (`server/deploy/athenaeum-alert-email` and its unit); a failed
  send is logged to the unit's journal and skipped.
  Repeated alerts with the same kind, source, and exception type are limited to
  one notification per minute; the next notification includes the aggregate
  count. Payloads contain only a category, source, exception type, and optional
  count; they never contain user content, sync IDs (plain or encoded), or
  device IDs.
- **Quota probe:** in a staging deployment, create data until the service
  returns `507`, record the UTC timestamp and alert/incident URL, then remove
  the staging store.
- **Sweep probe:** in staging, backdate a disposable store beyond 30 days and
  invoke the hourly sweep with a deliberate filesystem failure. Confirm a
  `sweep_failure` alert reaches a human, record the timestamp and incident URL,
  then repeat without the injected failure to verify removal.
- **Retention:** after the sweep, query the disposable store and expect
  "not found". Search ordinary access/error/container logs for its sync ID, plain
  and encoded, and its content; all must be absent.
- **Break-glass:** obtain an incident/ticket approval before access. Record the
  operator, reason, approval reference, and UTC time in the ticket, then use
  the supported command below; never read the blob directory or SQLite
  directly, because that bypasses the audit. It accepts the raw sync ID on
  stdin and reads exactly one item per run: one device's manifest
  (`--break-glass-device-id <device-id>`) or one blob
  (`--break-glass-blob <hash>`), in the store's current epoch unless
  `--break-glass-epoch <epoch>` names another. The blob hashes a device holds
  are the values inside its manifest's `records` map (kind, then record ID,
  then hash; spec §4.5), so read the manifest first. Before
  looking up the store, the command writes, in one transaction, the access row
  (`break_glass_access`: derived `id_key`, time) and a row naming the item
  (`break_glass_reads`: `manifest` or `blob`, `id_key`, epoch, device ID or
  blob hash, time); when no epoch was given it then records the current one.
  If either write fails it exits `1` without reading anything. The audit never
  holds the item's content. It writes only the item's bytes to stdout:
  ```sh
  printf '%s\n' "$SYNC_ID" | docker exec -i athenaeum \
    /opt/athenaeum/bin/athenaeum --data-dir /var/lib/athenaeum --break-glass \
    --break-glass-device-id device-one > /secure/incident/manifest.bin
  printf '%s\n' "$SYNC_ID" | docker exec -i athenaeum \
    /opt/athenaeum/bin/athenaeum --data-dir /var/lib/athenaeum --break-glass \
    --break-glass-blob "$BLOB_HASH" > /secure/incident/blob.bin
  ```
  Options that do not name exactly one valid item (both or neither of
  `--break-glass-device-id` and `--break-glass-blob`, a malformed device ID,
  hash, or epoch) exit `2` before the sync ID is read, and record nothing.
  The command is a **read**: it opens `athenaeum.sqlite` read-only and runs
  none of the server's startup work (no schema or index creation, manifest
  indexing, orphan-blob reconcile, or pending-deletion retry), so it is safe to
  run against the live volume and neither blocks nor is blocked by the running
  server's writes to `athenaeum.sqlite`. Only the break-glass log database is
  written, which is where the audit rows go. The running server's retention
  sweep writes that database too, so each side waits up to 250 ms for the
  other; past that, this command exits with `break-glass read failed` (re-run
  it) or the sweep reports a `break_glass_retention` failure. It never creates
  `athenaeum.sqlite`: if the server has never run on the volume the command
  fails (`SqliteException`) rather than reporting "store not found" against a
  fresh empty file. Run it as the same user as the server, or with write access
  to the data directory: a read-only connection to a WAL database still needs
  the `-shm` file, and creates it if the server has shut down cleanly and left
  no `-wal`/`-shm`.
  Use a secure terminal and output path; do not put the sync ID or returned
  content in shell history, ordinary logs, or chat. Inspect the separate
  break-glass database for one `break_glass_access` row and one
  `break_glass_reads` row per run, with the derived `id_key`, the item read,
  and the timestamp. Never write these audit rows to the ordinary store. Then
  add an entry to
  [`docs/user/breakglass-access-record.md`](../user/breakglass-access-record.md)
  saying what was read by kind and count, not by hash or device ID, and never
  its content. After 30 days the hourly sweep nulls the `id_key` of the
  access row and the `id_key`, epoch, device ID, and hash of the read row,
  leaving the time and, on the read row, the kind.
- **Lost ID:** a lost sync ID cannot be recovered by design. Verify ownership
  through the normal support process, explain that the server stores only a
  one-way derived key, and direct the user to create a new store.

## Upgrade, rollback, and release order

Before deploying a server release with a free-space floor for the first time,
check `df -B1 --output=avail /var/lib/athenaeum` on the host. Below the
floor (1 GiB unless `ATHENAEUM_MIN_FREE_BYTES` says otherwise), every upload
answers `507` from the moment the new container starts.

Build a new immutable image tag, stop the old container, start the new tag with
the same volume and pepper, and verify the HTTPS and plaintext probes before
declaring success. To roll back, stop the new tag and restart the previous
image; do not replace the volume or pepper. Keep the previous image until the
post-upgrade retention and break-glass checks complete.

Startup indexes the blob references of any manifest the reference index does
not cover ([sync-spec §7.3](../design/sync-spec.md#73-ttl-and-garbage-collection)).
The first start of an image with the index reads every stored manifest body
once, so it takes longer than later starts; afterwards it reads only manifests
an earlier image wrote, which is what a rollback followed by a fresh upgrade
leaves behind. Rolling back is safe without further steps: the earlier image
ignores the index, and the next upgrade rebuilds whatever it changed.

An image older than the `break_glass_reads` table ignores that table, so while
it runs its sweep does not null the table's `id_key`, epoch, device ID, or
hash after 30 days. The next upgrade's first sweep nulls every row then past
the period. Do not leave a host on such an image for longer than the period
after a break-glass read.

The release workflow performs this upgrade itself: its `deploy_server` job builds
`callers-compendium-athenaeum:<version>` from the tagged commit and swaps the
container before the mobile uploads and the update manifest
([Deploying the Athenaeum server](releasing.md#deploying-the-athenaeum-server)).
A failed job after the old container is removed leaves you to roll back by hand
as above.

Before beta or public client distribution, deploy and smoke-test the compatible
Athenaeum service first. Record the image digest, proxy probe results, alert
exercise, retention result, break-glass audit result, and lost-ID support result
in the release checklist. W16 is not complete until those live records exist.
