defmodule NwsText.ExploreTest do
  use ExUnit.Case, async: true

  alias NwsText.Model.{HydrologicVTEC, Motion, Segment, TextProduct, UGC, VTEC}

  test "loads a real product using its recorded reference time" do
    assert {:ok, %TextProduct{reference_time: ~U[2020-09-09 00:29:00Z], segments: [%Segment{} = segment]}} =
             NwsText.Explore.fixture()

    assert [%UGC{} | _] = segment.ugc_codes
    assert [%VTEC{} | _] = segment.vtec_codes
    assert [%Motion{}] = segment.motions
    assert %{name: "HAIL", value: "0.75IN"} in segment.impact_tags
    assert %Geo.Polygon{} = segment.polygon
  end

  test "can select a fixture and reports unknown paths" do
    assert {:ok, %TextProduct{awips_id: "AFDBOX"}} = NwsText.Explore.fixture("AFD.txt")
    assert {:ok, %TextProduct{segments: [segment | _]}} = NwsText.Explore.fixture("FFW/FFW_tags.txt")
    assert [%HydrologicVTEC{}] = segment.hydrologic_vtec

    assert_raise ArgumentError, ~r/unknown pyIEM fixture: missing.txt/, fn ->
      NwsText.Explore.fixture("missing.txt")
    end
  end
end
