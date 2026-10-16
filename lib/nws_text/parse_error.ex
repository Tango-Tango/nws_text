defmodule NwsText.ParseError do
  @moduledoc "Fatal parse error, with stable code and source line."
  defexception [:code, :line, :message]
end
