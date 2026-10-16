defmodule NwsText.CodedParsersTest do
  use ExUnit.Case, async: true

  alias NwsText.Model.UGC, as: ModelUGC
  alias NwsText.Model.VTEC, as: ModelVTEC
  alias NwsText.Parser.{Dates, HydroVTEC, Motion, Narrative, Polygon, UGC, VTEC, WMO}

  @reference ~U[2026-10-05 15:53:00Z]

  test "MND grammar finds a date amid prose, optional timezone annotation and case variants" do
    assert Dates.product_date("Issued 857 PM EDT (757 PM EST) SAT JUN 22 1996\n", @reference) ==
             ~U[1996-06-23 00:57:00Z]

    assert Dates.product_date("Wrong 857 PM XYZ SAT JUN 22 1996; 930 am pst Mon Jan 1 2027", @reference) ==
             ~U[2027-01-01 17:30:00Z]

    assert Dates.product_date("Issued 857 PM EDT SAT FOO 22 1996", @reference) == @reference
  end

  test "MND grammar covers Alaska, Hawaii, Atlantic, Samoa, and Guam time zones" do
    for {text, expected} <- [
          {"527 AM ChST Sun Jun 19 2016", ~U[2016-06-18 19:27:00Z]},
          {"1000 AM AKDT Mon Jun 1 2026", ~U[2026-06-01 18:00:00Z]},
          {"1000 AM AKST Mon Jan 5 2026", ~U[2026-01-05 19:00:00Z]},
          {"1000 AM HST Mon Jan 5 2026", ~U[2026-01-05 20:00:00Z]},
          {"1000 AM AST Mon Jan 5 2026", ~U[2026-01-05 14:00:00Z]},
          {"1000 AM SST Mon Jan 5 2026", ~U[2026-01-05 21:00:00Z]}
        ] do
      assert Dates.product_date(text, @reference) == expected
    end
  end

  test "MND clocks accept 24-hour PM and UTC hours like pyIEM, and reject impossible times" do
    assert Dates.product_date("1300 PM EDT Mon Oct 5 2026", @reference) == ~U[2026-10-05 17:00:00Z]
    assert Dates.product_date("1500 UTC Mon Oct 5 2026", @reference) == ~U[2026-10-05 15:00:00Z]
    assert Dates.product_date("0000 GMT Mon Oct 5 2026", @reference) == ~U[2026-10-05 00:00:00Z]
    assert Dates.product_date("1200 AM UTC Mon Oct 5 2026", @reference) == ~U[2026-10-05 00:00:00Z]
    assert Dates.product_date("1200 PM CDT Mon Oct 5 2026", @reference) == ~U[2026-10-05 17:00:00Z]

    for text <- ["1300 AM EDT", "000 PM EDT", "1260 PM EDT", "2400 PM EDT", "1500 EDT", "2400 UTC"] do
      assert Dates.product_date(text <> " Mon Oct 5 2026", @reference) == @reference
    end

    assert Dates.product_date("1300 AM EDT Mon Oct 5 2026 then 1200 AM EDT Tue Oct 6 2026", @reference) ==
             ~U[2026-10-06 04:00:00Z]
  end

  test "LAT...LON grammar handles continuation lines and rejects malformed coordinates" do
    assert {:ok, %Geo.Polygon{coordinates: [[{-86.3, 34.5}, {-86.4, 34.6}, {-86.3, 34.5}]]}} =
             Polygon.parse(["LAT...LON 3450 08630", " 3460 08640", "3450 08630", "prose"], 1)

    assert :error = Polygon.parse(["LAT...LON 3450 08630 3460 08640 3450 0863X"], 1)

    assert :error =
             Polygon.parse(["LAT...LON 3450 8630 3460 8640 3470 8650", "      34X0 8660 3480 8670"], 1)
  end

  test "WMO grammar consumes the complete header and preserves optional correction" do
    assert {:ok, %{wmo_id: "WWUS53", issuing_center: "KHUN", wmo_date_group: "052010", correction_code: "CCA"}} =
             WMO.parse_header("WWUS53 KHUN 052010 CCA")

    assert :error = WMO.parse_header("WWUS53 KHUN 052010 garbage")
    assert :error = WMO.parse_header("WWUS53 KHUN 052010 CCA extra")
  end

  test "UGC grammar expands ranges and rejects trailing or malformed content" do
    assert {:ok, [%ModelUGC{raw_code: "ALC089"}, %ModelUGC{raw_code: "ALC091"}, %ModelUGC{raw_code: "ALC092"}],
            ~U[2026-10-05 21:30:00Z]} =
             UGC.parse("ALC089-091>092-052130-", @reference)

    assert :error = UGC.parse("ALC089-091>092-052130-TRAILING", @reference)
    assert :error = UGC.parse("ALC089-BAD-052130-", @reference)
    assert [{"ALC089-091>092-052130-", 1}] = UGC.collapse_lines(["ALC089-", "091>092-052130-"])
  end

  test "range-first UGC headers are detected across wrapped lines" do
    assert UGC.start?("CTZ005>011-030915-")

    assert [{"CTZ005>011-NJZ002-030915-", 1}] =
             UGC.collapse_lines(["CTZ005>011-NJZ002-", "030915-"])

    assert {:ok, codes, _} = UGC.parse("CTZ005>011-NJZ002-030915-", @reference)
    assert Enum.map(codes, & &1.raw_code) == ~w(CTZ005 CTZ006 CTZ007 CTZ008 CTZ009 CTZ010 CTZ011 NJZ002)
  end

  test "short AWIPS identifiers are parsed without accepting arbitrary text" do
    assert {:ok, %{awips_id: "AFDPQ"}} = WMO.parse("FXUS66 KPQR 052010\nAFDPQ\n", @reference)
    assert {:ok, %{awips_id: nil}} = WMO.parse("FXUS66 KPQR 052010\nLONGNAME\n", @reference)
  end

  test "VTEC timestamp decoder handles valid dates, missing dates, and invalid dates" do
    assert Dates.vtec_timestamp("130418", "0819") == {:ok, ~U[2013-04-18 08:19:00Z]}
    assert Dates.vtec_timestamp("000000", "0000") == {:ok, nil}
    assert Dates.vtec_timestamp("261035", "2010") == {:error, :invalid_date}
  end

  test "hydrologic VTEC decodes its three timestamps and unknown sentinels" do
    assert {:ok,
            %{
              nwsli: "DVSI4",
              severity: "1",
              cause: "ER",
              begins_at: ~U[2013-04-18 08:19:00Z],
              crests_at: ~U[2013-04-19 00:00:00Z],
              ends_at: ~U[2013-04-20 11:12:00Z],
              record: "NO"
            }} =
             HydroVTEC.parse("/DVSI4.1.ER.130418T0819Z.130419T0000Z.130420T1112Z.NO/")

    assert {:ok, %{nwsli: "00000", begins_at: nil, crests_at: nil, ends_at: nil}} =
             HydroVTEC.parse("/00000.0.ER.000000T0000Z.000000T0000Z.000000T0000Z.OO/")

    assert :error = HydroVTEC.parse("/00000.0.ER.261035T0000Z.000000T0000Z.000000T0000Z.OO/")
  end

  test "motion parses multiple coordinate pairs and resolves time relative to UGC expiry" do
    assert {:ok,
            %{
              time: "2022Z",
              valid_at: ~U[2026-10-05 20:22:00Z],
              direction_degrees: 281,
              speed_knots: 27,
              points: [%Geo.Point{coordinates: {-89.05, 38.18}}, _, _]
            }} =
             Motion.parse(
               "TIME...MOT...LOC 2022Z 281DEG 27KT 3818 8905 3802 8911 3793 8936",
               ~U[2026-10-05 21:30:00Z]
             )

    assert {:ok, %{valid_at: ~U[2026-10-04 23:59:00Z]}} =
             Motion.parse("TIME...MOT...LOC 2359Z 270DEG 30KT 3791 8414", ~U[2026-10-05 00:20:00Z])

    assert :error = Motion.parse("TIME...MOT...LOC 2561Z 400DEG 30KT 9999 8414", nil)

    assert {:ok, %{points: [%Geo.Point{coordinates: {144.78, 13.41}}]}} =
             Motion.parse("TIME...MOT...LOC 2022Z 281DEG 27KT 1341 14478", nil, "PGUM")
  end

  test "headlines and impact tags preserve source wording without inferring alert severity" do
    lines = ["...WINTER WEATHER", "ADVISORY IN EFFECT...", "TORNADO...OBSERVED", "HAIL...<.75IN", "Some prose..."]
    assert Narrative.headlines(lines) == ["WINTER WEATHER ADVISORY IN EFFECT"]
    assert Narrative.tags(lines) == [%{name: "TORNADO", value: "OBSERVED"}, %{name: "HAIL", value: "<.75IN"}]
    assert Narrative.headlines(["...............................", "...A REAL HEADLINE..."]) == ["A REAL HEADLINE"]

    assert Narrative.tags(["EXPECTED RAINFALL RATE...1-2 INCHES IN 1 HOUR"]) ==
             [%{name: "EXPECTED RAINFALL RATE", value: "1-2 INCHES IN 1 HOUR"}]

    assert Narrative.tags(["In prose HAIL...1.00IN", "MAX WIND GUST...<30 MPH"]) ==
             [%{name: "MAX WIND GUST", value: "<30 MPH"}]
  end

  test "VTEC grammar consumes the complete coded line and validates dates" do
    line = "/O.NEW.KHUN.SV.W.0123.261005T2010Z-261005T2100Z/"
    assert {:ok, %ModelVTEC{raw_line: ^line, begins_at: ~U[2026-10-05 20:10:00Z]}} = VTEC.parse(line)
    assert :error = VTEC.parse(line <> "junk")
    assert :error = VTEC.parse("/O.NEW.KHUN.SV.W.0123.261035T2010Z-261005T2100Z/")
  end
end
