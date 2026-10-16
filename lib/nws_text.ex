defmodule NwsText do
  @moduledoc "Pure parser for one decoded NWWS text payload."
  alias NwsText.Model.Narrative
  alias NwsText.{ParseError, Parser}
  alias NwsText.Parser.Sections

  @doc "Parse a complete product using the required UTC reference time (never the wall clock)."
  def parse(raw_text, opts \\ [])

  def parse(raw_text, opts) when is_binary(raw_text) and is_list(opts) do
    reference_time = Keyword.get(opts, :reference_time)

    if match?(%DateTime{time_zone: "Etc/UTC"}, reference_time) do
      Parser.parse(raw_text, reference_time)
    else
      {:error, %ParseError{code: :invalid_reference_time, message: "reference_time must be a UTC DateTime"}}
    end
  end

  def parse(_, _), do: {:error, %ParseError{code: :invalid_input, message: "expected a text product"}}

  @doc "Parse headlines, labeled sections, and impact tags from product text; no WMO header is needed."
  def parse_narrative(text) when is_binary(text) do
    lines = String.split(text, "\n")

    {:ok,
     %Narrative{
       headlines: Parser.Narrative.headlines(lines),
       sections: Sections.parse(text),
       impact_tags: Parser.Narrative.tags(lines)
     }}
  end

  def parse_narrative(_), do: {:error, %ParseError{code: :invalid_input, message: "expected text"}}
end
