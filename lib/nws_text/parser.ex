defmodule NwsText.Parser do
  @moduledoc false
  alias NwsText.Model.TextProduct
  alias NwsText.Parser.{CAP, Segments, WMO}

  def parse(raw, reference) do
    with {:ok, header} <- WMO.parse(raw, reference),
         {_, xml} = CAP.extract(raw),
         {cap, cap_diagnostics} = CAP.parse(xml, raw),
         {:ok, segments, diagnostics} <- Segments.parse(raw, header.wmo_issued_at, xml, header.issuing_center) do
      {:ok,
       struct(
         TextProduct,
         Map.merge(header, %{
           raw_text: raw,
           reference_time: reference,
           cap: cap,
           segments: segments,
           diagnostics: cap_diagnostics ++ diagnostics
         })
       )}
    end
  end
end
