defmodule NwsText.Model.Motion do
  @moduledoc "TIME...MOT...LOC fields; valid_at is nil without UGC expiration."
  defstruct [:raw_line, :time, :valid_at, :direction_degrees, :speed_knots, points: []]
end
