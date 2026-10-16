defmodule NwsText.Parser.Dates do
  @moduledoc false
  import NimbleParsec

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

  letters = [?A..?Z, ?a..?z]
  digits = [?0..?9]
  whitespace = ascii_string([9..13, ?\s], min: 1)

  annotation =
    ignore(whitespace)
    |> ignore(string("("))
    |> ignore(ascii_string([0..40, 42..255], min: 1))
    |> ignore(string(")"))

  # AM/PM is optional only for UTC/GMT 24-hour times; valid_mnd?/4 enforces that.
  ampm = choice([string("AM"), string("PM"), string("am"), string("pm")]) |> ignore(whitespace)

  mnd =
    ascii_string(digits, min: 3, max: 4)
    |> ignore(optional(whitespace))
    |> choice([ampm, replace(empty(), "")])
    |> ascii_string(letters, min: 3, max: 4)
    |> optional(annotation)
    |> ignore(whitespace)
    |> ignore(ascii_string(letters ++ digits ++ [?_], min: 1))
    |> ignore(whitespace)
    |> ascii_string(letters, 3)
    |> ignore(whitespace)
    |> ascii_string(digits, min: 1, max: 2)
    |> ignore(whitespace)
    |> ascii_string(digits, 4)

  defparsecp(:parse_mnd, mnd)

  def resolve_day(<<day::binary-size(2), hour::binary-size(2), minute::binary-size(2)>>, reference) do
    base = Date.new!(reference.year, reference.month, 15)

    for shift <- [-1, 0, 1],
        month <- [Date.add(base, shift * 32) |> Date.beginning_of_month()],
        {:ok, date} <- [Date.new(month.year, month.month, String.to_integer(day))],
        {:ok, time} <- [Time.new(String.to_integer(hour), String.to_integer(minute), 0)],
        {:ok, datetime} <- [DateTime.new(date, time)] do
      datetime
    end
    |> Enum.min_by(&abs(DateTime.diff(&1, reference)), fn -> nil end)
    |> case do
      nil -> :error
      date -> {:ok, date}
    end
  end

  def vtec_timestamp("000000", "0000"), do: {:ok, nil}

  def vtec_timestamp(
        <<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2)>>,
        <<hh::binary-size(2), mi::binary-size(2)>>
      ) do
    with {:ok, date} <- Date.new(2000 + String.to_integer(yy), String.to_integer(mm), String.to_integer(dd)),
         {:ok, time} <- Time.new(String.to_integer(hh), String.to_integer(mi), 0),
         do: DateTime.new(date, time)
  end

  def product_date(raw, wmo) do
    case find_mnd(raw, nil) do
      {:ok, [hhmm, ampm, zone, month, day, year]} ->
        {:ok, hour, minute} = clock(hhmm, ampm, zone)
        month_number = Enum.find_index(@months, &(String.downcase(&1) == String.downcase(month))) + 1

        with {:ok, date} <- Date.new(String.to_integer(year), month_number, String.to_integer(day)),
             {:ok, time} <- Time.new(hour, minute, 0),
             {:ok, datetime} <- DateTime.new(date, time) do
          DateTime.add(
            datetime,
            -3600 * Map.fetch!(@zones, String.upcase(zone)),
            :second,
            Calendar.UTCOnlyTimeZoneDatabase
          )
        else
          _ -> wmo
        end

      :error ->
        wmo
    end
  end

  # Search prose at word boundaries for an MND timestamp.
  defp find_mnd(<<byte, rest::binary>> = text, previous) do
    match = if byte in ?0..?9 and not word?(previous), do: parse_candidate(text), else: :error

    case match do
      {:ok, _} = result -> result
      :error -> find_mnd(rest, byte)
    end
  end

  defp find_mnd(<<>>, _), do: :error

  defp parse_candidate(text) do
    case parse_mnd(text) do
      {:ok, [hhmm, ampm, zone, month, _day, _year] = fields, remaining, _, _, _} ->
        if valid_mnd?(ampm, zone, month, remaining) and match?({:ok, _, _}, clock(hhmm, ampm, zone)),
          do: {:ok, fields},
          else: :error

      _ ->
        :error
    end
  end

  # Follows pyIEM: PM accepts 24-hour hours (1300 PM is 13:00), and UTC/GMT may omit AM/PM.
  defp clock(hhmm, ampm, zone) do
    {hour, minute} =
      hhmm
      |> String.split_at(byte_size(hhmm) - 2)
      |> then(fn {h, m} -> {String.to_integer(h), String.to_integer(m)} end)

    hour =
      case String.upcase(ampm) do
        "AM" when hour in 0..12 -> rem(hour, 12)
        "PM" when hour in 1..11 -> hour + 12
        "PM" when hour in 12..23 -> hour
        "" when hour in 0..23 -> if String.upcase(zone) in ~w(UTC GMT), do: hour
        _ -> nil
      end

    if hour && minute in 0..59, do: {:ok, hour, minute}, else: :error
  end

  defp valid_mnd?(ampm, zone, month, remaining) do
    String.upcase(ampm) in ["AM", "PM", ""] and Map.has_key?(@zones, String.upcase(zone)) and
      Enum.any?(@months, &(String.downcase(&1) == String.downcase(month))) and
      not word?(next_byte(remaining))
  end

  defp next_byte(<<byte, _::binary>>), do: byte
  defp next_byte(<<>>), do: nil
  defp word?(byte) when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte == ?_, do: true
  defp word?(_), do: false
end
