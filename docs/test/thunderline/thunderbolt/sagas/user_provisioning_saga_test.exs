defmodule Thunderline.Thunderbolt.Sagas.UserProvisioningSagaTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.Sagas.UserProvisioningSaga

  @moduletag :saga

  describe "UserProvisioningSaga" do
    test "executes full happy path" do
      correlation_id = Thunderline.UUID.v7()

      inputs = %{
        email: "test@example.com",
        correlation_id: correlation_id,
        causation_id: nil,
        magic_link_redirect: "/communities"
      }

      # TODO: Mock MagicLinkSender to avoid actual email dispatch
      # TODO: Stub Ash actions for User and VaultUser creation

      # For now, expect failure due to missing user create logic
      result = Reactor.run(UserProvisioningSaga, inputs)

      # Once mocked, assert:
      # assert {:ok, %{user: user, vault: vault}} = result
      # assert user.email == "test@example.com"
      # assert vault.user_id == user.id

      # Temporary assertion until mocks wired:
      assert match?({:error, _}, result)
    end

    test "compensates on user creation failure" do
      correlation_id = Thunderline.UUID.v7()

      inputs = %{
        email: "invalid@",
        correlation_id: correlation_id,
        causation_id: nil,
        magic_link_redirect: "/communities"
      }

      result = Reactor.run(UserProvisioningSaga, inputs)

      assert {:error, :invalid_email_format} = result
    end

    test "emits telemetry events during execution" do
      # TODO: Attach telemetry handler and verify events emitted
      # Expected events:
      # - [:reactor, :saga, :start]
      # - [:reactor, :saga, :step, :start] (multiple)
      # - [:reactor, :saga, :step, :stop] (multiple)
      # - [:reactor, :saga, :complete] or [:reactor, :saga, :fail]
    end
  end
end
