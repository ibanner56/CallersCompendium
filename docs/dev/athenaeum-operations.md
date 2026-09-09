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

4. Copy `server/deploy/athenaeum.conf` into Apache's sites directory, replace
   `sync.example.invalid`, install a real certificate, enable the site, and
   reload Apache. The `:80` vhost may serve ACME challenges, but `/v1` must
   remain refused and must never redirect or proxy.
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

## Proxy and security contract

The vhost must preserve `Authorization`, allow a 32 MiB wire body (the
application enforces the 16 MiB decoded manifest limit), avoid decompressing
request bodies, overwrite `X-Forwarded-For` with the connecting client
address, and proxy only over loopback. The application trusts that header only
when the socket peer is loopback; Apache derives it from the underlying
connection peer (`CONN_REMOTE_ADDR`) even if host-level `mod_remoteip` is
enabled, and the application otherwise uses its peer address. The
limits are independent: 10 failures per IP per minute, a burst of 20 failures
per IP, 1,000 failures per minute server-wide, and 60 store creations per
minute. A saturated server-wide failure budget must not block authenticated
access to an existing store.

Use a no-redirect probe after every Apache change in a direct-origin or staging
deployment:

```sh
ATHENAEUM_CREDENTIAL='encoded-credential-for-a-new-disposable-store' \
  ATHENAEUM_APACHE_CONFIG=/etc/apache2/sites-enabled/athenaeum.conf \
  sh server/deploy/smoke_test.sh sync.example.invalid
curl --max-time 10 --max-redirs 0 --include http://sync.example.invalid/v1/store
curl --max-time 10 --include https://sync.example.invalid/v1/store
```

The credential must be new and belong to a disposable test store; the script
deletes stores it creates. If cleanup is rate-limited after the failure-budget
probe, it retries after the rolling 60-second window before reporting failure.
The first request must be a refusal (not 3xx and not an Athenaeum response).
The script then exercises real client buckets and
forwarded-header overwrite through Apache, the 1,000-failure and 60-creation
budgets, the inclusive 16 MiB boundary, compressed-body preservation, and
authenticated Athenaeum create/lookup responses over HTTPS with
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
IPv4** off, and add a cache rule that bypasses cache for
`https://sync.example.invalid/v1/*`. Do not attach a Worker route to
`/v1/*`. A zone-wide HTTPS redirect must exclude `/v1/*`: plaintext Device
Sync requests must remain refusals, not redirects.

Enable Apache's `remoteip` module, then fetch Cloudflare's published trusted
proxy ranges. Write the IPv4 and IPv6 lists separately: the IPv4 endpoint does
not guarantee a trailing newline, and concatenating them directly can create
an invalid CIDR.

```sh
sudo a2enmod remoteip headers
sudo install -d -m 755 /etc/apache2/cloudflare
tmp=$(mktemp)
curl --fail --silent --show-error https://www.cloudflare.com/ips-v4 > "$tmp"
printf '\n' >> "$tmp"
curl --fail --silent --show-error https://www.cloudflare.com/ips-v6 >> "$tmp"
sudo install -m 644 "$tmp" /etc/apache2/cloudflare/trusted-proxies.conf
rm -f "$tmp"
sudo apachectl configtest
sudo systemctl reload apache2
```

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
endpoint still returns the expected unauthenticated `401`. Then change
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
HTTPS must return Athenaeum's unauthenticated `401`. The direct HTTPS request
must fail TLS client-certificate verification without returning an HTTP
response. The standard smoke harness intentionally connects to loopback, so it
cannot run while `SSLVerifyClient require` is enforced; use a direct/staging
topology for that harness and a disposable public create/lookup/delete round
trip for the Cloudflare path.

## Operations

- **Logs:** retain only the redacted Apache access/error logs and container
  stderr according to the host's retention policy. The safe access format
  excludes request targets and headers, so sync IDs and credentials are not
  written. Restrict log access to operators.
- **Alerts:** route JSON lines with `alert.kind` of `quota_exhaustion` or
  `sweep_failure` from container stderr to the on-call notification path.
  Repeated alerts with the same kind, source, and exception type are limited to
  one notification per minute; the next notification includes the aggregate
  count. Payloads contain only a category, source, exception type, and optional
  count; they never contain user content, bearer credentials, sync IDs, or
  device IDs.
- **Quota probe:** in a staging deployment, create data until the service
  returns `507`, record the UTC timestamp and alert/incident URL, then remove
  the staging store.
- **Sweep probe:** in staging, backdate a disposable store beyond 30 days and
  invoke the hourly sweep with a deliberate filesystem failure. Confirm a
  `sweep_failure` alert reaches a human, record the timestamp and incident URL,
  then repeat without the injected failure to verify removal.
- **Retention:** after the sweep, query the disposable store and expect
  "not found". Search ordinary access/error/container logs for its credential,
  sync ID, and content; all must be absent.
- **Break-glass:** obtain an incident/ticket approval before access. Record the
  operator, reason, approval reference, and UTC time in the ticket, then use
  the supported command below. It accepts the raw sync ID on stdin, writes the
  separate audit row before looking up the store or reading the requested
  manifest, and writes only the manifest bytes to stdout:
  ```sh
  printf '%s\n' "$SYNC_ID" | docker exec -i athenaeum \
    /opt/athenaeum/bin/athenaeum --data-dir /var/lib/athenaeum --break-glass \
    --break-glass-device-id device-one > /secure/incident/manifest.bin
  ```
  Use a secure terminal and output path; do not put the sync ID or returned
  content in shell history, ordinary logs, or chat. Inspect the separate
  break-glass database for exactly one row with the derived `id_key` and
  timestamp. Never write this audit row to the ordinary store.
- **Lost ID:** a lost sync ID cannot be recovered by design. Verify ownership
  through the normal support process, explain that the server stores only a
  one-way derived key, and direct the user to create a new store.

## Upgrade, rollback, and release order

Build a new immutable image tag, stop the old container, start the new tag with
the same volume and pepper, and verify the HTTPS and plaintext probes before
declaring success. To roll back, stop the new tag and restart the previous
image; do not replace the volume or pepper. Keep the previous image until the
post-upgrade retention and break-glass checks complete.

Before beta or public client distribution, deploy and smoke-test the compatible
Athenaeum service first. Record the image digest, proxy probe results, alert
exercise, retention result, break-glass audit result, and lost-ID support result
in the release checklist. W16 is not complete until those live records exist.
