# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A single-page NRL Supercoach draft board web app. Players are ranked by VORP (Value Over Replacement Player) using weighted averages across three seasons. Stats are scraped from nrlsupercoachstats.com via a PowerShell script and saved as a JS file loaded by the HTML app.

## Running the app locally

Start the dev server (PowerShell HTTP server on port 3456):
```
# Via Claude Code preview
# launch.json is configured — use preview_start "supercoach-draft"

# Or manually
powershell -ExecutionPolicy Bypass -File serve.ps1
```
Then open `http://localhost:3456/`.

## Refreshing player data

```powershell
powershell -ExecutionPolicy Bypass -File update-players.ps1
```

This fetches from `nrlsupercoachstats.com/draftgrid.php` and regenerates `players-data.js`. Must be run locally — cannot run on Vercel. After running, commit `players-data.js` and push to update the live site.

## Architecture

**Single-file app** — all HTML, CSS, and JS live in `supercoach-draft.html`. No build step, no framework, no npm.

**Data pipeline:**
- `update-players.ps1` scrapes `draftgrid.php?year=2026` (2025 data), `?year=2025` (2024), `?year=2024` (2023) — the year offset is intentional; N contains season N-1 data
- Also scrapes `playerlist.php` for team codes and prices
- Outputs `players-data.js` which sets `window.PLAYER_DATA = { generated, players: [...] }`
- `supercoach-draft.html` loads `players-data.js` via `<script src>` and falls back to a hardcoded `FALLBACK_PLAYERS` array if missing

**Key data shape** (one player in `players-data.js`):
```json
{"name":"Payne Haas","team":"BRO","positions":["FRF"],"avg2025":85.05,"avg2024":67.59,"avgPrior":74.07,"price":680800}
```

**Position codes** match the site exactly: `FLB`, `CTW`, `HFB`, `5/8`, `HOK`, `FRF`, `2RF`. These differ from common shorthand (e.g. FRF = prop, 2RF = second row/lock, CTW = centre/wing combined).

**VORP calculation** (`computeVORP` in the HTML):
- Weighted average: 80% avg2025, 10% avg2024, 10% avgPrior (re-normalised if years missing)
- Replacement level = Nth player's weighted avg at their primary position, where N = `STARTERS_PER_TEAM[pos] × numTeams`
- `numTeams` is configurable via UI toggle (8/10/12/14/16), persisted in `localStorage`

**Draft state** stored in `localStorage` as `sc-draft-picks`: `{ [playerId]: 'mine' | 'opp' }`. Player IDs are array indices assigned at render time.

**Low availability flag**: players where `avg2025 / avg2024 < 0.80` are flagged ⚠ — this detects the draftgrid formula's game multiplier being applied (×0.66 for 1 game, ×0.75 for 2 games), meaning ≤2 games played. Players with 3+ games are indistinguishable from full-season players in this data source.

**Players with no 2025 data are excluded entirely** — filtered out at load time (`PLAYERS = RAW_PLAYERS.filter(p => p.avg2025 != null)`).

## Deployment

Deployed on Vercel (static hosting). `index.html` redirects to `supercoach-draft.html`. `vercel.json` is present but the index redirect is what actually works. To update the live site: run `update-players.ps1` locally, then `git add players-data.js && git commit && git push`.

## PowerShell notes

- Uses PowerShell 5.1 (Windows built-in) — no Node.js or Python required
- `serve.ps1` uses `System.Net.HttpListener`; includes path traversal protection (resolves full path, checks it starts within `$root`)
- `update-players.ps1` uses `Invoke-WebRequest` with `-UseBasicParsing`; all draftgrid pages are server-rendered HTML (no JS required). Stats pages (`stats.php`, `mattsstats.php`) are JS-rendered and cannot be scraped this way.
- PowerShell 5.1: use `.Contains()` not `.ContainsKey()` on `OrderedDictionary`; `&&` pipeline chaining is not available
