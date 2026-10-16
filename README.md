# NwsText

Parse National Weather Service (NWS) text products in Elixir.

`NwsText` turns one NWS text product into plain structs: WMO header, AWIPS ID,
issue times, ordered segments, UGC codes, VTEC, polygons, storm motion, impact
tags, headlines, labeled narrative sections, and embedded CAP 1.2 XML. It is a
pure parser. It does no network, XMPP, database, or location lookups, and it
makes no alerting decisions. The same input and reference time always give the
same result.

This project is not affiliated with or endorsed by NOAA or the National Weather
Service.

## Installation

```elixir
def deps do
  [{:nws_text, "~> 0.1"}]
end
```

## Usage

### Complete products

```elixir
{:ok, product} = NwsText.parse(raw_text, reference_time: ~U[2026-10-05 20:15:00Z])

product.awips_id                      #=> "SVRHUN"
product.issued_at                     #=> ~U[2026-10-05 20:10:00Z]

segment = hd(product.segments)
Enum.map(segment.ugc_codes, & &1.raw_code)  #=> ["ALC089", "ALC091"]
segment.vtec_codes                    #=> [%NwsText.Model.VTEC{action: "NEW", phenomenon: "SV", ...}]
segment.polygon                       #=> %Geo.Polygon{srid: 4326, ...}
segment.impact_tags                   #=> [%{name: "MAX HAIL SIZE", value: "1.00 IN"}]
```

`reference_time` is required and must be a UTC `DateTime`. The parser uses it
to resolve day-only WMO and UGC times to the nearest previous, current, or next
month. It never reads the wall clock.

`parse/2` returns `{:error, %NwsText.ParseError{}}` for an invalid WMO header or
malformed UGC or VTEC coding. Problems with optional fields, such as a bad
polygon or motion line, are reported in `product.diagnostics`. The field is
then `nil` or left out. The parser never returns partial geometry.

### Narrative text

Some sources deliver only the product body, without the WMO header, UGC, or VTEC
lines. Use `parse_narrative/1` for that text:

```elixir
{:ok, narrative} = NwsText.parse_narrative(body_text)

narrative.headlines   #=> ["FLOOD WARNING REMAINS IN EFFECT UNTIL FURTHER NOTICE"]
narrative.sections    #=> [%{label: "WHAT", text: "Minor flooding is occurring."}, ...]
narrative.impact_tags #=> []
```

Sections are literal `%{label, text}` maps in source order. The known labels are
`WHAT`, `WHERE`, `WHEN`, `HAZARD`, `SOURCE`, `IMPACT` (`IMPACTS` is reported as
`IMPACT`), `ADDITIONAL DETAILS`, and `PRECAUTIONARY/PREPAREDNESS ACTIONS`. Other
text stays in the raw text only.

## Behavior notes

- **Times:** A product time line such as `1011 AM EDT Tue Oct 13 2026` sets
  `issued_at`. Without one, `issued_at` is the WMO time. Supported zones are UTC,
  GMT, and US zones: Atlantic, Eastern, Central, Mountain, Pacific, Alaska,
  Hawaii, Samoa, and Chamorro (Guam). Like pyIEM, `1300 PM` means 13:00,
  and UTC or GMT times may omit AM/PM.
- **Coordinates:** `LAT...LON` and `TIME...MOT...LOC` have no hemisphere marker.
  Longitudes are west, except for products from `PGUM` (Guam), which are east.
- **CAP:** Embedded CAP XML is limited to 1 MB and parsed with
  [Saxy](https://hex.pm/packages/saxy). Entities are not expanded, and any DTD or
  entity declaration is rejected. CAP fields are matched by namespace URI. CAP
  text is never scanned for UGC or VTEC lines.
- **Raw text:** `raw_text` is kept on the product and on every segment, so
  nothing is lost when a field is not modeled.

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix credo --strict
```

Releases are made by maintainers with `scripts/release`; see
[PUBLISHING.md](PUBLISHING.md).

The test corpus contains 169 unmodified product examples from
[pyIEM](https://github.com/akrherz/pyIEM). Its expected results are generated
independently from the raw text, not from the parser. See
[test/fixtures/README.md](test/fixtures/README.md) for attribution and for how to
regenerate them.

## License

MIT. See [LICENSE](LICENSE). The pyIEM test fixtures are MIT licensed by Iowa
State University; see `test/fixtures/LICENSE.pyiem`.
