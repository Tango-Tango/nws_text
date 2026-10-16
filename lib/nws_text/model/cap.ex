defmodule NwsText.Model.CAP do
  @moduledoc "CAP 1.2 envelope."
  defstruct [:identifier, :sender, :sent_at, :status, :message_type, references: [], infos: []]
end
