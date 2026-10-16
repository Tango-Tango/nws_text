defmodule NwsText.Parser.UGC do
  @moduledoc false
  import NimbleParsec

  alias NwsText.Model.UGC, as: Code
  alias NwsText.Parser.Dates

  prefix = ascii_string([?A..?Z], 2) |> choice([string("C"), string("Z")])
  number = ascii_string([?0..?9], 3)
  token = optional(prefix) |> concat(number) |> optional(ignore(string(">")) |> concat(number))
  defparsecp(:parse_token, token)
  defparsecp(:parse_expiration, ascii_string([?0..?9], 6))
  defparsecp(:parse_start, prefix |> concat(number) |> ignore(choice([string("-"), string(">")])))

  fragment_start =
    optional(prefix)
    |> concat(number)
    |> choice([string("-"), string(">"), number |> ignore(string("-"))])

  defparsecp(:parse_fragment_start, fragment_start)
  defparsecp(:parse_fragment_chars, ascii_string([?A..?Z, ?0..?9, ?-, ?>], min: 1))

  def start?(line) do
    match?({:ok, _, _, _, _, _}, parse_start(line))
  end

  def parse(line, reference) do
    case Enum.reverse(String.split(line, "-")) do
      ["", expiration | reversed] when reversed != [] ->
        with {:ok, [_], "", _, _, _} <- parse_expiration(expiration),
             {:ok, date} <- Dates.resolve_day(expiration, reference),
             {:ok, codes} <- expand(Enum.reverse(reversed)) do
          {:ok, codes, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp expand(parts) do
    Enum.reduce_while(parts, {:ok, [], nil}, fn part, {:ok, acc, prefix} ->
      case parse_token(part) do
        {:ok, [state, type, first, last], "", _, _, _} -> append(acc, state <> type, first, last)
        {:ok, [state, type, first], "", _, _, _} -> append(acc, state <> type, first, first)
        {:ok, [first, last], "", _, _, _} -> append(acc, prefix, first, last)
        {:ok, [first], "", _, _, _} -> append(acc, prefix, first, first)
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, codes, _} -> {:ok, codes}
      _ -> :error
    end
  end

  defp append(acc, prefix, first, last) when is_binary(prefix) and byte_size(prefix) == 3 do
    from = String.to_integer(first)
    to = String.to_integer(last)

    if to >= from do
      codes =
        Enum.map(from..to, fn number ->
          %Code{
            raw_code: prefix <> String.pad_leading(Integer.to_string(number), 3, "0"),
            state: binary_part(prefix, 0, 2),
            type: if(String.ends_with?(prefix, "C"), do: :county, else: :zone),
            number: number
          }
        end)

      {:cont, {:ok, acc ++ codes, prefix}}
    else
      {:halt, :error}
    end
  end

  defp append(_, _, _, _), do: {:halt, :error}

  # Join plausible UGC continuations, preserving the original line number.
  def collapse_lines(lines), do: collapse_lines(Enum.with_index(lines, 1), [])
  defp collapse_lines([], acc), do: Enum.reverse(acc)

  defp collapse_lines([{line, number} | rest], acc) do
    if start?(String.trim(line)) and not expires?(line) do
      case continuation(rest, String.trim(line)) do
        {:ok, joined, remaining} -> collapse_lines(remaining, [{joined, number} | acc])
        :error -> collapse_lines(rest, [{line, number} | acc])
      end
    else
      collapse_lines(rest, [{line, number} | acc])
    end
  end

  defp continuation([{line, _} | rest], joined) do
    fragment = String.trim(line)

    if match?({:ok, _, _, _, _, _}, parse_fragment_start(fragment)) and
         match?({:ok, [_], "", _, _, _}, parse_fragment_chars(fragment)) and
         String.ends_with?(fragment, "-") do
      joined = joined <> fragment
      if expires?(joined), do: {:ok, joined, rest}, else: continuation(rest, joined)
    else
      :error
    end
  end

  defp continuation([], _), do: :error

  defp expires?(line) when byte_size(line) >= 8 do
    case binary_part(line, byte_size(line) - 8, 8) do
      <<"-", expiration::binary-size(6), "-">> -> match?({:ok, [_], "", _, _, _}, parse_expiration(expiration))
      _ -> false
    end
  end

  defp expires?(_), do: false
end
