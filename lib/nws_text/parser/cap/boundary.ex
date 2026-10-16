defmodule NwsText.Parser.CAP.Boundary do
  @moduledoc false
  alias NwsText.Parser.CAP.Boundary.Handler

  @max_xml_bytes 1_000_000
  @namespace "urn:oasis:names:tc:emergency:cap:1.2"

  def extract(text) do
    case locate(text, text, 0) do
      nil ->
        {text, nil}

      {start, tail} ->
        length = document_length(tail)
        xml = binary_part(tail, 0, length)
        remaining = binary_part(text, 0, start) <> binary_part(tail, length, byte_size(tail) - length)
        {remaining, xml}
    end
  end

  # Ignore alert lookalikes in prose, comments, CDATA, and quoted attributes.
  defp locate(<<>>, _, _), do: nil

  defp locate(text, source, offset) do
    case :binary.match(text, "<") do
      {position, 1} ->
        candidate = binary_part(text, position, byte_size(text) - position)
        start = offset + position

        cond do
          String.starts_with?(candidate, "<!--") -> skip(candidate, "-->", 4, source, start)
          String.starts_with?(candidate, "<![CDATA[") -> skip(candidate, "]]>", 9, source, start)
          String.starts_with?(candidate, "<?") -> skip(candidate, "?>", 2, source, start)
          not tag_start?(candidate) -> locate(binary_part(candidate, 1, byte_size(candidate) - 1), source, start + 1)
          true -> locate_tag(candidate, source, start)
        end

      :nomatch ->
        nil
    end
  end

  defp skip(candidate, marker, opening_length, source, start) do
    tail = binary_part(candidate, opening_length, byte_size(candidate) - opening_length)

    case :binary.match(tail, marker) do
      {position, length} ->
        consumed = opening_length + position + length
        locate(binary_part(candidate, consumed, byte_size(candidate) - consumed), source, start + consumed)

      :nomatch ->
        nil
    end
  end

  defp tag_start?(<<"<", byte, _::binary>>) when byte in ?A..?Z or byte in ?a..?z or byte in [?_, ?:], do: true
  defp tag_start?(_), do: false

  defp locate_tag(candidate, source, start) do
    {tag, rest} = take_tag(candidate)

    if alert_tag?(tag) and (line_start?(source, start) or String.contains?(tag, @namespace)) do
      {start, candidate}
    else
      locate(rest, source, start + byte_size(tag))
    end
  end

  defp take_tag(text), do: take_tag(text, text, nil, 0)
  defp take_tag(<<>>, original, _, _), do: {original, <<>>}

  defp take_tag(<<byte, rest::binary>>, original, quote, count) do
    cond do
      byte == quote -> take_tag(rest, original, nil, count + 1)
      quote != nil -> take_tag(rest, original, quote, count + 1)
      byte in [?', ?\"] -> take_tag(rest, original, byte, count + 1)
      byte == ?> -> {binary_part(original, 0, count + 1), rest}
      true -> take_tag(rest, original, nil, count + 1)
    end
  end

  defp alert_tag?(<<"<", rest::binary>>) do
    case :binary.match(rest, [" ", "\t", "\r", "\n", "/", ">"]) do
      {length, _} ->
        case String.split(binary_part(rest, 0, length), ":") do
          ["alert"] -> true
          [prefix, "alert"] when prefix != "" -> true
          _ -> false
        end

      :nomatch ->
        false
    end
  end

  defp alert_tag?(_), do: false

  defp line_start?(source, start) do
    line = source |> binary_part(0, start) |> String.split("\n") |> List.last()
    String.trim(line) == ""
  end

  # Incomplete XML consumes the tail rather than selecting a later document.
  defp document_length(tail) do
    input = binary_part(tail, 0, min(byte_size(tail), @max_xml_bytes + 1))

    case Saxy.parse_string(input, Handler, 0, expand_entity: :skip) do
      {:halt, 0, rest} -> byte_size(input) - byte_size(rest)
      _ -> byte_size(tail)
    end
  end
end
