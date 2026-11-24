# LNURL

Unbeholden LNURL runs on goddard through bitcoinix, with LND as its node. It
serves the Lightning Address `*@unbeholden.dev`. The website on Giran proxies
`/.well-known/lnurlp/` to `LNURL_URL`, which is
`https://lnurl.home.unbeholden.dev`. In Dokploy, the website container has an
Extra Hosts entry of `lnurl.home.unbeholden.dev:192.168.4.200`.

Traefik serves that name with the wildcard certificate and proxies to
`192.168.4.11:8081` through a selectorless Service and a manual EndpointSlice.
Goddard accepts that port only from the worker at `192.168.4.133`, where
Traefik runs, and the service trusts its `X-Forwarded-*` headers. If Traefik moves to another node, update the firewall
rule and `trusted_proxies` in `nixos/goddard.nix`.

The service holds settlement cursors and zap receipts in
`/var/lib/unbeholden-lnurl` and its keys in `/etc/nix-bitcoin-secrets`. Back
both up. A new Nostr key changes the `nostrPubkey` that wallets have seen.

The secret files are `unbeholden-lnurl-nostr` and
`unbeholden-lnurl-ntfy-token`. Write the ntfy token without a trailing newline.
