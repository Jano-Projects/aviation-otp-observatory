# VRA data notes

Measured on the files for May, June and July 2026 (82,120 / 81,119 / 89,517 lines),
not assumed. When ANAC changes the format, update this page and the tests together.

## File format (current layout, 2026)

| Property | Value |
|---|---|
| Location | `https://sistemas.anac.gov.br/dadosabertos/Voos e operações aéreas/Voo Regular Ativo (VRA)/<year>/<MM - Mês>/VRA_<year><month>.csv` |
| File name | `VRA_20267.csv`: month **without** zero padding |
| Encoding | UTF-8 **with BOM**, CRLF line endings |
| Line 1 | `Atualizado em: YYYY-MM-DD` (not the header) |
| Line 2 | Header; 12 columns, `;` separated, every field quoted |
| Missing value | the literal text `null` |
| Timestamps | `YYYY-MM-DD HH:MM:SS`; about 8% carry a `.100000000` fraction |

Columns: `ICAO Empresa Aérea`, `Número Voo`, `Código Autorização (DI)`, `Código Tipo Linha`,
`ICAO Aeródromo Origem`, `ICAO Aeródromo Destino`, `Partida Prevista`, `Partida Real`,
`Chegada Prevista`, `Chegada Real`, `Situação Voo`, `Código Justificativa`.

Older files (published on `siros.anac.gov.br`) used 21 columns, different names and
`dd/mm/yyyy HH:MM` dates. The loader maps both header styles and `pkg_vra_util.to_ts`
parses both date styles.

## Content observations

- `Situação Voo` is only `REALIZADO` (flown) or `CANCELADO`.
- Cancelled flights have no actual times (`null`), as expected.
- About 3% of flown legs have **no scheduled times** (mostly flight numbers starting
  with `Z`: unscheduled/extra operations). They are kept but excluded from punctuality,
  because a delay cannot be measured without a schedule.
- `Código Justificativa` is always `N/A`: the delay cause is not usable.
- A few lines are **exact duplicates** (0 to 18 per month); they are removed.
- A few same-flight/same-day pairs differ only in the actual time, sometimes by a day.
  They are kept for now; a data-quality check is planned for phase 2.
- `Código Tipo Linha`: `N` domestic, `I` international, `C` cargo, `G` other.

## Assumptions

1. **Times are Brasília local time, for every airport.** Evidence: São Paulo→Lisbon is
   scheduled 15:30→01:25 (9h55, the real block time) without any time-zone shift.
   This is the same convention as ANAC's older layout.
2. **Minute precision.** Seconds are always `:00` and the fraction is dropped.
3. **On-time = arrival delay ≤ 15 minutes** (the industry-standard OTP15), measured only for
   flown legs with both scheduled and actual arrival times.
4. **Reference month = the file's month**, not the departure date: a few flights scheduled on
   the 31st land in the next month's dates but belong to the file they were published in.
