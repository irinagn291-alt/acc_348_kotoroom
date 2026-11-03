# Private HIBP email lookup

The iPhone's default email tool opens the official HIBP website. To enable native results, deploy this optional Node 22+ service behind HTTPS and supply an HIBP **Pro or High RPM** subscription with breached account range access. Set the key via your host's secret manager as `HIBP_API_KEY`. The iOS app never needs the key.

Run `node server.mjs`. It listens on loopback port 8787 by default. Configure `PORT` and `BIND_ADDRESS` for your host. Route `POST /v1/email-range` to it. Its JSON body contains only a six-character hex prefix. The iPhone matches the returned suffixes locally. The relay rejects email addresses, full hashes, query strings and unrelated fields. No database is needed.

Use one process with `HIBP_GLOBAL_RPM` at or below your purchased quota (default 10) and `HIBP_PEER_RPM` (default 3). The relay uses the TCP peer for its local limit. With a reverse proxy, apply client limits at the trusted edge and set the relay peer limit appropriately. For multiple replicas, enforce a shared quota at ingress. Disable caching, access logs, request/response capture and tracing for this route at every layer.

Set the iPhone build setting `PIPROOM_HIBP_PROXY_URL` to the full public HTTPS endpoint including `/v1/email-range`, then rebuild. With an empty setting, email checks remain available via the website. Errors on a configured relay never silently send a full address to another service.

Run `node --test server.test.mjs` for the relay contract checks. See [HIBP API documentation](https://haveibeenpwned.com/API/v3).
