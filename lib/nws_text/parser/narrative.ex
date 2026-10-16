defmodule NwsText.Parser.Narrative do
  @moduledoc false

  @tag ~r/^(FLASH FLOOD DAMAGE THREAT|THUNDERSTORM DAMAGE THREAT|TORNADO DAMAGE THREAT|SNOW SQUALL IMPACT|MAX HAIL SIZE|MAX WIND GUST|EXPECTED RAINFALL RATE|EXPECTED RAINFALL|DAM FAILURE|LEVEE FAILURE|HAIL THREAT|WIND THREAT|FLASH FLOOD|SNOW SQUALL|TORNADO|WATERSPOUT|LANDSPOUT|HAIL|WIND)\.\.\.(.+)$/i

  def tags(lines) do
    Enum.flat_map(lines, fn line ->
      case Regex.run(@tag, String.trim(line)) do
        [_, name, value] -> [%{name: String.upcase(name), value: String.trim(value)}]
        _ -> []
      end
    end)
  end

  def headlines(lines) do
    {headlines, _} =
      Enum.reduce(lines, {[], nil}, fn line, {found, pending} ->
        line = String.trim(line)

        cond do
          Regex.match?(~r/^\.+$/, line) -> {found, nil}
          String.starts_with?(line, "...") -> collect(found, String.trim_leading(line, "."))
          pending != nil -> collect(found, pending <> " " <> line)
          true -> {found, nil}
        end
      end)

    Enum.reverse(headlines)
  end

  defp collect(found, text) do
    if String.ends_with?(text, "...") do
      headline = text |> String.trim_trailing("...") |> String.split() |> Enum.join(" ")
      if headline == "", do: {found, nil}, else: {[headline | found], nil}
    else
      {found, text}
    end
  end
end
