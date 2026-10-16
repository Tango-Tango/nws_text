defmodule NwsText.Parser.CAP do
  @moduledoc false
  alias NwsText.Diagnostic
  alias NwsText.Model.CAP
  alias NwsText.Model.CAP.{Area, Info}
  alias NwsText.Parser.CAP.Boundary

  @max_xml_bytes 1_000_000
  @namespace "urn:oasis:names:tc:emergency:cap:1.2"

  defdelegate extract(text), to: Boundary

  def parse(nil, _text), do: {nil, []}

  def parse(xml, text) do
    line =
      case :binary.match(text, xml) do
        {offset, _} -> text |> binary_part(0, offset) |> String.split("\n") |> length()
        :nomatch -> 1
      end

    {cap, diagnostics} =
      cond do
        byte_size(xml) > @max_xml_bytes -> diagnostic(:cap_too_large)
        Regex.match?(~r/<!\s*(?:DOCTYPE|ENTITY)\b/i, text) -> diagnostic(:cap_unsafe_xml)
        true -> decode(xml)
      end

    {cap, Enum.map(diagnostics, fn %Diagnostic{} = note -> %{note | line: line} end)}
  end

  defp decode(xml) do
    with {:ok, {name, attrs, _} = root} <- Saxy.SimpleForm.parse_string(xml, expand_entity: :skip),
         scope = namespace_scope(%{}, attrs),
         true <- cap_element?(name, "alert", scope) do
      build(root, scope)
    else
      _ -> diagnostic(:invalid_cap)
    end
  end

  defp build(root, scope) do
    case DateTime.from_iso8601(value(root, "sent", scope) || "") do
      {:ok, sent_at, _} ->
        {%CAP{
           identifier: value(root, "identifier", scope),
           sender: value(root, "sender", scope),
           sent_at: sent_at,
           status: value(root, "status", scope),
           message_type: value(root, "msgType", scope),
           references: String.split(value(root, "references", scope) || ""),
           infos: Enum.map(children(root, "info", scope), fn {node, child_scope} -> info(node, child_scope) end)
         }, []}

      _ ->
        diagnostic(:invalid_cap_timestamp)
    end
  end

  defp info(node, scope) do
    %Info{
      event: value(node, "event", scope),
      event_codes:
        Enum.map(children(node, "eventCode", scope), fn {child, child_scope} -> code(child, child_scope) end),
      areas: Enum.map(children(node, "area", scope), fn {child, child_scope} -> area(child, child_scope) end)
    }
  end

  defp area(node, scope) do
    %Area{
      description: value(node, "areaDesc", scope),
      geocodes: Enum.map(children(node, "geocode", scope), fn {child, child_scope} -> code(child, child_scope) end)
    }
  end

  defp code(node, scope), do: %{name: value(node, "valueName", scope), value: value(node, "value", scope)}

  defp value(node, tag, scope) do
    case children(node, tag, scope) do
      [{{_, _, content}, _} | _] ->
        content |> Enum.filter(&is_binary/1) |> Enum.join() |> String.trim()

      _ ->
        nil
    end
  end

  defp children({_, _, content}, tag, scope) do
    Enum.flat_map(content, fn
      {name, attrs, _} = node ->
        child_scope = namespace_scope(scope, attrs)
        if cap_element?(name, tag, child_scope), do: [{node, child_scope}], else: []

      _ ->
        []
    end)
  end

  defp namespace_scope(scope, attrs) do
    Enum.reduce(attrs, scope, fn
      {"xmlns", uri}, scope -> Map.put(scope, "", uri)
      {"xmlns:" <> prefix, uri}, scope -> Map.put(scope, prefix, uri)
      _, scope -> scope
    end)
  end

  defp cap_element?(name, tag, scope) do
    case String.split(name, ":", parts: 2) do
      [^tag] -> Map.get(scope, "") == @namespace
      [prefix, ^tag] -> Map.get(scope, prefix) == @namespace
      _ -> false
    end
  end

  defp diagnostic(code), do: {nil, [%Diagnostic{code: code, line: nil, message: Atom.to_string(code)}]}
end
