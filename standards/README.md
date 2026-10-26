# Standards

The texts Tempo implements or reads, kept here so that a clause can be found and quoted without leaving the repository.

## `iso8601/` (not distributed)

`ISO_8601-1_2019(en).PDF` and `ISO_8601-2_2019(en).PDF`, the two parts of ISO 8601:2019, and their amendments `ISO_8601-1_2019_Amd_1_2022(en).pdf` (technical corrections, among them 24:00 as the end of a day) and `ISO_8601-2_2019_Amd_1_2025(en).pdf` (canonical expressions, time scale components and date and time arithmetic), under a single-user licence. What the amendments ask of Tempo is in `plans/iso8601-amendments.md`. They are listed in `.gitignore` and never committed or packaged; read them with `pdftotext -layout`. Part 1 (date and time representations) and Part 2 (extensions: explicit forms, sets, groups, qualification, unspecified digits, selections, repeat rules) are the source of truth for `Tempo.Iso8601` and for `guides/iso8601-grammar.md`.

## `rfc/` (public)

Plain-text copies from <https://www.rfc-editor.org/>, reproduced under the IETF Trust Legal Provisions, which permit unmodified copies.

| File | Title | Tempo uses it for |
|---|---|---|
| `rfc3339.txt` | Date and Time on the Internet: Timestamps | The timestamp profile `Tempo.from_iso8601/2` reads and `Tempo.to_datetime/1` writes |
| `rfc5234.txt` | Augmented BNF for Syntax Specifications: ABNF | The notation of `guides/iso8601-grammar.md` |
| `rfc5545.txt` | Internet Calendaring and Scheduling Core Object Specification (iCalendar) | `Tempo.RRule`, `Tempo.ICal`, the EXPAND/LIMIT rules |
| `rfc7529.txt` | Non-Gregorian Recurrence Rules in iCalendar | `RSCALE` and `SKIP` in `Tempo.RRule` |
| `rfc8984.txt` | JSCalendar: A JSON Representation of Calendar Data | `Tempo.JSCalendar` |
| `rfc9557.txt` | Date and Time on the Internet: Timestamps with Additional Information (IXDTF) | The `[Europe/Paris]`, `[u-ca=hebrew]` and `[key=value]` suffix read by `Tempo.Iso8601.Tokenizer.Extended`, and section 4.1 of the grammar guide |
