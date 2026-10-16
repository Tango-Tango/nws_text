defmodule NwsText.PyIEMCorpusTest do
  use ExUnit.Case, async: true

  @fixtures Path.expand("fixtures/pyiem", __DIR__)
  @paths @fixtures |> Path.join("**/*.txt") |> Path.wildcard() |> Enum.map(&Path.relative_to(&1, @fixtures))

  defp cases, do: @fixtures |> Path.join("expected.json") |> File.read!() |> Jason.decode!()

  setup_all do
    cases = cases()
    {:ok, cases: cases, expectations: Map.new(cases, &{&1["path"], &1})}
  end

  test "corpus covers at least 100 distinct products and coded fields across families", %{cases: cases} do
    paths = Enum.map(cases, & &1["path"])
    files = @paths
    assert length(paths) >= 100
    assert Enum.sort(paths) == Enum.sort(files)
    assert length(Enum.uniq(paths)) == length(paths)
    assert length(Enum.uniq(Enum.map(cases, &String.slice(&1["awips_id"] || "", 0, 3)))) >= 15
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["ugc_codes"] != [] end)) >= 40
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["vtec"] != [] end)) >= 40
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["polygon"] != nil end)) >= 20
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["hydrologic_vtec"] != [] end)) >= 20
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["motions"] != [] end)) >= 20
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["impact_tags"] != [] end)) >= 20
    assert Enum.count(cases, &Enum.any?(&1["segments"] || [], fn segment -> segment["headlines"] != [] end)) >= 40
    assert Enum.any?(cases, &(&1["awips_id"] == "AFDPQ"))
  end

  test "fixture failures identify the source product", %{cases: cases} do
    expected = cases |> hd() |> Map.put("sha256", "wrong")

    assert_raise ExUnit.AssertionError, ~r/AFD\.txt/, fn ->
      assert_case(expected)
    end
  end

  for path <- @paths do
    @path path
    test "#{path}: raw to parsed contract", %{expectations: expectations} do
      assert_case(Map.fetch!(expectations, @path))
    end
  end

  defp assert_case(expected) do
    raw = File.read!(Path.join(@fixtures, expected["path"]))
    assert Base.encode16(:crypto.hash(:sha256, raw), case: :lower) == expected["sha256"]
    {:ok, reference_time, 0} = DateTime.from_iso8601(expected["reference_time"])

    case NwsText.parse(raw, reference_time: reference_time) do
      {:error, error} ->
        assert expected["error"] == Atom.to_string(error.code)
        assert expected["error_line"] == error.line

      {:ok, product} ->
        refute Map.has_key?(expected, "error")
        assert product.raw_text == raw
        assert product.reference_time == reference_time
        assert Enum.map(product.segments, & &1.index) == Enum.to_list(0..(length(product.segments) - 1))
        assert product.wmo_id == expected["wmo_id"]
        assert product.issuing_center == expected["issuing_center"]
        assert product.wmo_date_group == expected["wmo_date_group"]
        assert product.awips_id == expected["awips_id"]
        assert product.correction_code == expected["correction_code"]
        assert product.cap == nil
        assert DateTime.to_iso8601(product.wmo_issued_at) == expected["wmo_issued_at"]
        assert DateTime.to_iso8601(product.issued_at) == expected["issued_at"]

        assert Enum.map(product.segments, &segment_fields/1) == expected["segments"]
    end
  rescue
    error in ExUnit.AssertionError ->
      reraise %{error | message: "#{expected["path"]}: #{error.message}"}, __STACKTRACE__
  end

  defp segment_fields(segment) do
    %{
      "ugc_codes" => Enum.map(segment.ugc_codes, & &1.raw_code),
      "ugc_expires_at" => iso(segment.ugc_expires_at),
      "vtec" =>
        Enum.map(segment.vtec_codes, fn code ->
          %{
            "raw_line" => code.raw_line,
            "status" => code.status,
            "action" => code.action,
            "office" => code.office,
            "phenomenon" => code.phenomenon,
            "significance" => code.significance,
            "event_tracking_number" => code.event_tracking_number,
            "begins_at" => iso(code.begins_at),
            "ends_at" => iso(code.ends_at)
          }
        end),
      "hydrologic_vtec" =>
        Enum.map(segment.hydrologic_vtec, fn code ->
          %{
            "raw_line" => code.raw_line,
            "nwsli" => code.nwsli,
            "severity" => code.severity,
            "cause" => code.cause,
            "begins_at" => iso(code.begins_at),
            "crests_at" => iso(code.crests_at),
            "ends_at" => iso(code.ends_at),
            "record" => code.record
          }
        end),
      "motions" =>
        Enum.map(segment.motions, fn motion ->
          %{
            "raw_line" => motion.raw_line,
            "time" => motion.time,
            "valid_at" => iso(motion.valid_at),
            "direction_degrees" => motion.direction_degrees,
            "speed_knots" => motion.speed_knots,
            "points" => Enum.map(motion.points, fn point -> Tuple.to_list(point.coordinates) end)
          }
        end),
      "headlines" => segment.headlines,
      "impact_tags" => Enum.map(segment.impact_tags, &%{"name" => &1.name, "value" => &1.value}),
      "polygon" => if(segment.polygon, do: Enum.map(hd(segment.polygon.coordinates), fn {lon, lat} -> [lon, lat] end))
    }
  end

  defp iso(nil), do: nil
  defp iso(date), do: DateTime.to_iso8601(date)
end
