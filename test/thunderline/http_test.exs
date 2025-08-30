defmodule Thunderline.HTTPTest do
  use ExUnit.Case

  @tag :external
  @tag :skip
  test "GET JSON happy path (skipped by default)" do
    # Only run when network allowed; set MIX_ENV or remove :skip
    url = System.get_env("HTTP_TEST_URL") || "https://httpbin.org/json"
    assert {:ok, %Req.Response{status: 200}} = Thunderline.HTTP.get(url)
  end
end
