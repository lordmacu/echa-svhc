# ECHA — Regulatory lookup by CAS number

Desktop app (**macOS** and **Windows**) that, given one or more **CAS** numbers,
checks whether each substance appears in **22 regulatory lists and inventories**
worldwide, and shows the result in a comparative table that can be exported to Excel.

![build](https://github.com/lordmacu/echa-svhc/actions/workflows/build.yml/badge.svg)

![Application screenshot](docs/screenshot.png)

🌐 **Project page:** https://lordmacu.github.io/echa-svhc/

---

## Downloads

| Platform | Download |
|---|---|
| 🍎 **macOS** | [echa_svhc-macos.dmg](https://github.com/lordmacu/echa-svhc/releases/latest/download/echa_svhc-macos.dmg) |
| 🪟 **Windows** (installer) | [echa_svhc-windows-setup.exe](https://github.com/lordmacu/echa-svhc/releases/latest/download/echa_svhc-windows-setup.exe) |
| 🪟 **Windows** (portable) | [echa_svhc-windows-portable.zip](https://github.com/lordmacu/echa-svhc/releases/latest/download/echa_svhc-windows-portable.zip) |

Links always point to the [latest release](https://github.com/lordmacu/echa-svhc/releases/latest).
On Windows you can either run the **installer** or unzip the **portable** build and run `echa_svhc.exe`.

---

## Lists checked (22)

**🇪🇺 European Union — ECHA**
- Candidate List (SVHC)
- Authorisation List (REACH Annex XIV) — new portal (ECHA CHEM)
- Authorisation List (REACH Annex XIV) — legacy portal
- Restriction List (REACH Annex XVII)

**🇺🇸 United States**
- California Proposition 65
- TSCA Chemical Substance Inventory
- EPA Hazardous Air Pollutants (Clean Air Act)
- TSCA Significant New Use Rule (SNUR)
- TSCA § 5(e) Consent Order

**🇯🇵 Japan**
- PDSCL — Poisonous substances (毒物)
- PDSCL — Deleterious substances (劇物)
- ENCS (Existing & New Chemical Substances)

**🇨🇦 Canada**
- Domestic Substances List (DSL)
- Non-domestic Substances List (NDSL)

**🌏 Others (via ChemRadar)**
- 🇨🇳 China IECSC · 🇰🇷 Korea KECL · 🇪🇺 EU REACH Registered · 🇹🇷 Turkey KKDIK
- 🇵🇭 Philippines PICCS · 🇹🇼 Taiwan TCSI · 🇦🇺 Australia AIIC · 🇳🇿 New Zealand NZIoC

---

## Features

- **Automatic CAS detection** (`2–7 digits - 2 digits - 1 digit`), even when pasting free text/prose; matches become *chips* with no duplicates.
- **Import from file**: load a `.csv`, `.txt`, `.xlsx` or `.xls` and extract every CAS (from any column/sheet).
- **Comparative table**: one row per CAS, one column per list (✓ listed / – not / ⚠ error). Each row expands to show per-source details (inclusion date, Art. 57 reason, Entry No., Sunset date, conditions…).
- **Filters** (Candidate List): Reason for inclusion (Art. 57) and inclusion date range.
- **Export to Excel**: generates an `.xlsx` with Yes/No per list plus detail columns.
- **Parallel lookups**: sources are grouped by host and queried concurrently, respecting each server's rate limits.

---

## How it works

Each list is queried with the most reliable method for its source:

| Source | Method |
|---|---|
| **ECHA** (Candidate, Annex XIV legacy, Annex XVII) | Liferay portal — *render GET* (`p_p_lifecycle=0`) with *namespaced* criteria + `_doSearch=true`; the hidden `_total` field signals whether it is listed. |
| **ECHA CHEM** (Annex XIV new) | JSON API `api-obligation-list/v1/authorisationList?searchText=<cas>`. |
| **EPA ChemView** (SNUR, § 5(e)) | `chemicals/search` → id → `chemicals/datatable` → reads `SNUR` / `CO` codes in `sources`. |
| **ChemRadar** (China, Korea, REACH, Turkey, PICCS, TCSI, AIIC, NZIoC, ENCS, Prop 65, TSCA, EPA HAP) | Public `es_query` endpoint per inventory. |
| **Japan PDSCL** (NIHS) | Static lists (Shift_JIS) fetched once and cached. |
| **Canada DSL/NDSL** | **Local** inventories (Excel bundled as assets) — instant lookup, no network. |

ECHA reverse-engineering notes in [`test.md`](test.md).

> **Why desktop and not web?** Several of these APIs would block requests from a
> browser due to **CORS**. A native app makes raw HTTP requests (like `curl`),
> without that restriction.

---

## Development

```bash
flutter pub get
flutter run -d macos        # or -d windows
flutter test
```

## Builds (CI)

GitHub Actions ([`.github/workflows/build.yml`](.github/workflows/build.yml))
builds on every push to `main` and publishes the binaries as *artifacts*. When a
**tag** `vX.Y.Z` is pushed, the binaries are attached to a **GitHub Release**:

```bash
git tag v1.4.0
git push origin v1.4.0
```

---

## Disclaimer

This is a *screening* aid and does not replace official verification against the
regulatory sources. Some lists (e.g. confidential substances under TSCA) are not
searchable by public CAS number. ECHA's legacy portal is maintained until
**July 2026**.
