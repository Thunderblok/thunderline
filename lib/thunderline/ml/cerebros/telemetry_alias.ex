defmodule Thunderline.ML.Cerebros.Telemetry do
  @moduledoc "Deprecated alias for Thunderline.Thunderbolt.Cerebros.Telemetry"
  @deprecated "Use Thunderline.Thunderbolt.Cerebros.Telemetry instead"
  defdelegate metrics_namespace(), to: Thunderline.Thunderbolt.Cerebros.Telemetry
  defdelegate emit_trial_completed(m), to: Thunderline.Thunderbolt.Cerebros.Telemetry
  defdelegate emit_search_completed(m), to: Thunderline.Thunderbolt.Cerebros.Telemetry
  defdelegate attach_logger(), to: Thunderline.Thunderbolt.Cerebros.Telemetry
end
