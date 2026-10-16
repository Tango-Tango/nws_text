defmodule NwsText.Explore do
  @moduledoc false

  @fixtures Path.expand("../fixtures/pyiem", __DIR__)

  def fixture(path \\ "SVR/SVRPSR.txt") do
    cases = @fixtures |> Path.join("expected.json") |> File.read!() |> Jason.decode!()
    expected = Enum.find(cases, &(&1["path"] == path)) || raise ArgumentError, "unknown pyIEM fixture: #{path}"
    {:ok, reference_time, 0} = DateTime.from_iso8601(expected["reference_time"])

    @fixtures
    |> Path.join(path)
    |> File.read!()
    |> NwsText.parse(reference_time: reference_time)
  end
end
