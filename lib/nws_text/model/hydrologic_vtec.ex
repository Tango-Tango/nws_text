defmodule NwsText.Model.HydrologicVTEC do
  @moduledoc "Decoded hydrologic VTEC fields; no alert action is inferred."
  defstruct [:raw_line, :nwsli, :severity, :cause, :begins_at, :crests_at, :ends_at, :record]
end
