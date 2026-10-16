defmodule NwsTextTest do
  use ExUnit.Case, async: true

  alias NwsText.Model.CAP
  alias NwsText.Model.CAP.Area
  alias NwsText.Model.{Segment, TextProduct, UGC, VTEC}
  alias NwsText.Parser.CAP, as: CAPParser

  @time ~U[2026-10-05 15:53:00Z]
  @header "WWUS53 KHUN 052010\nSVRHUN\n"
  @vtec "/O.NEW.KHUN.SV.W.0123.261005T2010Z-261005T2100Z/"

  defp parse(text), do: NwsText.parse(text, reference_time: @time)

  test "requires a valid WMO header and explicit reference time" do
    assert {:error, %NwsText.ParseError{code: :invalid_wmo_header, line: 1}} = parse("garbage")
    assert {:error, %NwsText.ParseError{code: :invalid_reference_time}} = NwsText.parse(@header)
  end

  test "invalid WMO date reports the header line after a preamble" do
    assert {:error, %NwsText.ParseError{code: :invalid_wmo_date, line: 3}} =
             parse("\x01\n123\nWWUS53 KHUN 322010\nSVRHUN\n")
  end

  test "resolves month/year rollover and prefers usable product date to WMO issuance" do
    assert {:ok, product} = NwsText.parse("WWUS53 KHUN 312359\nSVRHUN\n", reference_time: ~U[2027-01-01 00:01:00Z])
    assert product.wmo_issued_at == ~U[2026-12-31 23:59:00Z]
    assert product.issued_at == product.wmo_issued_at
  end

  test "parses ordered segments, ranges, VTEC, polygon, and preserves raw text" do
    raw =
      @header <>
        "ALC089-091>093-052130-\n#{@vtec}\nLAT...LON 3450 08630 3460 08640 3450 08630\n$$\nALZ001-052200-\n/O.CON.KHUN.SV.W.0123.261005T2010Z-261005T2100Z/\n$$\n"

    assert {:ok, %TextProduct{segments: [%Segment{} | _]} = product} = parse(raw)
    refute Map.has_key?(product, :candidacy)
    assert product.raw_text == raw
    assert product.wmo_id == "WWUS53"
    assert product.issuing_center == "KHUN"
    assert product.awips_id == "SVRHUN"
    assert [first, second] = product.segments
    assert {first.index, second.index} == {0, 1}
    assert [%UGC{} | _] = first.ugc_codes
    assert Enum.map(first.ugc_codes, & &1.raw_code) == ~w(ALC089 ALC091 ALC092 ALC093)
    assert first.ugc_expires_at == ~U[2026-10-05 21:30:00Z]

    assert [%VTEC{action: "NEW", phenomenon: "SV", significance: "W", event_tracking_number: 123}] =
             first.vtec_codes

    assert first.polygon == %Geo.Polygon{coordinates: [[{-86.3, 34.5}, {-86.4, 34.6}, {-86.3, 34.5}]], srid: 4326}
    assert Enum.map(second.ugc_codes, & &1.type) == [:zone]
    assert length(second.vtec_codes) == 1
    assert second.polygon == nil
  end

  test "range-first UGC coding is retained alongside VTEC" do
    raw = @header <> "ALZ011>013-052130-\n#{@vtec}\n"
    assert {:ok, %{segments: [segment]}} = parse(raw)
    assert Enum.map(segment.ugc_codes, & &1.raw_code) == ~w(ALZ011 ALZ012 ALZ013)
    assert segment.ugc_expires_at == ~U[2026-10-05 21:30:00Z]

    assert {:error, %NwsText.ParseError{code: :invalid_ugc}} =
             parse(@header <> "ALZ011>BAD-052130-\n#{@vtec}\n")
  end

  test "real wrapped range-first UGC lines retain all warning zones" do
    raw = File.read!("test/fixtures/pyiem/WSWOKX/14.txt")
    assert {:ok, %{segments: [warning | _]}} = NwsText.parse(raw, reference_time: ~U[2015-02-03 01:05:00Z])
    assert [%VTEC{action: "EXT", phenomenon: "WW"}] = warning.vtec_codes

    codes = Enum.map(warning.ugc_codes, & &1.raw_code)
    assert length(codes) == 31
    assert Enum.take(codes, 7) == ~w(CTZ005 CTZ006 CTZ007 CTZ008 CTZ009 CTZ010 CTZ011)
    assert "NJZ108" in codes
    assert List.last(codes) == "NYZ179"
  end

  test "double-CR segment separators keep warning and advisory geography apart" do
    raw = File.read!("test/fixtures/pyiem/WSWAMA/WSWAMA_05.txt")

    assert {:ok, %{segments: [warning, advisory]}} =
             NwsText.parse(raw, reference_time: ~U[2017-01-14 03:21:00Z])

    assert [%VTEC{phenomenon: "IS", significance: "W"}] = warning.vtec_codes
    assert Enum.map(warning.ugc_codes, & &1.raw_code) == ~w(OKZ002 OKZ003 TXZ004 TXZ005 TXZ009 TXZ010 TXZ015)
    assert [%VTEC{phenomenon: "ZR", significance: "Y"}] = advisory.vtec_codes
    advisory_codes = Enum.map(advisory.ugc_codes, & &1.raw_code)
    assert length(advisory_codes) == 15
    assert hd(advisory_codes) == "OKZ001"
    assert List.last(advisory_codes) == "TXZ020"
  end

  test "hyphen-wrapped UGC lists preserve state/zone prefixes and expiration" do
    raw = @header <> "MOC155-TNC023-033-039-\n045-053-052200-\n"
    assert {:ok, product} = parse(raw)
    assert Enum.map(hd(product.segments).ugc_codes, & &1.raw_code) == ~w(MOC155 TNC023 TNC033 TNC039 TNC045 TNC053)
    assert hd(product.segments).ugc_expires_at == ~U[2026-10-05 22:00:00Z]
    assert hd(product.segments).raw_text == raw
  end

  test "routine hydrologic VTEC retains its coded fields" do
    raw = @header <> "/O.ROU.KHUN.HY.S.0000.000000T0000Z-000000T0000Z/\n"
    assert {:ok, product} = parse(raw)

    assert [%VTEC{action: "ROU", phenomenon: "HY", begins_at: nil, ends_at: nil}] =
             hd(product.segments).vtec_codes
  end

  test "retains every operational VTEC line in a segment and correction header" do
    raw =
      "WWUS53 KHUN 052010 CCA\nSVRHUN\n" <>
        @vtec <>
        "\n" <>
        String.replace(@vtec, ".NEW.", ".CON.") <> "\n"

    assert {:ok, %{correction_code: "CCA", segments: [segment]}} = parse(raw)
    assert Enum.map(segment.vtec_codes, & &1.action) == ~w(NEW CON)
    assert Enum.map(segment.vtec_codes, & &1.raw_line) == [@vtec, String.replace(@vtec, ".NEW.", ".CON.")]
  end

  test "invalid coding cannot produce valid-looking codes; invalid polygon is only diagnostic" do
    assert {:error, %NwsText.ParseError{code: :invalid_ugc}} = parse(@header <> "ALC089-BAD-052130-\n")
    assert {:error, %NwsText.ParseError{code: :invalid_vtec}} = parse(@header <> "/O.NEW.KHUN.SV.W.BAD/\n")

    assert {:error, %NwsText.ParseError{code: :invalid_vtec}} =
             parse(@header <> String.replace(@vtec, ".NEW.", ".BAD."))

    assert {:ok, product} = parse(@header <> "LAT...LON 9999 08630 1234\n")
    assert hd(product.segments).polygon == nil
    assert [%NwsText.Diagnostic{code: :invalid_polygon}] = product.diagnostics
  end

  test "segment errors and diagnostics use product-relative lines" do
    prefix = @header <> "\nALC089-052130-\n#{@vtec}\n$$\nALC001-052130-\n"

    assert {:error, %NwsText.ParseError{code: :invalid_vtec, line: 8}} =
             parse(prefix <> "/O.NEW.KHUN.SV.W.BAD/\n$$\n")

    assert {:ok, %{diagnostics: [%NwsText.Diagnostic{code: :invalid_polygon, line: 8}], segments: [_, segment]}} =
             parse(prefix <> "LAT...LON 3450 8630 3460 8640 3470 8650\n      34X0 8660 3480 8670\n$$\n")

    assert segment.polygon == nil
  end

  test "malformed polygon continuation does not produce partial geometry" do
    raw = @header <> "LAT...LON 3450 8630 3460 8640 3470 8650\n      34X0 8660 3480 8670\n"

    assert {:ok, %{segments: [segment], diagnostics: [%NwsText.Diagnostic{code: :invalid_polygon}]}} = parse(raw)
    assert segment.polygon == nil
  end

  test "pyIEM fixtures across families expose common fields without family-specific parsing" do
    svr = File.read!("test/fixtures/SVRILN_mnd_timestamp.txt")
    assert {:ok, warning} = NwsText.parse(svr, reference_time: ~U[1996-06-23 01:30:00Z])
    assert warning.awips_id == "SVRILN"
    assert warning.wmo_issued_at == ~U[1996-06-23 01:30:00Z]
    assert warning.issued_at == ~U[1996-06-23 00:57:00Z]
    assert Enum.map(hd(warning.segments).ugc_codes, & &1.raw_code) == ["INC029"]

    sps = File.read!("test/fixtures/SPSBMX.txt")
    assert {:ok, statement} = NwsText.parse(sps, reference_time: ~U[2018-05-29 21:52:00Z])
    assert statement.issued_at == ~U[2018-05-29 21:52:00Z]
    assert Enum.map(hd(statement.segments).ugc_codes, & &1.raw_code) == ["ALZ039"]
    assert %Geo.Polygon{srid: 4326, coordinates: [points]} = hd(statement.segments).polygon
    assert hd(points) == List.last(points)

    assert {:ok, %{awips_id: "AFDBOX"}} =
             NwsText.parse(File.read!("test/fixtures/AFD_noMND.txt"), reference_time: ~U[2026-10-27 00:02:00Z])
  end

  test "Guam warning polygons have east longitudes" do
    raw = File.read!("test/fixtures/pyiem/FFW/FFW_tags.txt")

    assert {:ok, %{issuing_center: "PGUM", segments: [segment | _]}} =
             NwsText.parse(raw, reference_time: ~U[2018-10-24 20:23:00Z])

    assert %Geo.Polygon{coordinates: [[{145.8, 15.16} | _]]} = segment.polygon
  end

  test "real fixtures expose short AWIPS, hydrologic VTEC, motion, impact tags, and headlines" do
    assert {:ok, %{awips_id: "AFDPQ"}} =
             NwsText.parse(File.read!("test/fixtures/pyiem/AFDPQ.txt"), reference_time: ~U[2016-06-18 20:09:00Z])

    assert {:ok, %{segments: [flood | _]}} =
             NwsText.parse(File.read!("test/fixtures/pyiem/FFW/FFW_tags.txt"),
               reference_time: ~U[2018-10-24 20:23:00Z]
             )

    assert [%NwsText.Model.HydrologicVTEC{nwsli: "00000", severity: "0"}] = flood.hydrologic_vtec
    assert %{name: "FLASH FLOOD DAMAGE THREAT", value: "CATASTROPHIC"} in flood.impact_tags

    assert {:ok, %{segments: [warning]}} =
             NwsText.parse(File.read!("test/fixtures/pyiem/SVR/SVRPSR.txt"),
               reference_time: ~U[2020-09-09 00:29:00Z]
             )

    assert [
             %NwsText.Model.Motion{
               time: "0029Z",
               valid_at: ~U[2020-09-09 00:29:00Z],
               points: [%Geo.Point{coordinates: {-111.83, 33.19}}]
             }
           ] = warning.motions

    assert %{name: "HAIL", value: "0.75IN"} in warning.impact_tags

    assert {:ok, %{segments: segments}} =
             NwsText.parse(File.read!("test/fixtures/pyiem/WSWGRR/13.txt"),
               reference_time: ~U[2015-01-05 08:48:00Z]
             )

    assert "WIND CHILL ADVISORY IN EFFECT UNTIL NOON EST TODAY" in hd(segments).headlines
  end

  test "malformed hydrologic and motion lines remain raw and produce diagnostics" do
    raw =
      @header <>
        "ALC089-052130-\n" <>
        "/00000.0.ER.261035T0000Z.000000T0000Z.000000T0000Z.OO/\n" <>
        "/00000.0.ER.BAD/\n" <>
        "TIME...MOT...LOC 2561Z 400DEG 30KT 9999 8414\n"

    assert {:ok, %{segments: [segment], diagnostics: notes}} = parse(raw)
    assert segment.hydrologic_vtec == []
    assert segment.motions == []
    assert segment.raw_text == raw

    assert Enum.map(notes, &{&1.code, &1.line}) == [
             {:invalid_hydrologic_vtec, 4},
             {:invalid_hydrologic_vtec, 5},
             {:invalid_motion, 6}
           ]
  end

  test "observation and prose products retain their raw text" do
    for raw <- ["SAUS70 KNYC 052010\nMETAR KNYC 052010Z\n", @header <> "Potential hazard described in prose.\n"] do
      assert {:ok, %TextProduct{raw_text: ^raw}} = parse(raw)
    end
  end

  @cap """
  <?xml version="1.0" encoding="UTF-8"?>
  <alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">
    <identifier>urn:oid:KEEPALIVE-16629</identifier><sender>w-nws.webmaster@noaa.gov</sender>
    <sent>2026-10-05T15:53:00Z</sent><status>Test</status><msgType>Alert</msgType>
    <info><event>Test Message</event><eventCode><valueName>NationalWeatherService</valueName><value>TST</value></eventCode>
      <area><areaDesc>Montgomery</areaDesc><geocode><valueName>UGC</valueName><value>MDC031</value></geocode></area>
    </info>
  </alert>
  """

  test "CAP extraction ignores alert lookalikes in prose, comments and attributes" do
    prefix =
      @header <> "The <alert> tag is mentioned in prose.\n<!-- <alert xmlns=\"fake\"/> -->\n<other hint=\"<alert>\"/>\n"

    suffix = "\nPostscript remains after XML.\n"
    raw = prefix <> @cap <> suffix

    assert {coded, xml} = CAPParser.extract(raw)
    assert String.starts_with?(xml, "<alert xmlns=\"urn:oasis:names:tc:emergency:cap:1.2\">")
    assert String.ends_with?(xml, "</alert>")
    assert coded == String.replace(raw, xml, "")
    assert coded =~ "The <alert> tag is mentioned in prose."
    assert coded =~ "<other hint=\"<alert>\"/>"
    assert coded =~ suffix
    assert {:ok, %{cap: %CAP{status: "Test"}}} = parse(raw)
  end

  test "CAP boundary follows the XML root, not a closing tag inside CDATA or a comment" do
    xml =
      @cap
      |> String.replace("<identifier>", "<note><![CDATA[</alert>]]></note><!-- </alert> --><identifier>")

    suffix = "\nAfter the CAP document.\n"
    assert {remaining, fragment} = CAPParser.extract(@header <> xml <> suffix)
    assert String.contains?(fragment, "<![CDATA[</alert>]]>")
    assert String.ends_with?(fragment, "</alert>")
    assert remaining == String.replace(@header <> xml <> suffix, fragment, "")
    assert remaining =~ suffix
    assert {:ok, %{cap: %CAP{status: "Test"}}} = parse(@header <> xml <> suffix)
  end

  test "prefixed CAP root and nested alert tags use the outer XML boundary" do
    xml =
      "<cap:alert xmlns:cap=\"urn:oasis:names:tc:emergency:cap:1.2\">" <>
        "<cap:identifier>prefixed</cap:identifier><cap:sender>sender</cap:sender>" <>
        "<cap:sent>2026-10-05T15:53:00Z</cap:sent><cap:status>Actual</cap:status>" <>
        "<cap:msgType>Alert</cap:msgType><cap:info><cap:event>Warning</cap:event>" <>
        "<cap:alert>nested</cap:alert></cap:info></cap:alert>"

    assert {coded, ^xml} = CAPParser.extract(@header <> xml <> "\nPostscript")
    assert coded == @header <> "\nPostscript"

    assert {:ok, %{cap: %CAP{identifier: "prefixed"}}} = parse(@header <> xml <> "\nPostscript")
  end

  test "malformed first CAP root is diagnosed rather than skipping ahead to a valid one" do
    raw = @header <> "<alert><info></alert>\n" <> @cap
    assert {coded, xml} = CAPParser.extract(raw)
    assert coded == @header
    assert String.starts_with?(xml, "<alert><info>")

    assert {:ok, %{cap: nil, diagnostics: [%NwsText.Diagnostic{code: :invalid_cap} | _]}} = parse(raw)
  end

  test "CAP boundary ignores less-than signs in prose before a CAP root" do
    cap = String.replace_prefix(@cap, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n", "")

    for prose <- ["VISIBILITY <1 MILE. DO NOT TRAVEL.", "DON'T TRAVEL WHEN VISIBILITY <1 MILE."] do
      assert {:ok, %{cap: %CAP{status: "Test"}}} = parse("XOUS55 KWBC 051553\nCAPWBC\n#{prose}\n" <> cap)
    end
  end

  test "CAP XML replacement preserves coded-line locations" do
    raw = @header <> @cap <> "/O.NEW.KHUN.SV.W.BAD/\n"
    assert {:error, %NwsText.ParseError{code: :invalid_vtec, line: 11}} = parse(raw)
  end

  test "CAP text containing a segment separator cannot create segments or coded fields" do
    xml =
      String.replace(
        @cap,
        "<identifier>",
        "<note>Prose before\n$$\nALC001-052130-\n/O.NEW.KHUN.SV.W.BAD/\nProse after</note><identifier>"
      )

    first = @header <> "ALC089-052130-\n#{@vtec}\n$$\n"
    second = xml <> "ALZ001-052200-\n"
    raw = first <> second

    assert {:ok, %{cap: %CAP{}, segments: [warning, following], diagnostics: []}} = parse(raw)
    assert warning.raw_text == String.trim_trailing(first, "\n")
    assert following.raw_text == second
    assert Enum.map(warning.ugc_codes, & &1.raw_code) == ["ALC089"]
    assert Enum.map(following.ugc_codes, & &1.raw_code) == ["ALZ001"]
    assert following.vtec_codes == []

    bad_line = length(:binary.matches(raw, "\n")) + 1

    assert {:error, %NwsText.ParseError{code: :invalid_vtec, line: ^bad_line}} =
             parse(raw <> "/O.NEW.KHUN.SV.W.BAD/")
  end

  test "CAPWBC keepalive Test Alert retains CAP fields without treating XML geocodes as UGC headers" do
    raw = "XOUS55 KWBC 051553\nCAPWBC\n" <> @cap
    assert {:ok, product} = parse(raw)
    assert product.raw_text == raw
    assert hd(product.segments).raw_text =~ "<value>MDC031</value>"

    assert %CAP{
             identifier: "urn:oid:KEEPALIVE-16629",
             sender: "w-nws.webmaster@noaa.gov",
             status: "Test",
             message_type: "Alert",
             infos: [info]
           } = product.cap

    assert info.event_codes == [%{name: "NationalWeatherService", value: "TST"}]
    assert [%Area{description: "Montgomery", geocodes: [%{name: "UGC", value: "MDC031"}]}] = info.areas
    assert Enum.all?(product.segments, &(&1.ugc_codes == []))
  end

  test "Actual alert, update and cancel expose all infos, areas and references" do
    xml =
      @cap
      |> String.replace("<status>Test</status>", "<status>Actual</status>")
      |> String.replace("<value>TST</value>", "<value>SVR</value>")
      |> String.replace("<event>Test Message</event>", "<event>Severe Thunderstorm Warning</event>")

    for type <- ~w(Alert Update Cancel) do
      changed =
        xml
        |> String.replace("<msgType>Alert</msgType>", "<msgType>#{type}</msgType>")
        |> String.replace("<info>", "<references>other,sender,2026-10-05T15:00:00Z</references><info>")
        |> String.replace(
          "</info>",
          "<area><areaDesc>Second</areaDesc><geocode><valueName>SAME</valueName><value>001001</value></geocode></area></info><info><event>Other</event></info>"
        )

      assert {:ok, %{cap: %CAP{message_type: ^type} = cap}} = parse(@header <> changed)
      assert cap.references == ["other,sender,2026-10-05T15:00:00Z"]
      assert length(cap.infos) == 2
      assert length(hd(cap.infos).areas) == 2
    end
  end

  test "CAP preserves a TST event code even when status is Actual" do
    actual_test = String.replace(@cap, "<status>Test</status>", "<status>Actual</status>")
    assert {:ok, %{cap: %CAP{status: "Actual", infos: [info]}}} = parse(@header <> actual_test)
    assert info.event_codes == [%{name: "NationalWeatherService", value: "TST"}]
  end

  test "mixed VTEC statuses are retained across segments" do
    for other <- ~w(T Q O) do
      raw = @header <> @vtec <> "\n$$\n" <> String.replace(@vtec, "/O.", "/#{other}.") <> "\n"
      assert {:ok, %{segments: [first, second]}} = parse(raw)
      assert [%VTEC{status: "O"}] = first.vtec_codes
      assert [%VTEC{status: ^other}] = second.vtec_codes
    end
  end

  test "CAP fields use namespace URIs across prefix changes" do
    xml = """
    <a:alert xmlns:a="urn:oasis:names:tc:emergency:cap:1.2">
      <b:sent xmlns:b="urn:oasis:names:tc:emergency:cap:1.2">2026-10-05T15:53:00Z</b:sent>
      <a:status>Actual</a:status><a:msgType>Alert</a:msgType>
      <b:info xmlns:b="urn:oasis:names:tc:emergency:cap:1.2">
        <a:event>Flash Flood Warning</a:event>
        <c:eventCode xmlns:c="urn:oasis:names:tc:emergency:cap:1.2">
          <c:valueName>NationalWeatherService</c:valueName><c:value>FFW</c:value>
        </c:eventCode>
        <area xmlns="urn:oasis:names:tc:emergency:cap:1.2">
          <areaDesc>Guam</areaDesc><geocode><valueName>UGC</valueName><value>GUC100</value></geocode>
        </area>
        <b:area xmlns:b="urn:other"><b:areaDesc>Wrong area</b:areaDesc></b:area>
      </b:info>
    </a:alert>
    """

    assert {:ok, %{cap: %CAP{status: "Actual", message_type: "Alert", infos: [info]}}} = parse(@header <> xml)
    assert info.event == "Flash Flood Warning"
    assert info.event_codes == [%{name: "NationalWeatherService", value: "FFW"}]
    assert [%Area{description: "Guam", geocodes: [%{name: "UGC", value: "GUC100"}]}] = info.areas
  end

  test "foreign-namespace CAP fields do not appear as CAP status" do
    spoofed =
      @cap
      |> String.replace("<status>Test</status>", "<evil:status xmlns:evil=\"urn:other\">Actual</evil:status>")

    assert {:ok, %{cap: %CAP{status: nil}}} = parse(@header <> spoofed)
  end

  test "CAP keeps incomplete or unfamiliar decision fields instead of discarding parsed data" do
    for {xml, fields} <- [
          {String.replace(@cap, "Test</status>", "Unknown</status>"), %{status: "Unknown"}},
          {String.replace(@cap, "<status>Test</status>", ""), %{status: nil}},
          {String.replace(@cap, "<msgType>Alert</msgType>", "<msgType>Other</msgType>"), %{message_type: "Other"}},
          {String.replace(@cap, "<event>Test Message</event>", ""), %{infos: [%NwsText.Model.CAP.Info{event: nil}]}},
          {String.replace(@cap, "<msgType>Alert</msgType>", "<msgType>Cancel</msgType>"), %{references: []}},
          {String.replace(@cap, ~r/<info>.*?<\/info>/s, ""), %{infos: []}},
          {String.replace(@cap, "<identifier>urn:oid:KEEPALIVE-16629</identifier>", ""), %{identifier: nil}},
          {String.replace(@cap, "<sender>w-nws.webmaster@noaa.gov</sender>", ""), %{sender: nil}}
        ] do
      assert {:ok, %{cap: cap, diagnostics: []}} = parse(@header <> xml)

      case Map.get(fields, :infos) do
        [] -> assert cap.infos == []
        [_] -> assert [%NwsText.Model.CAP.Info{event: nil}] = cap.infos
        nil -> :ok
      end

      expected = Map.delete(fields, :infos)
      assert Map.take(cap, Map.keys(expected)) == expected
    end
  end

  test "hydrologic VTEC remains in raw text alongside parsed operational VTEC" do
    raw = @header <> @vtec <> "\n/05000.0.ER.261005T2010Z.261005T2100Z.261005T2200Z.NO/\n"
    assert {:ok, %{segments: [segment]}} = parse(raw)
    assert [%VTEC{status: "O"}] = segment.vtec_codes
    assert segment.raw_text =~ "/05000.0.ER.261005T2010Z.261005T2100Z.261005T2200Z.NO/"
  end

  test "malformed XML, unsafe declarations, and oversized XML produce diagnostics" do
    for xml <- [
          String.replace(@cap, "</alert>", ""),
          "<!DOCTYPE alert [<!ENTITY x SYSTEM \"file:///etc/passwd\">]>" <> @cap,
          "<alert>" <> String.duplicate("x", 1_000_001) <> "</alert>"
        ] do
      assert {:ok, %{cap: nil, diagnostics: [%NwsText.Diagnostic{} | _]}} = parse(@header <> xml)
    end
  end

  test "invalid CAP sent timestamp is diagnosed without inventing a parsed date" do
    xml = String.replace(@cap, "2026-10-05T15:53:00Z", "not-a-date")

    assert {:ok, %{cap: nil, diagnostics: [%NwsText.Diagnostic{code: :invalid_cap_timestamp, line: 4}]}} =
             parse(@header <> xml)
  end
end
