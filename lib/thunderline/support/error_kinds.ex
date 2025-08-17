defmodule Thunderline.Support.ErrorKinds do
  @moduledoc """
  DEPRECATED shim. ErrorKinds moved to Thunderline.Thunderflow.Support.ErrorKinds.

  Update references to the new domain-scoped module and then remove this file.
  """
  @deprecated "Use Thunderline.Thunderflow.Support.ErrorKinds instead"

  defdelegate classify(error), to: Thunderline.Thunderflow.Support.ErrorKinds
  defdelegate transient?(reason), to: Thunderline.Thunderflow.Support.ErrorKinds
  defdelegate permanent?(reason), to: Thunderline.Thunderflow.Support.ErrorKinds
end
