defmodule NwsText.Parser.Segments do
  @moduledoc false

  alias NwsText.{Diagnostic, ParseError}
  alias NwsText.Model.Segment
  alias NwsText.Parser.{HydroVTEC, Motion, Narrative, Polygon, UGC, VTEC}

  def parse(text, reference, xml, center) do
    coded_text = mask_cap(text, xml)

    {parts, offset, line} =
      ~r/(?<=\$\$)\r*\n/
      |> Regex.scan(coded_text, return: :index)
      |> Enum.reduce({[], 0, 1}, fn [{position, separator_size}], {parts, offset, line} ->
        size = position - offset
        raw = binary_part(text, offset, size)
        coded = binary_part(coded_text, offset, size)
        {[{raw, coded, line} | parts], position + separator_size, line + length(:binary.matches(raw, "\n")) + 1}
      end)

    size = byte_size(text) - offset

    chunks =
      [{binary_part(text, offset, size), binary_part(coded_text, offset, size), line} | parts]
      |> Enum.reverse()
      |> Enum.reject(fn {raw, _, _} -> String.trim(raw) == "" end)

    Enum.reduce_while(Enum.with_index(chunks), {:ok, [], []}, fn {{raw, coded, start}, index},
                                                                 {:ok, acc, diagnostics} ->
      case segment(raw, coded, index, reference, start, center) do
        {:ok, part, notes} -> {:cont, {:ok, [part | acc], diagnostics ++ notes}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts, diagnostics} -> {:ok, Enum.reverse(parts), diagnostics}
      error -> error
    end
  end

  defp mask_cap(text, nil), do: text

  defp mask_cap(text, xml) do
    mask = for <<byte <- xml>>, into: "", do: if(byte == ?\n, do: "\n", else: " ")
    String.replace(text, xml, mask, global: false)
  end

  defp segment(chunk, coded_text, index, reference, start, center) do
    lines = String.split(coded_text, "\n")

    Enum.reduce_while(UGC.collapse_lines(lines), {:ok, [], [], nil, nil, []}, fn {line, number}, state ->
      parse_line(String.trim(line), number, lines, reference, center, state)
    end)
    |> case do
      {:ok, ugcs, vtecs, expiry, polygon, notes} ->
        {hydrologic, motions, extra_notes} = parse_extras(lines, expiry, center)

        {:ok,
         %Segment{
           index: index,
           raw_text: chunk,
           ugc_codes: ugcs,
           ugc_expires_at: expiry,
           vtec_codes: vtecs,
           hydrologic_vtec: hydrologic,
           motions: motions,
           headlines: Narrative.headlines(lines),
           impact_tags: Narrative.tags(lines),
           polygon: polygon
         }, offset_lines(notes ++ extra_notes, start)}

      {:error, %ParseError{} = error} ->
        {:error, %{error | line: error.line + start - 1}}
    end
  end

  defp offset_lines(notes, start), do: Enum.map(notes, &%{&1 | line: &1.line + start - 1})

  defp parse_extras(lines, expiry, center) do
    {hydrologic, motions, notes} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], []}, fn {raw, number}, acc -> extra(String.trim(raw), number, expiry, center, acc) end)

    {Enum.reverse(hydrologic), Enum.reverse(motions), Enum.reverse(notes)}
  end

  defp extra(line, number, expiry, center, {hydrologic, motions, notes} = acc) do
    cond do
      HydroVTEC.starts?(line) ->
        case HydroVTEC.parse(line) do
          {:ok, code} -> {[code | hydrologic], motions, notes}
          :error -> {hydrologic, motions, [diagnostic(:invalid_hydrologic_vtec, number) | notes]}
        end

      String.starts_with?(line, "TIME...MOT...LOC") ->
        case Motion.parse(line, expiry, center) do
          {:ok, motion} -> {hydrologic, [motion | motions], notes}
          :error -> {hydrologic, motions, [diagnostic(:invalid_motion, number) | notes]}
        end

      true ->
        acc
    end
  end

  defp diagnostic(code, number),
    do: %Diagnostic{code: code, line: number, message: Atom.to_string(code)}

  defp parse_line(line, number, lines, reference, center, state) do
    cond do
      UGC.start?(line) -> parse_ugc(line, number, reference, state)
      VTEC.starts?(line) -> parse_vtec(line, number, state)
      String.starts_with?(line, "LAT...LON") -> parse_polygon(lines, number, center, state)
      true -> {:cont, state}
    end
  end

  defp parse_ugc(line, number, reference, {:ok, ugcs, vtecs, _, polygon, notes}) do
    case UGC.parse(line, reference) do
      {:ok, codes, date} -> {:cont, {:ok, ugcs ++ codes, vtecs, date, polygon, notes}}
      :error -> {:halt, {:error, %ParseError{code: :invalid_ugc, line: number, message: "invalid UGC coding"}}}
    end
  end

  defp parse_vtec(line, number, {:ok, ugcs, vtecs, expiry, polygon, notes}) do
    case VTEC.parse(line) do
      {:ok, code} -> {:cont, {:ok, ugcs, vtecs ++ [code], expiry, polygon, notes}}
      :error -> {:halt, {:error, %ParseError{code: :invalid_vtec, line: number, message: "invalid VTEC coding"}}}
    end
  end

  defp parse_polygon(lines, number, center, {:ok, ugcs, vtecs, expiry, _, notes}) do
    case Polygon.parse(lines, number, center) do
      {:ok, geometry} ->
        {:cont, {:ok, ugcs, vtecs, expiry, geometry, notes}}

      :error ->
        note = %Diagnostic{code: :invalid_polygon, line: number, message: "invalid LAT...LON"}
        {:cont, {:ok, ugcs, vtecs, expiry, nil, notes ++ [note]}}
    end
  end
end
