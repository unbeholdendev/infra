# LNURL

Unbeholden LNURL runs on goddard through bitcoinix, with LND as its node. It
serves the Lightning Address `*@unbeholden.dev`. The website on Giran proxies
`/.well-known/lnurlp/` to `LNURL_URL`, which is
`https://lnurl.home.unbeholden.dev`. Traefik serves that name with the wildcard
certificate and proxies to `192.168.4.11:8081` through a selectorless Service
and a manual EndpointSlice. goddard accepts that port only from the worker,
`192.168.4.133`, where Traefik runs, and the service trusts its
`X-Forwarded-*` headers. If Traefik moves to another node, update the firewall
rule and `trusted_proxies` in `nixos/goddard.nix`.

The service holds settlement cursors and zap receipts in
`/var/lib/unbeholden-lnurl` and its keys in `/etc/nix-bitcoin-secrets`. Back
both up. A new Nostr key changes the `nostrPubkey` that wallets have seen.

## Move from aden

goddard reads two files that you copy from aden:
`unbeholden-lnurl-nostr`, the Nostr key that aden mounts as
`/run/secrets/nostr.key`, and `unbeholden-lnurl-ntfy-token`, the ntfy token
from aden's `config.yml`, with no trailing newline. bitcoinix generates a new
verify key, so verify URLs that aden issued stop working.

1. Merge, and check that Flux has applied `lnurl`.
2. On aden, stop the container: `docker compose down` in
   `~/unbeholden-lnurl`. Payments fail from here until step 6.
3. Copy the Nostr key to `/etc/nix-bitcoin-secrets/unbeholden-lnurl-nostr` on
   goddard, write the token to `/etc/nix-bitcoin-secrets/unbeholden-lnurl-ntfy-token`,
   and copy the contents of the Compose volume's `/app/data` to
   `/var/lib/unbeholden-lnurl` on goddard.
4. Deploy goddard (see [nixos](../../../nixos/README.md#deploy)), then:
   ```sh
   chown -R unbeholden-lnurl: /var/lib/unbeholden-lnurl
   systemctl restart unbeholden-lnurl
   journalctl -u unbeholden-lnurl -n 50
   ```
5. Test through Traefik. Expect the same `nostrPubkey` as before:
   ```sh
   curl --fail --resolve lnurl.home.unbeholden.dev:443:192.168.4.200 -H 'X-Forwarded-Host: unbeholden.dev' https://lnurl.home.unbeholden.dev/.well-known/lnurlp/ln
   ```
6. In Dokploy on Giran, set the website's `LNURL_URL` to
   `https://lnurl.home.unbeholden.dev` and redeploy.
7. Pay `ln@unbeholden.dev` a few sats with a zap. Check the ntfy push and the
   zap receipt.
8. Remove the container, its volume and its files on aden.
