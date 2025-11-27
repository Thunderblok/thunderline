defmodule Thunderline.Thunderflow.ErrorClassifierTest do
  @moduledoc """
  Tests for the ErrorClassifier module (HC-09).
  """
  use ExUnit.Case, async: true

  alias Thunderline.Thunderflow.ErrorClassifier
  alias Thunderline.Thunderflow.ErrorClass

  describe "classify/2 - Ecto validation errors" do
    test "classifies invalid changeset as user validation error" do
      changeset = %Ecto.Changeset{valid?: false, errors: [email: {"is invalid", []}]}

      result = ErrorClassifier.classify({:error, changeset})

      assert %ErrorClass{
               origin: :user,
               class: :validation,
               severity: :warn,
               visibility: :user_safe,
               raw: ^changeset
             } = result
    end

    test "classifies bare invalid changeset" do
      changeset = %Ecto.Changeset{valid?: false}

      result = ErrorClassifier.classify(changeset)

      assert result.origin == :user
      assert result.class == :validation
      assert result.visibility == :user_safe
    end
  end

  describe "classify/2 - timeout errors" do
    test "classifies :timeout atom" do
      result = ErrorClassifier.classify(:timeout)

      assert result.class == :timeout
      assert result.severity == :error
    end

    test "classifies {:error, :timeout} tuple" do
      result = ErrorClassifier.classify({:error, :timeout})

      assert result.class == :timeout
    end

    test "uses external origin when external_service in context" do
      result = ErrorClassifier.classify(:timeout, %{external_service: :smtp})

      assert result.origin == :external
      assert result.class == :timeout
    end

    test "classifies RuntimeError with timeout message" do
      error = %RuntimeError{message: "operation timeout after 5000ms"}

      result = ErrorClassifier.classify(error)

      assert result.class == :timeout
      assert result.origin == :system
    end
  end

  describe "classify/2 - security errors" do
    test "classifies unauthorized error" do
      result = ErrorClassifier.classify({:error, :unauthorized})

      assert result.origin == :user
      assert result.class == :security
      assert result.visibility == :user_safe
    end

    test "classifies forbidden error" do
      result = ErrorClassifier.classify({:error, :forbidden})

      assert result.class == :security
    end

    test "classifies unauthenticated error" do
      result = ErrorClassifier.classify({:error, :unauthenticated})

      assert result.class == :security
    end
  end

  describe "classify/2 - dependency errors" do
    test "classifies bypass dependency_unavailable" do
      result = ErrorClassifier.classify({:bypass, :dependency_unavailable})

      assert result.origin == :infrastructure
      assert result.class == :dependency
    end

    test "classifies error dependency_unavailable" do
      result = ErrorClassifier.classify({:error, :dependency_unavailable})

      assert result.origin == :infrastructure
      assert result.class == :dependency
    end
  end

  describe "classify/2 - HTTP status errors" do
    test "classifies 4xx as permanent user error" do
      result = ErrorClassifier.classify({:error, {:http_status, 404}})

      assert result.origin == :user
      assert result.class == :permanent
    end

    test "classifies 5xx as transient external error" do
      result = ErrorClassifier.classify({:error, {:http_status, 503}})

      assert result.origin == :external
      assert result.class == :transient
    end
  end

  describe "classify/2 - unknown errors" do
    test "classifies unknown struct as transient" do
      result = ErrorClassifier.classify(%{unknown: "error"})

      assert result.origin == :unknown
      assert result.class == :transient
    end

    test "preserves context" do
      ctx = %{module: MyModule, operation: :create, attempt: 2}

      result = ErrorClassifier.classify(:some_error, ctx)

      assert result.context == ctx
    end
  end

  describe "retry_policy/1" do
    test "returns retry config for transient errors" do
      error_class = %ErrorClass{origin: :system, class: :transient}

      assert {:retry, 5, 500, 2.0} = ErrorClassifier.retry_policy(error_class)
    end

    test "returns retry config for timeout errors" do
      error_class = %ErrorClass{origin: :external, class: :timeout}

      assert {:retry, 3, 1000, 2.0} = ErrorClassifier.retry_policy(error_class)
    end

    test "returns retry config for dependency errors" do
      error_class = %ErrorClass{origin: :infrastructure, class: :dependency}

      assert {:retry, 7, 1000, 1.5} = ErrorClassifier.retry_policy(error_class)
    end

    test "returns no_retry for validation errors" do
      error_class = %ErrorClass{origin: :user, class: :validation}

      assert :no_retry = ErrorClassifier.retry_policy(error_class)
    end

    test "returns no_retry for permanent errors" do
      error_class = %ErrorClass{origin: :external, class: :permanent}

      assert :no_retry = ErrorClassifier.retry_policy(error_class)
    end

    test "returns no_retry for security errors" do
      error_class = %ErrorClass{origin: :user, class: :security}

      assert :no_retry = ErrorClassifier.retry_policy(error_class)
    end
  end

  describe "should_dlq?/1" do
    test "returns true for transient after exhausted retries" do
      error_class = %ErrorClass{origin: :system, class: :transient}

      assert ErrorClassifier.should_dlq?(error_class)
    end

    test "returns true for timeout after exhausted retries" do
      error_class = %ErrorClass{origin: :external, class: :timeout}

      assert ErrorClassifier.should_dlq?(error_class)
    end

    test "returns false for security errors (audit channel)" do
      error_class = %ErrorClass{origin: :user, class: :security}

      refute ErrorClassifier.should_dlq?(error_class)
    end

    test "returns false for validation errors" do
      error_class = %ErrorClass{origin: :user, class: :validation}

      refute ErrorClassifier.should_dlq?(error_class)
    end
  end
end
