defmodule NwsText.Model.VTEC do
  @moduledoc "Parsed VTEC code; no event identity is inferred."
  defstruct [
    :raw_line,
    :status,
    :action,
    :office,
    :phenomenon,
    :significance,
    :event_tracking_number,
    :begins_at,
    :ends_at
  ]
end
