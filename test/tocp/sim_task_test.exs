defmodule Thunderline.TOCP.SimTaskTest do
  use ExUnit.Case, async: true
  @moduletag :skip

  @tag :tocp
  test "mix tocp.sim.run writes a JSON report" do
    path = Path.join(System.tmp_dir!(), "tocp_report_#{System.unique_integer([:positive])}.json")
    {output, 0} = System.cmd("mix", ["tocp.sim.run", "--out", path], env: [{"MIX_ENV", "test"}])
    assert File.exists?(path), "report file missing"
    {:ok, json} = File.read(path)
    {:ok, decoded} = Jason.decode(json)
  assert decoded["version"] == 1
  assert decoded["nodes"] == 0
  assert decoded["security"]["sig_fail"] == 0
  assert decoded["pass"]["sybil_swarm"]
    assert output =~ "[TOCP][SIM] Wrote report"
  end
end
