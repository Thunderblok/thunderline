defmodule Thunderline.Thunderblock.VaultSecurityTest do
  use Thunderline.DataCase, async: false

  import Ash.Query

  alias Thunderline.Thunderblock.Resources.VaultUser
  alias Thunderline.Thunderblock.Resources.VaultUserToken

  @moduletag :vault_security

  describe "VaultUser policy enforcement" do
    test "allows unauthenticated user creation (registration flow)" do
      attrs = %{
        email: "newuser@example.com",
        hashed_password: Bcrypt.hash_pwd_salt("password123"),
        role: :user
      }

      # No actor context - simulating registration
      assert {:ok, user} = Ash.create(VaultUser, attrs)
      assert to_string(user.email) == "newuser@example.com"
    end

    test "allows unauthenticated user reads (for auth preparation)" do
      user = create_test_user()

      # No actor context - simulating login lookup
      query = VaultUser |> Ash.Query.filter(email == ^user.email)
      assert {:ok, [found | _]} = Ash.read(query)
      assert found.id == user.id
    end

    test "denies updates when actor is not the user or admin" do
      user = create_test_user()
      other_user = create_test_user()

      # Attempt to update as different user (not admin)
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.update(user, %{first_name: "Hacked"}, actor: other_user)
    end

    test "allows updates when actor is the user themselves" do
      user = create_test_user()

      # Update as self
      assert {:ok, updated} =
               Ash.update(user, %{first_name: "Updated"}, actor: user)

      assert updated.first_name == "Updated"
    end

    test "allows updates when actor is admin" do
      user = create_test_user()
      admin = create_test_user(role: :admin)

      # Update as admin
      assert {:ok, updated} =
               Ash.update(user, %{first_name: "AdminUpdated"}, actor: admin)

      assert updated.first_name == "AdminUpdated"
    end

    test "denies deletion when actor is not the user or admin" do
      user = create_test_user()
      other_user = create_test_user()

      # Attempt to delete as different user
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.destroy(user, actor: other_user)
    end

    test "allows deletion when actor is the user themselves" do
      user = create_test_user()

      # Delete as self
      assert :ok = Ash.destroy(user, actor: user)

      # Verify deletion
      query = VaultUser |> Ash.Query.filter(id == ^user.id)
      assert {:ok, []} = Ash.read(query)
    end

    test "allows deletion when actor is admin" do
      user = create_test_user()
      admin = create_test_user(role: :admin)

      # Delete as admin
      assert :ok = Ash.destroy(user, actor: admin)

      # Verify deletion
      query = VaultUser |> Ash.Query.filter(id == ^user.id)
      assert {:ok, []} = Ash.read(query)
    end
  end

  describe "VaultUserToken policy enforcement" do
    test "allows unauthenticated token creation (magic link flow)" do
      user = create_test_user()

      attrs = %{
        user_id: user.id,
        context: :magic_link,
        sent_to: user.email
      }

      # No actor context - simulating magic link generation
      assert {:ok, token} = Ash.create(VaultUserToken, attrs, action: :build_email_token)
      assert token.user_id == user.id
      assert token.context == :magic_link
    end

    test "denies token reads for non-owners (without admin)" do
      user = create_test_user()
      other_user = create_test_user()
      token = create_test_token(user)

      # Attempt to read as different user
      query = VaultUserToken |> Ash.Query.filter(id == ^token.id)
      assert {:ok, []} = Ash.read(query, actor: other_user)
    end

    test "allows token reads for owner" do
      user = create_test_user()
      token = create_test_token(user)

      # Read as owner
      query = VaultUserToken |> Ash.Query.filter(id == ^token.id)
      assert {:ok, [found | _]} = Ash.read(query, actor: user)
      assert found.id == token.id
    end

    test "allows token reads for admin" do
      user = create_test_user()
      admin = create_test_user(role: :admin)
      token = create_test_token(user)

      # Read as admin
      query = VaultUserToken |> Ash.Query.filter(id == ^token.id)
      assert {:ok, [found | _]} = Ash.read(query, actor: admin)

      assert found.id == token.id
    end

    test "denies token updates for non-owners (without admin)" do
      user = create_test_user()
      other_user = create_test_user()
      token = create_test_token(user)

      # Attempt to update as different user
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.update(token, %{}, action: :mark_as_used, actor: other_user)
    end

    test "allows token updates for owner" do
      user = create_test_user()
      token = create_test_token(user)

      # Update as owner
      assert {:ok, updated} = Ash.update(token, %{}, action: :mark_as_used, actor: user)
      assert updated.used_at != nil
    end

    test "allows token updates for admin" do
      user = create_test_user()
      admin = create_test_user(role: :admin)
      token = create_test_token(user)

      # Update as admin
      assert {:ok, updated} = Ash.update(token, %{}, action: :mark_as_used, actor: admin)
      assert updated.used_at != nil
    end

    test "denies token deletion for non-owners (without admin)" do
      user = create_test_user()
      other_user = create_test_user()
      token = create_test_token(user)

      # Attempt to delete as different user
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.destroy(token, actor: other_user)
    end

    test "allows token deletion for owner" do
      user = create_test_user()
      token = create_test_token(user)

      # Delete as owner
      assert :ok = Ash.destroy(token, actor: user)

      # Verify deletion
      query = VaultUserToken |> Ash.Query.filter(id == ^token.id)
      assert {:ok, []} = Ash.read(query, actor: user)
    end

    test "allows token deletion for admin" do
      user = create_test_user()
      admin = create_test_user(role: :admin)
      token = create_test_token(user)

      # Delete as admin
      assert :ok = Ash.destroy(token, actor: admin)

      # Verify deletion (read as admin to bypass ownership check)
      query = VaultUserToken |> Ash.Query.filter(id == ^token.id)
      assert {:ok, []} = Ash.read(query, actor: admin)
    end
  end

  describe "saga-coordinated user provisioning security" do
    test "UserProvisioningSaga respects vault policies during provisioning" do
      # TODO: Wire saga test once VaultUser creation via saga is implemented
      # This test will verify that the saga properly coordinates across Gate/Block/Link
      # with actor context flowing correctly
      assert true
    end

    test "vault provisioning fails safely if user creation fails mid-saga" do
      # TODO: Test compensation - if vault provisioning fails, user should be deleted
      assert true
    end
  end

  # Test helpers

  defp create_test_user(overrides \\ []) do
    defaults = %{
      email: "test#{:rand.uniform(999_999)}@example.com",
      hashed_password: Bcrypt.hash_pwd_salt("password123"),
      role: :user
    }

    attrs = Map.merge(defaults, Map.new(overrides))

    {:ok, user} = Ash.create(VaultUser, attrs)
    user
  end

  defp create_test_token(user, opts \\ []) do
    context = Keyword.get(opts, :context, :magic_link)

    attrs = %{
      user_id: user.id,
      context: context,
      sent_to: to_string(user.email)
    }

    {:ok, token} = Ash.create(VaultUserToken, attrs, action: :build_email_token)
    token
  end
end
