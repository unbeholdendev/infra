# Wallet

Unbeholden Wallet runs on goddard through bitcoinix and uses its Fulcrum.
Traefik serves it at `https://wallet.home.unbeholden.dev` with the wildcard
certificate and proxies to `192.168.4.11:60846` through a selectorless Service
and a manual EndpointSlice. goddard accepts that port only from the worker,
`192.168.4.133`, where Traefik runs. If Traefik moves to another node, add
that node to the rule in `nixos/goddard.nix`.

The wallet has no authentication. Anyone who reaches `.200:443` can use its
Electrum relay. Keep it off public proxies and WAN forwards.

## Move from aden

1. Deploy goddard (see [nixos](../../../nixos/README.md#deploy)) and merge.
2. Test before changing DNS:
   ```sh
   curl --fail -I --resolve wallet.home.unbeholden.dev:443:192.168.4.200 https://wallet.home.unbeholden.dev/
   ```
3. Point AdGuard's `wallet.home.unbeholden.dev` rewrite at `192.168.4.200`.
4. Open the wallet, press Connect, check balances and a QR scan.
5. Stop and remove the wallet container on aden.

The watch-only wallet lives in the browser's storage for this hostname, so it
carries over. The tailnet grant to `.200:443` covers the new address.
