defmodule NwsText.Parser.Sections do
  @moduledoc false
  import NimbleParsec

  # Labeled narrative sections, such as `* WHAT...` and `IMPACT...`.
  # Unknown lines are skipped, so unfamiliar layouts never fail the parse.
  spaces = ascii_string([?\s, ?\t], min: 0)
  line = ascii_string([not: ?\n], min: 0) |> ignore(string("\n"))
  blank = spaces |> string("\n")

  actions_label = string("PRECAUTIONARY/PREPAREDNESS ACTIONS")

  paragraph_label =
    choice([
      string("ADDITIONAL DETAILS"),
      replace(string("IMPACTS"), "IMPACT"),
      string("IMPACT"),
      string("HAZARD"),
      string("SOURCE"),
      string("WHAT"),
      string("WHERE"),
      string("WHEN")
    ])

  header = fn label -> ignore(spaces) |> ignore(optional(string("* "))) |> concat(label) |> ignore(string("...")) end
  any_header = header.(choice([actions_label, paragraph_label]))
  delimiter = spaces |> choice([string("&&"), string("$$")]) |> concat(blank)

  date_line =
    spaces
    |> ascii_string([?0..?9], min: 3, max: 4)
    |> string(" ")
    |> choice([string("AM"), string("PM"), string("am"), string("pm")])
    |> string(" ")
    |> ascii_string([?A..?Z], min: 3, max: 4)
    |> string(" ")
    |> ascii_string([?A..?Z, ?a..?z], 3)
    |> string(" ")
    |> ascii_string([?A..?Z, ?a..?z], 3)
    |> string(" ")
    |> ascii_string([?0..?9], min: 1, max: 2)
    |> string(" ")
    |> ascii_string([?0..?9], 4)

  # Paragraph sections continue past a blank line only into indented text, such as sub-bullets.
  paragraph_line = lookahead_not(choice([any_header, string("* "), delimiter, blank])) |> concat(line)

  indented_gap =
    times(replace(blank, ""), min: 1)
    |> lookahead_not(any_header)
    |> lookahead(ascii_char([?\s, ?\t]))

  # A bulleted section also keeps unindented paragraphs that sit between it and the next bullet,
  # such as a second flood stage in `* IMPACTS...`. Text after the last bullet is left out.
  loose_line =
    lookahead_not(choice([any_header, string("* "), delimiter, blank, date_line, spaces |> string("...")]))
    |> concat(line)

  loose_paragraphs = times(loose_line, min: 1) |> repeat(times(blank, min: 1) |> times(loose_line, min: 1))
  bullet_gap = times(replace(blank, ""), min: 1) |> lookahead(loose_paragraphs |> repeat(blank) |> string("* "))

  bullet_header = ignore(spaces) |> ignore(string("* ")) |> concat(paragraph_label) |> ignore(string("..."))
  bullet = bullet_header |> concat(line) |> repeat(choice([paragraph_line, indented_gap, bullet_gap]))
  paragraph = header.(paragraph_label) |> concat(line) |> repeat(choice([paragraph_line, indented_gap]))

  # Actions span paragraphs. They end at a delimiter, a new label or bullet, a date line, or a headline.
  actions_stop = choice([any_header, string("* "), delimiter, date_line, spaces |> string("...")])
  actions = header.(actions_label) |> concat(line) |> repeat(lookahead_not(actions_stop) |> concat(line))

  section = choice([actions, bullet, paragraph]) |> reduce({__MODULE__, :section, []})

  defparsecp(:document, repeat(choice([section, ignore(line)])) |> eos())

  def parse(text) do
    text = String.replace(text, ~r/\r+\n/, "\n")
    text = if String.ends_with?(text, "\n"), do: text, else: text <> "\n"

    case document(text) do
      {:ok, sections, "", _, _, _} -> Enum.reject(sections, &is_nil/1)
      _ -> []
    end
  end

  @doc false
  def section([label | lines]) do
    case lines |> Enum.map_join("\n", &String.trim/1) |> String.trim() do
      "" -> nil
      text -> %{label: label, text: text}
    end
  end
end
