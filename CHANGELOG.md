# Changelog

## 0.1.0 (unreleased)

- `NwsText.parse/2` parses one NWS text product with an explicit UTC reference time: WMO header,
  AWIPS ID, product and WMO times, ordered segments, UGC codes with expiration, operational and
  hydrologic VTEC, `LAT...LON` polygons, `TIME...MOT...LOC` motion, impact tags, headlines, and
  embedded CAP 1.2 XML.
- `NwsText.parse_narrative/1` parses headlines, impact tags, and labeled sections from product text
  without a WMO header.
