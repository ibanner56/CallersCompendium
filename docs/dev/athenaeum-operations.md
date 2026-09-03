# Athenaeum operations runbook

This runbook is the W16 reference deployment for the Device Sync service. The
supported topology is a Linux host running Apache and a Docker container with
`--network host`. Apache terminates TLS on `:443` and proxies `/v1/` to the
container's loopback listener on `127.0.0.1:33333`. Do not use a bridged
container for this configuration: it changes the socket peer and invalidates
the loopback-only forwarded-address trust boundary.

## First deployment

1. Install Docker, Apache 2.4, and the Apache modules `ssl`, `headers`, `proxy`,
   `proxy_http`, `reqtimeout`, and `rewrite`.
2. Create a dedicated directory owned by the container user for the three
   SQLite databases and blob directory:

   ```sh
   sudo install -d -o 65534 -g 65534 -m 700 /var/lib/athenaeum
   openssl rand -base64 32 | sudo tee /root/athenaeum.pepper >/dev/null
   sudo chmod 600 /root/athenaeum.pepper
   sudo sh -c 'printf "ATHENAEUM_PEPPER=%s\n" "$(cat /root/athenaeum.pepper)" > /root/athenaeum.env'
   sudo chmod 600 /root/athenaeum.env
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
   docker run --detach --name athenaeum \
     --network host \
     --read-only \
     --tmpfs /tmp:rw,noexec,nosuid,size=64m \
     --mount type=bind,src=/var/lib/athenaeum,dst=/var/lib/athenaeum \
     --env-file /root/athenaeum.env \
     callers-compendium-athenaeum:0.1
   ```

   Use a Docker/host secret manager instead of the env file in production; do
   not put the pepper in command history or an image layer. The service runs as
   the unprivileged `nobody` user.
   Port `33333` is reserved for this service and must not be published or
   exposed on a non-loopback interface.

## Proxy and security contract

The vhost must preserve `Authorization`, accept bodies up to 16 MiB, avoid
decompressing request bodies, overwrite `X-Forwarded-For` with the connecting
client address, and proxy only over loopback. The application trusts that
header only when the socket peer is loopback; it otherwise uses the peer
address. The limits are independent: 10 failures per IP per minute, a burst of
20 failures per IP, 1,000 failures per minute server-wide, and 60 store
creations per minute. A saturated server-wide failure budget must not block
authenticated access to an existing store.

Use a no-redirect probe after every Apache change:

```sh
ATHENAEUM_CREDENTIAL='encoded-credential-for-a-disposable-store' \
  sh server/deploy/smoke_test.sh sync.example.invalid
curl --max-time 10 --max-redirs 0 --include http://sync.example.invalid/v1/store
curl --max-time 10 --include https://sync.example.invalid/v1/store
```

The credential must belong to a disposable test store. The first request must
be a refusal (not 3xx and not an Athenaeum response); the script then requires
authenticated Athenaeum create/lookup responses over HTTPS and
`Strict-Transport-Security`.

## Operations

- **Logs:** retain only the redacted Apache access/error logs and container
  stderr according to the host's retention policy. The safe access format
  excludes request targets and headers, so sync IDs and credentials are not
  written. Restrict log access to operators.
- **Alerts:** route JSON lines with `alert.kind` of `quota_exhaustion` or
  `sweep_failure` from container stderr to the on-call notification path.
  Alert payloads contain only a category, source, and exception type; they
  never contain user content, bearer credentials, sync IDs, or device IDs.
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
  operator, reason, approval reference, and UTC time in the ticket, perform one
  read, then inspect the separate break-glass database for exactly one row with
  the derived `id_key` and timestamp. Never write this audit row to the ordinary
  store.
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
