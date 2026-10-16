defmodule NwsText.Parser.Motion do
  @moduledoc false
  import NimbleParsec

  alias NwsText.Model.Motion

  digits = [?0..?9]
  space = ignore(ascii_string([?\s, ?\t], min: 1))
  coordinate = ascii_string(digits, min: 4, max: 5)

  fields =
    ascii_string(digits, 4)
    |> ignore(string("Z"))
    |> concat(space)
    |> ascii_string(digits, min: 1, max: 3)
    |> ignore(string("DEG"))
    |> concat(space)
    |> ascii_string(digits, min: 1, max: 3)
    |> ignore(string("KT"))
    |> concat(space)
    |> concat(coordinate)
    |> repeat(space |> concat(coordinate))

  defparsecp(:parse_fields, fields)

  def parse(line, expiry, center \\ nil) do
    with true <- String.starts_with?(line, "TIME...MOT...LOC "),
         text = String.replace_prefix(line, "TIME...MOT...LOC ", "") |> String.trim(),
         {:ok, [clock, direction, speed | coordinates], "", _, _, _} <- parse_fields(text),
         {:ok, time} <-
           Time.new(String.to_integer(binary_part(clock, 0, 2)), String.to_integer(binary_part(clock, 2, 2)), 0),
         true <- String.to_integer(direction) <= 360,
         true <- rem(length(coordinates), 2) == 0 and coordinates != [],
         points = coordinates |> Enum.chunk_every(2) |> Enum.map(&point(&1, center)),
         true <- Enum.all?(points, &match?(%Geo.Point{}, &1)) do
      {:ok,
       %Motion{
         raw_line: line,
         time: clock <> "Z",
         valid_at: resolve_time(expiry, time),
         direction_degrees: String.to_integer(direction),
         speed_knots: String.to_integer(speed),
         points: points
       }}
    else
      _ -> :error
    end
  end

  defp resolve_time(nil, _), do: nil

  defp resolve_time(expiry, time) do
    {:ok, datetime} = expiry |> DateTime.to_date() |> DateTime.new(time)

    if DateTime.compare(datetime, expiry) == :gt,
      do: DateTime.add(datetime, -86_400, :second, Calendar.UTCOnlyTimeZoneDatabase),
      else: datetime
  end

  defp point([lat, lon], center) do
    latitude = String.to_integer(lat) / 100
    longitude = String.to_integer(lon) / 100
    longitude = if byte_size(lon) == 4 and longitude < 40, do: longitude + 100, else: longitude

    if latitude >= 0 and latitude <= 90 and longitude >= 0 and longitude <= 180 do
      # Motion coordinates also omit hemisphere. PGUM is east; other centers default west.
      longitude = if center == "PGUM", do: longitude, else: -longitude
      %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
    end
  end
end
