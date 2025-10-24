defmodule Mix.Tasks.TestMessageFlow do
  @moduledoc """
  Run the message flow integration test
  """
  use Mix.Task

  @shortdoc "Tests end-to-end message flow"

  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")

    # Load and run the test
    Code.eval_file("test_message_flow.exs")
  end
end
