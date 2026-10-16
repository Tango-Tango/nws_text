defmodule NwsText.Model.Narrative do
  @moduledoc "Narrative fields from NWS product text; sections are literal `%{label, text}` maps in source order."
  defstruct headlines: [], sections: [], impact_tags: []
end
