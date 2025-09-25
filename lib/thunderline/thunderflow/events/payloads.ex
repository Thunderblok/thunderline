defmodule Thunderline.Thunderflow.Events.Payloads.MessageSend do
  @enforce_keys [:message_id, :channel_id, :actor_id, :text]
  defstruct [:message_id, :channel_id, :actor_id, :text]
end

defmodule Thunderline.Thunderflow.Events.Payloads.MlRunStarted do
  @enforce_keys [:run_id, :trial_id, :model, :dataset_ref]
  defstruct [:run_id, :trial_id, :model, :dataset_ref]
end
