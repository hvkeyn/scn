# SCN updates (same host as WAN relay)

Put files here on the relay machine:

- `update.json` — manifest (served as `/scn/update.json`)
- `scn-windows.zip` — portable Windows build (entire release folder contents)

Clients fetch: `http://5.187.4.132:53319/scn/update.json`

After placing a new zip, bump `build` in `update.json` and set `url` to the zip.
Optional: set `sha256` of the zip (lowercase hex).

Env override: `SCN_UPDATES_DIR=/path/to/updates`
