defmodule NwsText.Parser.WMO do
  @moduledoc false
  import NimbleParsec

  alias NwsText.ParseError
  alias NwsText.Parser.Dates

  upper = ascii_string([?A..?Z], 4)
  digits = ascii_string([?0..?9], 2)

  wmo =
    upper
    |> concat(digits)
    |> ignore(string(" "))
    |> concat(upper)
    |> ignore(string(" "))
    |> ascii_string([?0..?9], 6)
    |> optional(ignore(string(" ")) |> ascii_string([?A..?Z], 3))

  defparsecp(:parse_wmo, wmo)
  defparsecp(:parse_awips, ascii_string([?A..?Z, ?0..?9], min: 4, max: 6))
  defparsecp(:parse_preamble, ascii_string([?0..?9], 3))

  def parse_header(line) do
    case parse_wmo(line) do
      {:ok, [id, suffix, center, date_group], "", _, _, _} ->
        {:ok, %{wmo_id: id <> suffix, issuing_center: center, wmo_date_group: date_group, correction_code: nil}}

      {:ok, [id, suffix, center, date_group, correction], "", _, _, _} ->
        {:ok, %{wmo_id: id <> suffix, issuing_center: center, wmo_date_group: date_group, correction_code: correction}}

      _ ->
        :error
    end
  end

  def parse(raw, reference) do
    lines = raw |> String.split("\n") |> Enum.map(&strip_controls/1)
    preamble? = &(&1 == "" or match?({:ok, [_], "", _, _, _}, parse_preamble(&1)))
    {skipped, remaining} = Enum.split_while(lines, preamble?)

    case remaining do
      [line | tail] when length(skipped) <= 3 ->
        case parse_header(line) do
          {:ok, fields} -> build_header(raw, reference, fields, tail, length(skipped) + 1)
          :error -> invalid_header(length(skipped) + 1)
        end

      _ ->
        invalid_header(1)
    end
  end

  defp build_header(raw, reference, fields, lines, line_number) do
    case Dates.resolve_day(fields.wmo_date_group, reference) do
      {:ok, issued} ->
        {:ok,
         Map.merge(fields, %{
           awips_id: awips_id(lines),
           wmo_issued_at: issued,
           issued_at: Dates.product_date(raw, issued)
         })}

      :error ->
        {:error, %ParseError{code: :invalid_wmo_date, line: line_number, message: "invalid WMO date group"}}
    end
  end

  defp awips_id([line | _]) do
    case parse_awips(String.trim(line)) do
      {:ok, [id], "", _, _, _} -> id
      _ -> nil
    end
  end

  defp awips_id(_), do: nil

  defp strip_controls(line) do
    cleaned = for <<byte <- line>>, byte > 31, into: <<>>, do: <<byte>>
    String.trim(cleaned)
  end

  defp invalid_header(line),
    do: {:error, %ParseError{code: :invalid_wmo_header, line: line, message: "invalid WMO header"}}
end
