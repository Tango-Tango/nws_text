defmodule NwsText.Parser.VTEC do
  @moduledoc false
  import NimbleParsec

  alias NwsText.Model.VTEC, as: Code
  alias NwsText.Parser.Dates

  upper = [?A..?Z]
  digits = [?0..?9]
  time = ascii_string(digits, 6) |> ignore(string("T")) |> ascii_string(digits, 4) |> ignore(string("Z"))

  code =
    ignore(string("/"))
    |> ascii_string(upper, 1)
    |> ignore(string("."))
    |> ascii_string(upper, 3)
    |> ignore(string("."))
    |> ascii_string([?A..?Z, ?0..?9], 4)
    |> ignore(string("."))
    |> ascii_string(upper, 2)
    |> ignore(string("."))
    |> ascii_string(upper, 1)
    |> ignore(string("."))
    |> ascii_string(digits, 4)
    |> ignore(string("."))
    |> concat(time)
    |> ignore(string("-"))
    |> concat(time)
    |> ignore(string("/"))

  defparsecp(:parse_code, code)
  def starts?(<<"/", status, ?., _::binary>>) when status >= ?A and status <= ?Z, do: true
  def starts?(_), do: false

  def parse(line) do
    with {:ok, [status, action, office, phenomenon, significance, tracking, begin_date, begin_time, end_date, end_time],
          "", _, _, _} <- parse_code(line),
         true <- action in ~w(NEW CON EXT EXA EXB CAN EXP UPG COR ROU),
         true <- significance in ~w(W A Y S F O N),
         {:ok, beginning} <- Dates.vtec_timestamp(begin_date, begin_time),
         {:ok, ending} <- Dates.vtec_timestamp(end_date, end_time) do
      {:ok,
       %Code{
         raw_line: line,
         status: status,
         action: action,
         office: office,
         phenomenon: phenomenon,
         significance: significance,
         event_tracking_number: String.to_integer(tracking),
         begins_at: beginning,
         ends_at: ending
       }}
    else
      _ -> :error
    end
  end
end
