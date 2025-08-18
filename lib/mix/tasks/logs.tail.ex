defmodule Mix.Tasks.Logs.Tail do
  @shortdoc "Print recent in-memory development logs"
  @moduledoc """
  Reads from the in-memory ring buffer (Thunderline.LogBuffer) and prints last N entries.

  Options:
    --n NUM   number of entries (default 200)
  """
  use Mix.Task

  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: [n: :integer])
    n = opts[:n] || 200
    Thunderline.LogBuffer.recent(n)
    |> Enum.each(fn {lvl, md, msg} ->
      io = IO.iodata_to_binary(msg)
      meta = Enum.map(md, fn {k,v} -> "#{k}=#{v}" end) |> Enum.join(" ")
      IO.puts("[#{lvl}] #{meta} #{io}")
    end)
  end
end
