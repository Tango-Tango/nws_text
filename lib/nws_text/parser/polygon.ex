defmodule NwsText.Parser.Polygon do
  @moduledoc false
  import NimbleParsec

  defparsecp(:parse_coordinate, choice([ascii_string([?0..?9], 5), ascii_string([?0..?9], 4)]))

  def parse(lines, number, center \\ nil) do
    [first | rest] = Enum.drop(lines, number - 1)
    coordinate_lines = [first | Enum.take_while(rest, &continuation_line?/1)]
    tokens = Enum.flat_map(coordinate_lines, &coordinate_tokens/1)

    if Enum.all?(tokens, &valid_token?/1) and rem(length(tokens), 2) == 0 and length(tokens) >= 6 do
      points = tokens |> Enum.chunk_every(2) |> Enum.map(&coordinate(&1, center))
      if Enum.all?(points, &valid_coordinate?/1), do: polygon_from_points(points), else: :error
    else
      :error
    end
  end

  defp continuation_line?(line) do
    case String.trim_leading(line) do
      <<digit, _::binary>> when digit in ?0..?9 -> true
      _ -> false
    end
  end

  defp coordinate_tokens(line), do: line |> String.trim() |> String.replace_prefix("LAT...LON", "") |> String.split()

  defp valid_token?(token) do
    match?({:ok, [_], "", _, _, _}, parse_coordinate(token))
  end

  defp coordinate([lat, lon], center) do
    longitude = String.to_integer(lon) / 100
    longitude = if byte_size(lon) == 4 and longitude < 40, do: longitude + 100, else: longitude
    # LAT...LON has no hemisphere marker. PGUM is east; other centers default west.
    longitude = if center == "PGUM", do: longitude, else: -longitude
    {longitude, String.to_integer(lat) / 100}
  end

  defp valid_coordinate?({lon, lat}), do: lon >= -180 and lon <= 180 and lat >= 0 and lat <= 90

  defp polygon_from_points(points) do
    ring = if hd(points) == List.last(points), do: points, else: points ++ [hd(points)]
    {:ok, %Geo.Polygon{coordinates: [ring], srid: 4326}}
  end
end
