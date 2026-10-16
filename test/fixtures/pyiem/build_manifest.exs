# Independently derive fixture expectations; never call NwsText.parse/2.
defmodule PyIEMManifest do
  @moduledoc false

  @root __DIR__
  @reference ~U[2026-10-05 12:00:00Z]
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @zones %{
    "UTC" => 0,
    "GMT" => 0,
    "EST" => -5,
    "EDT" => -4,
    "CST" => -6,
    "CDT" => -5,
    "MST" => -7,
    "MDT" => -6,
    "PST" => -8,
    "PDT" => -7,
    "AST" => -4,
    "ADT" => -3,
    "AKST" => -9,
    "AKDT" => -8,
    "HST" => -10,
    "SST" => -11,
    "CHST" => 10
  }

  @wmo ~r/^([A-Z]{4}\d{2}) ([A-Z]{4}) (\d{6})(?: ([A-Z]{3}))?$/
  @mnd ~r/\b(\d{1,2})(\d{2})\s*(?:(AM|PM)\s+)?(UTC|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|AST|ADT|AKST|AKDT|HST|SST|ChST)(?:\s+\([^)]+\))?\s+\w+\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{4})\b/i
  @ugc_start ~r/^[A-Z]{2}[CZ]\d{3}(?:-|>)/
  @ugc_part ~r/^([A-Z]{2}[CZ])?(\d{3})(?:>(\d{3}))?$/
  @ugc_cont ~r/^(?:[A-Z]{2}[CZ])?\d{3}(?:-|>|\d{3}-)/
  @ugc_end ~r/-\d{6}-$/
  @ugc_line ~r/^(.+)-(\d{6})-$/
  @vtec ~r|^/([A-Z])\.([A-Z]{3})\.([A-Z0-9]{4})\.([A-Z]{2})\.([A-Z])\.(\d{4})\.(\d{6}T\d{4}Z)-(\d{6}T\d{4}Z)/$|
  @hydrologic ~r|^/([A-Z0-9]{5})\.([N0123U])\.([A-Z]{2})\.(\d{6}T\d{4}Z)\.(\d{6}T\d{4}Z)\.(\d{6}T\d{4}Z)\.([A-Z]{2})/$|
  @motion ~r/^TIME\.\.\.MOT\.\.\.LOC (\d{4})Z (\d{1,3})DEG (\d{1,3})KT (\d{4,5}(?:\s+\d{4,5})*)$/
  @impact ~r/^(FLASH FLOOD DAMAGE THREAT|THUNDERSTORM DAMAGE THREAT|TORNADO DAMAGE THREAT|SNOW SQUALL IMPACT|MAX HAIL SIZE|MAX WIND GUST|EXPECTED RAINFALL RATE|EXPECTED RAINFALL|DAM FAILURE|LEVEE FAILURE|HAIL THREAT|WIND THREAT|FLASH FLOOD|SNOW SQUALL|TORNADO|WATERSPOUT|LANDSPOUT|HAIL|WIND)\.\.\.(.+)$/i
  @polygon_line ~r/^(?:\s*LAT\.\.\.LON)?\s*\d{4,5}(?:\s+\d{4,5})*\s*$/
  @coordinate ~r/^\d{4,5}$/

  def run do
    cases =
      @root
      |> Path.join("**/*.txt")
      |> Path.wildcard()
      |> Enum.sort_by(&Path.split(Path.relative_to(&1, @root)))
      |> Enum.map(&expectation/1)

    File.write!(Path.join(@root, "expected.json"), Jason.encode!(cases, pretty: true) <> "\n")
    IO.puts("Wrote #{length(cases)} independent raw-source expectations")
  end

  # Preserve the checked-in manifest's key order across regenerations.
  defp obj(fields), do: Jason.OrderedObject.new(fields)
  defp iso(date), do: DateTime.to_iso8601(date)

  defp utc(year, month, day, hour, minute) do
    with {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- Time.new(hour, minute, 0),
         {:ok, datetime} <- DateTime.new(date, time),
         do: datetime,
         else: (_ -> nil)
  end

  defp nearest_group(<<day::binary-size(2), hour::binary-size(2), minute::binary-size(2)>>, reference) do
    base = reference.year * 12 + reference.month - 1

    for shift <- [-1, 0, 1],
        month_index = base + shift,
        datetime =
          utc(
            div(month_index, 12),
            rem(month_index, 12) + 1,
            String.to_integer(day),
            String.to_integer(hour),
            String.to_integer(minute)
          ),
        datetime != nil do
      datetime
    end
    |> Enum.min_by(&abs(DateTime.diff(&1, reference, :microsecond)))
  end

  defp clock_hour(hour, "AM", _zone) when hour <= 12, do: rem(hour, 12)
  defp clock_hour(hour, "PM", _zone) when hour in 1..11, do: hour + 12
  defp clock_hour(hour, "PM", _zone) when hour in 12..23, do: hour
  defp clock_hour(hour, "", zone) when hour <= 23 and zone in ["UTC", "GMT"], do: hour
  defp clock_hour(_hour, _ampm, _zone), do: nil

  defp issue_date(raw, fallback) do
    # Like pyIEM: PM may carry a 24-hour hour, and UTC/GMT may omit AM/PM. Skip impossible clocks.
    @mnd
    |> Regex.scan(raw)
    |> Enum.find_value(fn [_, hour, minute, ampm | rest] ->
      with hour when hour != nil <- clock_hour(String.to_integer(hour), String.upcase(ampm), String.upcase(hd(rest))),
           true <- String.to_integer(minute) < 60,
           do: [hour, minute, ampm | rest],
           else: (_ -> nil)
    end)
    |> case do
      [hour, minute, _ampm, zone, month, day, year] ->
        month_number = Enum.find_index(@months, &(String.downcase(&1) == String.downcase(month))) + 1

        case utc(String.to_integer(year), month_number, String.to_integer(day), hour, String.to_integer(minute)) do
          nil ->
            fallback

          datetime ->
            DateTime.add(
              datetime,
              -3600 * Map.fetch!(@zones, String.upcase(zone)),
              :second,
              Calendar.UTCOnlyTimeZoneDatabase
            )
        end

      _ ->
        fallback
    end
  end

  defp expand_ugc(line, wmo) do
    [_, head, expiration] = Regex.run(@ugc_line, line)

    {codes, _prefix} =
      Enum.reduce(String.split(head, "-"), {[], nil}, fn token, {codes, previous} ->
        {prefix, first, last} = ugc_token(token, line)
        prefix = if prefix == "", do: previous, else: prefix
        last = if last == "", do: first, else: last
        {codes ++ expand_range(prefix, String.to_integer(first), String.to_integer(last)), prefix}
      end)

    {codes, iso(nearest_group(expiration, wmo))}
  end

  defp expand_range(prefix, from, to) when from <= to,
    do: for(number <- from..to, do: prefix <> String.pad_leading(Integer.to_string(number), 3, "0"))

  defp expand_range(_prefix, _from, _to), do: []

  defp ugc_token(token, line) do
    case Regex.run(@ugc_part, token) do
      [_, prefix, first, last] -> {prefix, first, last}
      [_, prefix, first] -> {prefix, first, first}
      _ -> raise "unexpected UGC token: #{line}"
    end
  end

  defp join_ugc(line, [next | rest]) do
    next = String.trim(next)

    if not Regex.match?(@ugc_end, line) and Regex.match?(@ugc_cont, next) do
      join_ugc(line <> next, rest)
    else
      {line, [next | rest]}
    end
  end

  defp join_ugc(line, []), do: {line, []}

  defp vtec_time("000000T0000Z"), do: nil

  defp vtec_time(
         <<year::binary-size(2), month::binary-size(2), day::binary-size(2), "T", hour::binary-size(2),
           minute::binary-size(2), "Z">>
       ) do
    (2000 + String.to_integer(year))
    |> utc(String.to_integer(month), String.to_integer(day), String.to_integer(hour), String.to_integer(minute))
    |> iso()
  end

  defp vtec_fields(line) do
    [_, status, action, office, phenomenon, significance, number, begins, ends] = Regex.run(@vtec, line)

    obj([
      {"raw_line", line},
      {"status", status},
      {"action", action},
      {"office", office},
      {"phenomenon", phenomenon},
      {"significance", significance},
      {"event_tracking_number", String.to_integer(number)},
      {"begins_at", vtec_time(begins)},
      {"ends_at", vtec_time(ends)}
    ])
  end

  defp hydrologic_fields(line) do
    [_, nwsli, severity, cause, begins, crests, ends, record] = Regex.run(@hydrologic, line)

    obj([
      {"raw_line", line},
      {"nwsli", nwsli},
      {"severity", severity},
      {"cause", cause},
      {"begins_at", vtec_time(begins)},
      {"crests_at", vtec_time(crests)},
      {"ends_at", vtec_time(ends)},
      {"record", record}
    ])
  end

  defp motion_fields(line, expiry, center) do
    [_, clock, direction, speed, coordinates] = Regex.run(@motion, line)

    points =
      coordinates
      |> String.split()
      |> Enum.chunk_every(2)
      |> Enum.map(fn [lat, lon] ->
        west = String.to_integer(lon) / 100
        west = if byte_size(lon) == 4 and west < 40, do: west + 100, else: west
        [if(center == "PGUM", do: west, else: -west), String.to_integer(lat) / 100]
      end)

    valid_at =
      if expiry do
        {:ok, expires, _} = DateTime.from_iso8601(expiry)
        hh = clock |> String.slice(0, 2) |> String.to_integer()
        mm = clock |> String.slice(2, 2) |> String.to_integer()
        time = utc(expires.year, expires.month, expires.day, hh, mm)

        if DateTime.compare(time, expires) == :gt,
          do: iso(DateTime.add(time, -86_400, :second, Calendar.UTCOnlyTimeZoneDatabase)),
          else: iso(time)
      end

    obj([
      {"raw_line", line},
      {"time", clock <> "Z"},
      {"valid_at", valid_at},
      {"direction_degrees", String.to_integer(direction)},
      {"speed_knots", String.to_integer(speed)},
      {"points", points}
    ])
  end

  defp impact_tags(lines) do
    Enum.flat_map(lines, fn line ->
      case Regex.run(@impact, String.trim(line)) do
        [_, name, value] -> [obj([{"name", String.upcase(name)}, {"value", String.trim(value)}])]
        _ -> []
      end
    end)
  end

  defp headlines(lines) do
    lines
    |> Enum.join("\n")
    |> then(&Regex.scan(~r/^\s*\.{3}(.+?)\.{3}[ \t]*$/ms, &1))
    |> Enum.map(fn [_, headline] -> headline |> String.split() |> Enum.join(" ") end)
    |> Enum.reject(&Regex.match?(~r/^\.+$/, &1))
  end

  defp polygon(lines, center) do
    tokens = lines |> Enum.join(" ") |> String.replace_prefix("LAT...LON", "") |> String.split()

    if length(tokens) >= 6 and rem(length(tokens), 2) == 0 and Enum.all?(tokens, &Regex.match?(@coordinate, &1)) do
      polygon_points(tokens, center)
    end
  end

  defp polygon_points(tokens, center) do
    points =
      Enum.chunk_every(tokens, 2)
      |> Enum.map(fn [latitude, longitude] ->
        lon = String.to_integer(longitude) / 100
        lon = if byte_size(longitude) == 4 and lon < 40, do: lon + 100, else: lon
        [if(center == "PGUM", do: lon, else: -lon), String.to_integer(latitude) / 100]
      end)

    if Enum.all?(points, fn [lon, lat] -> lon >= -180 and lon <= 180 and lat >= 0 and lat <= 90 end) do
      if hd(points) == List.last(points), do: points, else: points ++ [hd(points)]
    end
  end

  defp scan([], _, _, codes, expiry, vtecs, polygon), do: {codes, expiry, vtecs, polygon}

  defp scan([line | rest], wmo, center, codes, expiry, vtecs, polygon) do
    line = String.trim(line)

    cond do
      Regex.match?(@ugc_start, line) ->
        {joined, remaining} = join_ugc(line, rest)
        {new_codes, new_expiry} = expand_ugc(joined, wmo)
        scan(remaining, wmo, center, codes ++ new_codes, new_expiry, vtecs, polygon)

      Regex.match?(@vtec, line) ->
        scan(rest, wmo, center, codes, expiry, vtecs ++ [vtec_fields(line)], polygon)

      String.starts_with?(line, "LAT...LON") ->
        continuation = Enum.take_while(rest, &Regex.match?(@polygon_line, &1))
        scan(rest, wmo, center, codes, expiry, vtecs, polygon([line | continuation], center) || polygon)

      true ->
        scan(rest, wmo, center, codes, expiry, vtecs, polygon)
    end
  end

  defp segments(raw, wmo, center) do
    raw
    |> String.split(~r/(?<=\$\$)\r*\n/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(fn chunk ->
      lines = String.split(chunk, "\n")
      {codes, expiry, vtecs, polygon} = scan(lines, wmo, center, [], nil, [], nil)

      hydro = for line <- lines, line = String.trim(line), Regex.match?(@hydrologic, line), do: hydrologic_fields(line)

      motions =
        for line <- lines,
            line = String.trim(line),
            Regex.match?(@motion, line),
            do: motion_fields(line, expiry, center)

      obj([
        {"ugc_codes", codes},
        {"ugc_expires_at", expiry},
        {"vtec", vtecs},
        {"hydrologic_vtec", hydro},
        {"motions", motions},
        {"headlines", headlines(lines)},
        {"impact_tags", impact_tags(lines)},
        {"polygon", polygon}
      ])
    end)
  end

  defp expectation(path) do
    raw = File.read!(path)

    base = [
      {"path", Path.relative_to(path, @root)},
      {"sha256", Base.encode16(:crypto.hash(:sha256, raw), case: :lower)}
    ]

    lines = raw |> String.split("\n") |> Enum.map(&(String.replace(&1, ~r/[\x00-\x1f]/, "") |> String.trim()))
    {skipped, remaining} = Enum.split_while(lines, &(&1 == "" or Regex.match?(~r/^\d{3}$/, &1)))

    case remaining do
      [line | tail] ->
        case Regex.run(@wmo, line) do
          [_, wmo_id, center, group] ->
            product(raw, tail, base, wmo_id, center, group, nil)

          [_, wmo_id, center, group, correction] ->
            product(raw, tail, base, wmo_id, center, group, correction)

          _ ->
            obj(
              base ++
                [
                  {"reference_time", iso(@reference)},
                  {"error", "invalid_wmo_header"},
                  {"error_line", length(skipped) + 1}
                ]
            )
        end

      _ ->
        obj(
          base ++
            [{"reference_time", iso(@reference)}, {"error", "invalid_wmo_header"}, {"error_line", length(skipped) + 1}]
        )
    end
  end

  defp product(raw, tail, base, wmo_id, center, group, correction) do
    reference = issue_date(raw, @reference)
    wmo = nearest_group(group, reference)
    issued = issue_date(raw, wmo)

    awips =
      case tail do
        [line | _] -> if Regex.match?(~r/^[A-Z0-9]{4,6}$/, line), do: line
        _ -> nil
      end

    parts = segments(raw, wmo, center)

    obj(
      base ++
        [
          {"reference_time", iso(reference)},
          {"wmo_id", wmo_id},
          {"issuing_center", center},
          {"wmo_date_group", group},
          {"correction_code", correction},
          {"awips_id", awips},
          {"wmo_issued_at", iso(wmo)},
          {"issued_at", iso(issued)},
          {"segments", parts}
        ]
    )
  end
end

PyIEMManifest.run()
