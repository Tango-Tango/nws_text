defmodule NwsText.Model.Segment do
  @moduledoc "An ordered portion of a text product; raw text is retained unchanged."
  defstruct [
    :index,
    :raw_text,
    :ugc_expires_at,
    :polygon,
    ugc_codes: [],
    vtec_codes: [],
    hydrologic_vtec: [],
    motions: [],
    headlines: [],
    impact_tags: []
  ]
end
