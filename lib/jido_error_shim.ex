# Shim module for compatibility with ash_jido expecting %Jido.Error{}.
# The upstream Jido ecosystem (at least the versions currently fetched) does not
# define a top-level Jido.Error struct anymore (error handling lives under
# Jido.Action.Error and Splode). To unblock compilation of ash_jido's mapper
# (which constructs a %Jido.Error{} without raising), we provide a minimal
# struct here. If/when upstream reintroduces or renames the module, this shim
# will no longer be needed.
#
# Safe because:
#  * Only ash_jido Mapper references %Jido.Error{...} in this codebase.
#  * It is used as a plain data container, not an exception being raised.
#  * Fields (type, message, details) match what Mapper assembles.
#
# Guarded so we don't redefine if an upstream implementation appears later.
unless Code.ensure_loaded?(Jido.Error) do
  defmodule Jido.Error do
    @moduledoc """
    Compatibility struct expected by ash_jido for wrapping Ash errors.

    This is a local shim. Upstream newer Jido libs have migrated error handling
    to Jido.Action.Error.* (Splode-based). If an official Jido.Error module is
    added upstream, remove this file to avoid conflicts.
    """
    @enforce_keys [:type, :message]
    defstruct [:type, :message, details: %{}]

    @type t :: %__MODULE__{type: atom(), message: String.t(), details: map()}
  end
end
