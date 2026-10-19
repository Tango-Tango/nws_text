# Test fixtures

The three focused fixtures (`SVRILN_mnd_timestamp.txt`, `SPSBMX.txt`,
`AFD_noMND.txt`) and **169 unmodified product examples** under `pyiem/` come
from [pyIEM's product_examples](https://github.com/akrherz/pyIEM/tree/7b02d644652d90e75bd0db2e9d7fa8ec09f4bfc5/data/product_examples),
pinned to revision `7b02d644652d90e75bd0db2e9d7fa8ec09f4bfc5`.
They are MIT licensed, Copyright (c) 2005 Iowa State University; see
[LICENSE.pyiem](LICENSE.pyiem). The corpus covers 22 AWIPS families, including
107 products with UGC codes, 89 with operational VTEC, 29 with hydrologic VTEC,
23 with motion/location lines, 25 with impact tags, and 51 with polygons. No
pyIEM implementation code is translated here.

`pyiem/expected.json` is a checked-in, reviewable snapshot of raw-to-parsed
expectations, **not** captured output from `NwsText.parse/2`. The independent
`pyiem/build_manifest.exs` derives it from the raw fixtures; tests do not run
the script. Each record pins the source bytes with SHA-256, chooses a
deterministic `reference_time` (from the first recognizable dated MND header,
otherwise `2026-10-05T12:00:00Z`), and checks WMO/AWIPS dates, ordered UGC and
VTEC fields/times, motion/location points, impact tags, headlines, and polygon
coordinates.

Regenerate from the project root using the test environment for
Jason, then review any changes to `expected.json` before accepting them:

```sh
MIX_ENV=test mix run --no-start test/fixtures/pyiem/build_manifest.exs
```

`narrative/` holds NWS flood statement bodies: five captured on 2026-10-13 and
`FLS_MLB_astor_two_stages.txt`, an Astor statement from 2026-10-19 with two impact stages.
They have no WMO header, UGC, or VTEC lines and test `NwsText.parse_narrative/1`.
Their expectations in `narrative_test.exs` are written by hand.

The CAPWBC keepalive test uses a **synthetic representative sample**, not a
verified captured payload. A captured sample is still needed for that
acceptance criterion.

## Explore in IEx

The test-only `NwsText.Explore` helper loads raw pyIEM fixtures with their
recorded reference times and returns the actual parser result:

```sh
MIX_ENV=test iex -S mix
```

```elixir
{:ok, product} = NwsText.Explore.fixture() # SVR/SVRPSR.txt: UGC, VTEC, motion, tags, polygon
product.wmo_issued_at
segment = hd(product.segments)
Enum.map(segment.ugc_codes, & &1.raw_code)
segment.vtec_codes
segment.motions
segment.impact_tags
segment.headlines
segment.polygon
{:ok, another} = NwsText.Explore.fixture("AFD.txt")
```

For your own text, call `NwsText.parse(raw, reference_time: ~U[2026-10-05 12:00:00Z])` directly.
