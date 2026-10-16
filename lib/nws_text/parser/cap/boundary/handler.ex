defmodule NwsText.Parser.CAP.Boundary.Handler do
  @moduledoc false
  @behaviour Saxy.Handler

  @impl Saxy.Handler
  def handle_event(:start_element, _, depth), do: {:ok, depth + 1}
  def handle_event(:end_element, _, 1), do: {:halt, 0}
  def handle_event(:end_element, _, depth), do: {:ok, depth - 1}
  def handle_event(_, _, depth), do: {:ok, depth}
end
