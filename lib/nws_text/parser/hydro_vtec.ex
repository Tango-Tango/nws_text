defmodule NwsText.Parser.HydroVTEC do
  @moduledoc false
  import NimbleParsec

  alias NwsText.Model.HydrologicVTEC
  alias NwsText.Parser.Dates

  digits = [?0..?9]
  timestamp = ascii_string(digits, 6) |> ignore(string("T")) |> ascii_string(digits, 4) |> ignore(string("Z"))

  code =
    ignore(string("/"))
    |> ascii_string([?A..?Z, ?0..?9], 5)
    |> ignore(string("."))
    |> ascii_string([?N, ?0..?3, ?U], 1)
    |> ignore(string("."))
    |> ascii_string([?A..?Z], 2)
    |> ignore(string("."))
    |> concat(timestamp)
    |> ignore(string("."))
    |> concat(timestamp)
    |> ignore(string("."))
    |> concat(timestamp)
    |> ignore(string("."))
    |> ascii_string([?A..?Z], 2)
    |> ignore(string("/"))

  defparsecp(:parse_code, code)
  defparsecp(:parse_prefix, ignore(string("/")) |> ascii_string([?A..?Z, ?0..?9], 5) |> ignore(string(".")))

  def starts?(line), do: match?({:ok, _, _, _, _, _}, parse_prefix(line))

  def parse(line) do
    with {:ok, [nwsli, severity, cause, bd, bt, cd, ct, ed, et, record], "", _, _, _} <- parse_code(line),
         {:ok, begins_at} <- Dates.vtec_timestamp(bd, bt),
         {:ok, crests_at} <- Dates.vtec_timestamp(cd, ct),
         {:ok, ends_at} <- Dates.vtec_timestamp(ed, et) do
      {:ok,
       %HydrologicVTEC{
         raw_line: line,
         nwsli: nwsli,
         severity: severity,
         cause: cause,
         begins_at: begins_at,
         crests_at: crests_at,
         ends_at: ends_at,
         record: record
       }}
    else
      _ -> :error
    end
  end
end
