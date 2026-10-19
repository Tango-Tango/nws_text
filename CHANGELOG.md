# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A bulleted narrative section, such as `* IMPACTS...`, now keeps unindented paragraphs that sit
  between it and the next bullet, for example a second flood stage impact.

## [0.1.0] - 2026-10-16

### Added

- `NwsText.parse/2` parses one NWS text product with an explicit UTC reference time: WMO header,
  AWIPS ID, product and WMO times, ordered segments, UGC codes with expiration, operational and
  hydrologic VTEC, `LAT...LON` polygons, `TIME...MOT...LOC` motion, impact tags, headlines, and
  embedded CAP 1.2 XML.
- `NwsText.parse_narrative/1` parses headlines, impact tags, and labeled sections from product text
  without a WMO header.
