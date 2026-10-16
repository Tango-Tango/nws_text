defmodule NwsText.Model.TextProduct do
  @moduledoc "Parsed NWWS text and CAP fields."
  defstruct [
    :raw_text,
    :reference_time,
    :wmo_id,
    :issuing_center,
    :wmo_date_group,
    :correction_code,
    :awips_id,
    :wmo_issued_at,
    :issued_at,
    :cap,
    segments: [],
    diagnostics: []
  ]
end
