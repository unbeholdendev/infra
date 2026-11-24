# Wallet

Unbeholden Wallet runs on goddard through bitcoinix and uses its Fulcrum.
Traefik serves it at `https://wallet.home.unbeholden.dev` with the wildcard
certificate and proxies to `192.168.4.11:60846` through a selectorless Service
and a manual EndpointSlice. goddard accepts that port only from the worker,
`192.168.4.133`, where Traefik runs. If Traefik moves to another node, add
that node to the firewall rule and the wallet's `allowedClients` in
`nixos/goddard.nix`.

The wallet has no authentication. Anyone who reaches `.200:443` can use its
Electrum relay. Keep it off public proxies and WAN forwards.

AdGuard resolves `wallet.home.unbeholden.dev` to `192.168.4.200`. The tailnet
grant for `192.168.4.200:443` covers wallet access. The watch-only wallet lives
in the browser's storage for this hostname.
