# SLSsteam / slsteam-moon Source Patches (GNU AGPL v3)

All patches in this directory modify **SLSsteam / slsteam-moon** and are published under the **GNU Affero General Public License v3.0** (see [`../LICENSE-AGPLv3`](../LICENSE-AGPLv3)) in compliance with the upstream license of `SLSsteam`.

| File | Purpose |
| --- | --- |
| `decky-cef-8080.patch` | Keeps Steam CEF debug port on `8080` inside `steamrt64` `pressure-vessel` when Decky Loader is present. |
| `library-inject-x64.cpp` | Prevents 32-bit `/usr/lib32` paths from leaking into 64-bit `LD_AUDIT` child processes (fixes `kde-open` / OAuth browser launch on SteamOS). |
| `steam-beta-dual-patterns.patch` | Adds dual `fallbackPatterns` support so a single `SLSsteam.so` build matches both Steam Stable and Public Beta binaries. |
| `unowned-game-status.patch` | Adds optional `ShowUnownedStatus` config key (hot-reloaded) for outgoing `CMsgClientGamesPlayed` status display. |

Base upstream repository: https://github.com/Rafie-kun/slsteam-moon (pinned `v3.12`) / https://github.com/AceSLS/SLSsteam.

> Note: These patches are licensed under GNU AGPL v3. The standalone `gvlinux` orchestrator, WebUI, and Decky plugin are separate independent works governed by the root [`../LICENSE`](../LICENSE).
