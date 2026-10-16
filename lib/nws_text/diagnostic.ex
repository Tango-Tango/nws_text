defmodule NwsText.Diagnostic do
  @moduledoc "Non-fatal parse diagnostic, with stable code and source line."
  defstruct [:code, :line, :message]
end
