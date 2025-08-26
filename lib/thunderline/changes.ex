defmodule Thunderline.Changes.PruneWorkingMemory do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Changes.PruneWorkingMemory"
  @deprecated "Use Thunderline.Thunderbolt.Changes.PruneWorkingMemory"
  def change(changeset, opts, ctx), do: Thunderline.Thunderbolt.Changes.PruneWorkingMemory.change(changeset, opts, ctx)
end

defmodule Thunderline.Changes.RunNodeLogic do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Changes.RunNodeLogic"
  @deprecated "Use Thunderline.Thunderbolt.Changes.RunNodeLogic"
  def change(cs, opts, ctx), do: Thunderline.Thunderbolt.Changes.RunNodeLogic.change(cs, opts, ctx)
end

defmodule Thunderline.Changes.ApplyTickResult do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Changes.ApplyTickResult"
  @deprecated "Use Thunderline.Thunderbolt.Changes.ApplyTickResult"
  def change(cs, opts, ctx), do: Thunderline.Thunderbolt.Changes.ApplyTickResult.change(cs, opts, ctx)
end

defmodule Thunderline.Changes.PutInMap do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Changes.PutInMap"
  @deprecated "Use Thunderline.Thunderbolt.Changes.PutInMap"
  def change(cs, opts, ctx), do: Thunderline.Thunderbolt.Changes.PutInMap.change(cs, opts, ctx)
end

defmodule Thunderline.Changes.DeleteInMap do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Changes.DeleteInMap"
  @deprecated "Use Thunderline.Thunderbolt.Changes.DeleteInMap"
  def change(cs, opts, ctx), do: Thunderline.Thunderbolt.Changes.DeleteInMap.change(cs, opts, ctx)
end
