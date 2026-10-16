defmodule NwsText.NarrativeTest do
  use ExUnit.Case, async: true

  alias NwsText.Model.Narrative

  defp narrative(path), do: "test/fixtures/#{path}" |> File.read!() |> narrative_text()

  defp narrative_text(text) do
    assert {:ok, %Narrative{} = narrative} = NwsText.parse_narrative(text)
    narrative
  end

  defp section(narrative, label), do: Enum.find(narrative.sections, &(&1.label == label))
  defp labels(narrative), do: Enum.map(narrative.sections, & &1.label)

  test "body text without a WMO header exposes headlines, labeled sections, and tags" do
    narrative = narrative("narrative/FLS_MLB_astor.txt")

    assert narrative.headlines == [
             "The Flood Warning continues for the following rivers in Florida",
             "FLOOD WARNING REMAINS IN EFFECT UNTIL FURTHER NOTICE"
           ]

    assert narrative.sections == [
             %{
               label: "PRECAUTIONARY/PREPAREDNESS ACTIONS",
               text:
                 "Motorists should not attempt to drive around barricades or drive cars\n" <>
                   "through flooded areas.\n\nCaution is urged when walking near riverbanks.\n\n" <>
                   "Additional information is available at www.weather.gov.\n\n" <>
                   "The next statement will be issued this evening at 1100 PM EDT."
             },
             %{label: "WHAT", text: "Minor flooding is occurring and minor flooding is forecast."},
             %{label: "WHERE", text: "St Johns River near Astor."},
             %{label: "WHEN", text: "Until further notice."},
             %{
               label: "IMPACT",
               text:
                 "At 3.0 feet, Water approaches or may enter lowest homes\n" <>
                   "on or near Wildhog Road and nearby canals. Flooding reaches the\n" <>
                   "parking lot of the Juno Trail Apartments. Flooding on portions of\n" <>
                   "Alligator Road and Holiday Road. Lowest lying yards along Blue\n" <>
                   "Creek are flooded. Roads at Astor Landing Campground and Lake\n" <>
                   "Dexter Boat Ramp begin to flood. Water enters lower homes closest\n" <>
                   "to the river on McPherson Lane."
             },
             %{
               label: "ADDITIONAL DETAILS",
               text:
                 "- At 9:30 AM EDT Tuesday the stage was 2.9 feet.\n" <>
                   "- Bankfull stage is 2.0 feet.\n" <>
                   "- Recent Activity...The maximum river stage in the 24 hours ending\n" <>
                   "at 9:30 AM EDT Tuesday was 3.1 feet.\n" <>
                   "- Forecast...The river is expected to remain steady above flood\n" <>
                   "stage at 2.9 feet.\n" <>
                   "- Flood stage is 2.3 feet.\n" <>
                   "- http://www.weather.gov/safety/flood"
             }
           ]

    assert narrative.impact_tags == []
  end

  test "captured flood statements share the hazard simplification layout" do
    for {path, actions?} <- [
          {"FLS_JAX_atkinson.txt", false},
          {"FLS_MOB_crestview.txt", true},
          {"FLS_LCH_white_oak.txt", true},
          {"FLS_CAE_carolina_eastman.txt", true}
        ] do
      narrative = narrative("narrative/" <> path)
      bullets = ["WHAT", "WHERE", "WHEN", "IMPACT", "ADDITIONAL DETAILS"]
      assert labels(narrative) == if(actions?, do: ["PRECAUTIONARY/PREPAREDNESS ACTIONS" | bullets], else: bullets)
      assert String.ends_with?(section(narrative, "ADDITIONAL DETAILS").text, "- http://www.weather.gov/safety/flood")
    end

    jax = narrative("narrative/FLS_JAX_atkinson.txt")
    assert section(jax, "WHERE").text == "Satilla River at Atkinson."

    assert jax.headlines == [
             "The Flood Warning continues for the following rivers in southeast Georgia",
             "FLOOD WARNING REMAINS IN EFFECT UNTIL FURTHER NOTICE"
           ]
  end

  test "actions end at the next date line, and text after && stays out of sections" do
    lch = narrative("narrative/FLS_LCH_white_oak.txt")

    assert section(lch, "PRECAUTIONARY/PREPAREDNESS ACTIONS").text ==
             "Turn around, don't drown when encountering flooded roads. Most flood\n" <>
               "deaths occur in vehicles.\n\n" <>
               "Motorists should not attempt to drive around barricades or drive cars\n" <>
               "through flooded areas.\n\nAdditional information is available at www.weather.gov."

    refute Enum.any?(lch.sections, &(&1.text =~ "All Times CDT"))
    assert length(lch.headlines) == 4
    assert "The Flood Warning is cancelled for the following rivers in Texas" in lch.headlines
  end

  test "impact-based warning sections end before the following locations paragraph" do
    meg = narrative("pyiem/SVRMEG/SVRMEG_1.txt")
    assert labels(meg) == ["HAZARD", "SOURCE", "IMPACT", "PRECAUTIONARY/PREPAREDNESS ACTIONS"]
    assert section(meg, "SOURCE").text == "Radar indicated."
    refute section(meg, "IMPACT").text =~ "Locations impacted include"

    psr = narrative("pyiem/SVR/SVRPSR.txt")
    assert section(psr, "HAZARD").text == "60 mph wind gusts and penny size hail."
    assert section(psr, "IMPACT").text == "Expect damage to roofs, siding, and trees."
    refute section(psr, "PRECAUTIONARY/PREPAREDNESS ACTIONS").text =~ "LAT...LON"
    assert %{name: "HAIL", value: "0.75IN"} in psr.impact_tags
  end

  test "indented sub-bullets after a blank line stay in their section" do
    grr = narrative("pyiem/WSWGRR/13.txt")
    impact = section(grr, "IMPACT").text
    assert impact =~ "* ROADS WILL BE ICY AND SNOW COVERED"
    assert impact =~ "* FROSTBITE COULD OCCUR IN 45 MINUTES OR LESS ON EXPOSED SKIN."
    refute impact =~ "PRECAUTIONARY"
  end

  test "double carriage returns count as one line break" do
    ama = narrative("pyiem/WSWAMA/WSWAMA_05.txt")

    assert section(ama, "IMPACT").text ==
             "DRIVING CONDITIONS WILL BECOME NEARLY IMPOSSIBLE.\n" <>
               "POWER OUTAGES MAY OCCUR. DAMAGE TO TREES AND POWER LINES IS\n" <>
               "POSSIBLE. COMMERCE WILL LIKELY BE IMPACTED. ALSO...ICE ON\n" <>
               "SIDEWALKS... PORCHES...AND DRIVEWAYS WILL MAKE WALKING\nHAZARDOUS."

    refute Enum.any?(ama.sections, &String.contains?(&1.text, "\r"))
  end

  test "only known labels become sections" do
    tor = narrative("pyiem/TORtag.txt")
    assert labels(tor) == ["PRECAUTIONARY/PREPAREDNESS ACTIONS"]

    assert narrative_text("* WINDS: SOUTHEAST 20 KNOTS.\n* AT 1132 PM CDT...RADAR INDICATED A STORM.\n").sections ==
             []

    assert narrative_text("* WHAT...\n\n").sections == []
  end

  test "non-text input is rejected" do
    assert {:error, %NwsText.ParseError{code: :invalid_input}} = NwsText.parse_narrative(nil)
  end
end
