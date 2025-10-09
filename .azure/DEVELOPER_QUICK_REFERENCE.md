# Thunderline Rebuild - Developer Quick Reference

**Quick access to commands, patterns, and guidelines for HC task execution.**

---

## Mix Tasks (Quality Gates)

```bash
# Event taxonomy validation
mix thunderline.events.lint

# Ash resource validation
mix ash doctor

# Code quality
mix credo --strict

# Type checking
mix dialyzer

# Security scanning
mix sobelow --config

# Test with coverage
mix test --cover

# Run all quality checks
mix compile --warnings-as-errors && \
mix test && \
mix thunderline.events.lint && \
mix ash doctor && \
mix credo --strict
```

---

## EventBus API (HC-01)

### Publishing Events
```elixir
# Correct usage (HC-01 compliant):
{:ok, event} = Thunderline.EventBus.publish_event(%{
  name: "system.startup.complete",
  source: "thunderline.core",
  category: :system,
  priority: :normal,
  payload: %{
    duration_ms: 1234,
    components_loaded: 42
  }
})

# Handle result:
case Thunderline.EventBus.publish_event(attrs) do
  {:ok, event} -> 
    Logger.info("Event published: #{event.id}")
    {:ok, event}
  
  {:error, reason} ->
    Logger.error("Event publish failed: #{inspect(reason)}")
    {:error, reason}
end
```

### Event Categories (HC-03)
- `:system` - Lifecycle, health, configuration
- `:domain` - Ash actions, resource changes
- `:integration` - External APIs, webhooks
- `:user` - User actions, sessions, auth
- `:error` - Exceptions, failures

### Event Naming Convention
```
<domain>.<component>.<action>

Examples:
- system.startup.complete
- thunderbolt.model_run.started
- thunderlink.message.sent
- thundergate.auth.failed
- error.database.connection_lost
```

---

## Telemetry Spans

### Emitting Telemetry
```elixir
# Start span
metadata = %{
  actor_id: actor.id,
  resource_id: resource.id,
  action: :create
}

:telemetry.execute(
  [:thunderline, :thunderbolt, :model_run, :start],
  %{system_time: System.system_time()},
  metadata
)

# Stop span (success)
:telemetry.execute(
  [:thunderline, :thunderbolt, :model_run, :stop],
  %{duration: duration_ms},
  metadata
)

# Exception span
:telemetry.execute(
  [:thunderline, :thunderbolt, :model_run, :exception],
  %{duration: duration_ms},
  Map.put(metadata, :error, inspect(error))
)
```

### Common Telemetry Patterns
```elixir
# Wrap operation with telemetry
def perform_operation(params) do
  metadata = %{operation: :perform_operation, params: params}
  start_time = System.monotonic_time()
  
  :telemetry.execute([:thunderline, :domain, :operation, :start], %{}, metadata)
  
  result = do_operation(params)
  
  duration = System.monotonic_time() - start_time
  
  :telemetry.execute(
    [:thunderline, :domain, :operation, :stop],
    %{duration: duration},
    metadata
  )
  
  result
rescue
  error ->
    duration = System.monotonic_time() - start_time
    
    :telemetry.execute(
      [:thunderline, :domain, :operation, :exception],
      %{duration: duration},
      Map.put(metadata, :error, inspect(error))
    )
    
    reraise error, __STACKTRACE__
end
```

---

## Ash 3.x Patterns

### Resource Definition
```elixir
defmodule Thunderline.ThunderDomain.Resources.MyResource do
  use Ash.Resource,
    domain: Thunderline.ThunderDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "my_resources"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255
    end
    
    attribute :status, :atom do
      allow_nil? false
      default :draft
      constraints one_of: [:draft, :active, :archived]
    end
    
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Thunderline.Thundergate.Resources.User
    has_many :items, Thunderline.ThunderDomain.Resources.Item
  end

  calculations do
    calculate :display_name, :string, expr(name <> " (" <> status <> ")")
  end

  aggregates do
    count :item_count, :items
  end

  actions do
    defaults [:read, :destroy]
    
    create :create do
      accept [:name, :status]
      argument :user_id, :uuid, allow_nil?: false
      change relate_actor(:user)
    end
    
    update :update do
      accept [:name, :status]
    end
    
    update :activate do
      accept []
      change set_attribute(:status, :active)
      change {MyChange, [emit_event: true]}
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end
    
    policy action_type([:create, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  code_interface do
    define :create, args: [:name, :user_id]
    define :update, args: [:name]
    define :activate
  end
end
```

### State Machine Resource
```elixir
defmodule Thunderline.Thunderbolt.Resources.ModelRun do
  use Ash.Resource,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :start do
        from :draft
        to :running
      end

      transition :complete do
        from :running
        to :completed
      end

      transition :fail do
        from [:draft, :running]
        to :failed
      end
    end
  end

  attributes do
    uuid_primary_key :id
    
    attribute :state, :atom do
      allow_nil? false
      default :draft
      constraints one_of: [:draft, :running, :completed, :failed]
    end
    
    # ... other attributes
  end

  actions do
    defaults [:read]
    
    create :create do
      accept [:name]
    end
    
    update :start do
      accept []
      change transition_state(:running)
      change {EmitEventChange, event_name: "thunderbolt.model_run.started"}
    end
    
    update :complete do
      accept [:result]
      change transition_state(:completed)
      change {EmitEventChange, event_name: "thunderbolt.model_run.completed"}
    end
    
    update :fail do
      accept [:error_message]
      change transition_state(:failed)
      change {EmitEventChange, event_name: "thunderbolt.model_run.failed"}
    end
  end
end
```

### Policy Patterns
```elixir
# Read access for members
policy action_type(:read) do
  authorize_if relates_to_actor_via(:community, :members)
end

# Write access for admins only
policy action_type([:create, :update, :destroy]) do
  authorize_if actor_attribute_equals(:role, :admin)
end

# Custom policy with multiple conditions
policy action(:approve) do
  authorize_if actor_attribute_equals(:role, :admin)
  authorize_if expr(status == :pending)
  forbid_if expr(approved_by_id != nil)
end

# Integration with Thundergate central policies
policy action(:sensitive_action) do
  authorize_if Thundergate.Policies.has_permission(:sensitive_action)
end

# Default deny
policy action_type(:*) do
  forbid_if always()
end
```

### Query Patterns
```elixir
# Load associations
MyResource
|> Ash.Query.for_read(:read, %{}, actor: actor)
|> Ash.Query.load([:user, :items])
|> Ash.read!()

# Filter with expressions
MyResource
|> Ash.Query.for_read(:read, %{}, actor: actor)
|> Ash.Query.filter(status == :active)
|> Ash.Query.filter(inserted_at > ago(7, :day))
|> Ash.read!()

# Sort and limit
MyResource
|> Ash.Query.for_read(:read, %{}, actor: actor)
|> Ash.Query.sort(inserted_at: :desc)
|> Ash.Query.limit(10)
|> Ash.read!()

# Aggregate queries
MyResource
|> Ash.Query.for_read(:read, %{}, actor: actor)
|> Ash.Query.load(:item_count)
|> Ash.read!()
```

---

## Oban Job Patterns (HC-04)

### Defining Jobs
```elixir
defmodule Thunderline.Thunderbolt.Workers.TrainingWorker do
  use Oban.Worker,
    queue: :cerebros,
    max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"model_run_id" => model_run_id}}) do
    # Emit start telemetry
    :telemetry.execute(
      [:thunderline, :thunderbolt, :training, :start],
      %{},
      %{model_run_id: model_run_id}
    )

    with {:ok, model_run} <- get_model_run(model_run_id),
         {:ok, _} <- start_training(model_run),
         {:ok, result} <- wait_for_completion(model_run),
         {:ok, _} <- update_model_run(model_run, result) do
      
      # Emit success telemetry
      :telemetry.execute(
        [:thunderline, :thunderbolt, :training, :stop],
        %{duration: result.duration_ms},
        %{model_run_id: model_run_id}
      )
      
      :ok
    else
      {:error, reason} ->
        # Emit error telemetry
        :telemetry.execute(
          [:thunderline, :thunderbolt, :training, :exception],
          %{},
          %{model_run_id: model_run_id, error: inspect(reason)}
        )
        
        {:error, reason}
    end
  end
end
```

### Scheduling Jobs
```elixir
# Schedule immediately
%{model_run_id: model_run.id}
|> Thunderline.Thunderbolt.Workers.TrainingWorker.new()
|> Oban.insert()

# Schedule with delay
%{model_run_id: model_run.id}
|> Thunderline.Thunderbolt.Workers.TrainingWorker.new(schedule_in: 60)
|> Oban.insert()

# Schedule at specific time
%{model_run_id: model_run.id}
|> Thunderline.Thunderbolt.Workers.TrainingWorker.new(
  scheduled_at: ~U[2025-10-10 12:00:00Z]
)
|> Oban.insert()

# Unique jobs (prevent duplicates)
%{model_run_id: model_run.id}
|> Thunderline.Thunderbolt.Workers.TrainingWorker.new(
  unique: [period: 60, keys: [:model_run_id]]
)
|> Oban.insert()
```

---

## Testing Patterns

### Resource Tests
```elixir
defmodule Thunderline.ThunderDomain.MyResourceTest do
  use Thunderline.DataCase, async: true
  
  alias Thunderline.ThunderDomain.Resources.MyResource
  
  describe "create action" do
    test "creates resource with valid attributes" do
      user = user_fixture()
      
      assert {:ok, resource} = 
        MyResource
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Resource"
        }, actor: user)
        |> Ash.create()
      
      assert resource.name == "Test Resource"
      assert resource.status == :draft
      assert resource.user_id == user.id
    end
    
    test "fails with invalid attributes" do
      user = user_fixture()
      
      assert {:error, %Ash.Error.Invalid{} = error} =
        MyResource
        |> Ash.Changeset.for_create(:create, %{
          name: ""
        }, actor: user)
        |> Ash.create()
      
      assert Exception.message(error) =~ "name"
    end
  end
  
  describe "policies" do
    test "allows owner to read" do
      user = user_fixture()
      resource = resource_fixture(user: user)
      
      assert {:ok, [found]} =
        MyResource
        |> Ash.Query.filter(id == ^resource.id)
        |> Ash.read(actor: user)
      
      assert found.id == resource.id
    end
    
    test "forbids non-owner from reading" do
      user = user_fixture()
      other_user = user_fixture()
      resource = resource_fixture(user: user)
      
      assert {:ok, []} =
        MyResource
        |> Ash.Query.filter(id == ^resource.id)
        |> Ash.read(actor: other_user)
    end
  end
end
```

### Event Emission Tests
```elixir
test "emits event on successful creation" do
  user = user_fixture()
  
  # Capture telemetry events
  ref = :telemetry_test.attach_event_handlers(
    self(),
    [[:thunderline, :eventbus, :publish, :stop]]
  )
  
  assert {:ok, resource} =
    MyResource
    |> Ash.Changeset.for_create(:create, %{name: "Test"}, actor: user)
    |> Ash.create()
  
  # Assert event was emitted
  assert_received {[:thunderline, :eventbus, :publish, :stop], ^ref, 
    %{duration: _}, %{event_name: "domain.resource.created"}}
end
```

### State Machine Tests
```elixir
test "transitions from draft to running" do
  model_run = model_run_fixture(state: :draft)
  
  assert {:ok, updated} =
    ModelRun
    |> Ash.Changeset.for_update(:start, %{}, actor: model_run.user)
    |> Ash.update()
  
  assert updated.state == :running
end

test "fails transition from completed to running" do
  model_run = model_run_fixture(state: :completed)
  
  assert {:error, error} =
    ModelRun
    |> Ash.Changeset.for_update(:start, %{}, actor: model_run.user)
    |> Ash.update()
  
  assert Exception.message(error) =~ "invalid state transition"
end
```

### Oban Job Tests
```elixir
use Oban.Testing, repo: Thunderline.Repo

test "processes training job successfully" do
  model_run = model_run_fixture()
  
  assert :ok =
    perform_job(TrainingWorker, %{model_run_id: model_run.id})
  
  updated = Ash.get!(ModelRun, model_run.id)
  assert updated.state == :completed
end

test "retries on transient error" do
  model_run = model_run_fixture()
  
  # Simulate transient error (network timeout)
  expect(MLflowClientMock, :start_run, fn _ -> 
    {:error, :timeout} 
  end)
  
  assert {:error, :timeout} =
    perform_job(TrainingWorker, %{model_run_id: model_run.id})
  
  # Job should be retried
  assert_enqueued worker: TrainingWorker, 
                 args: %{model_run_id: model_run.id}
end
```

---

## Error Handling Patterns (HC-09)

### Error Classification
```elixir
defmodule Thunderline.Thunderflow.ErrorClassifier do
  def classify(error) do
    case error do
      # Transient errors (retry-able)
      %DBConnection.ConnectionError{} -> :transient
      %Mint.TransportError{reason: :timeout} -> :transient
      %Mint.TransportError{reason: :closed} -> :transient
      
      # Permanent errors (not retry-able)
      %Ecto.NoResultsError{} -> :permanent
      %Jason.DecodeError{} -> :permanent
      %Ash.Error.Forbidden{} -> :permanent
      %Ash.Error.Invalid{} -> :permanent
      
      # Unknown (needs investigation)
      _ -> :unknown
    end
  end
  
  def retry_policy(error) do
    case classify(error) do
      :transient -> {:retry, backoff_ms: exponential_backoff()}
      :permanent -> {:discard, reason: "permanent error"}
      :unknown -> {:retry, max_attempts: 1, backoff_ms: 5000}
    end
  end
  
  defp exponential_backoff(attempt \\ 1) do
    # 2^attempt * 1000 + jitter
    base = :math.pow(2, attempt) * 1000
    jitter = :rand.uniform(1000)
    trunc(base + jitter)
  end
end
```

### Broadway DLQ Handler
```elixir
defmodule Thunderline.Thunderflow.Broadway.DLQHandler do
  def handle_failed(messages, _context) do
    Enum.each(messages, fn msg ->
      error = msg.status.reason
      classification = ErrorClassifier.classify(error)
      
      :telemetry.execute(
        [:thunderline, :broadway, :dlq],
        %{count: 1},
        %{
          classification: classification,
          message_id: msg.data.id,
          error: inspect(error)
        }
      )
      
      case ErrorClassifier.retry_policy(error) do
        {:retry, opts} ->
          # Requeue with backoff
          schedule_retry(msg, opts)
        
        {:discard, reason} ->
          # Log and discard
          Logger.error("Message discarded: #{reason}", message: msg.data)
      end
    end)
  end
end
```

---

## Git Workflow

### Branch Naming
```bash
# Format: hc-{task-id}-{brief-description}
git checkout -b hc-01-eventbus-restoration
git checkout -b hc-04-cerebros-lifecycle
git checkout -b hc-05-email-mvp
```

### Commit Messages
```bash
# Format: HC-XX: Brief description
git commit -m "HC-01: Restore EventBus.publish_event/1 with validation"
git commit -m "HC-04: Activate ModelRun state machine transitions"
git commit -m "HC-05: Add Contact and OutboundEmail resources"
```

### PR Workflow
```bash
# 1. Create feature branch
git checkout -b hc-01-eventbus-restoration

# 2. Make changes and commit
git add lib/thunderline/thunderflow/event_bus.ex
git commit -m "HC-01: Restore EventBus.publish_event/1"

# 3. Run quality checks
mix test && \
mix thunderline.events.lint && \
mix ash doctor && \
mix credo --strict

# 4. Push and create PR
git push origin hc-01-eventbus-restoration

# 5. Fill out PR template with checklist
# 6. Tag domain steward for review
# 7. Address feedback and merge
```

---

## Common Pitfalls & Solutions

### ❌ Using legacy Bus API
```elixir
# DON'T (deprecated):
Thunderline.Bus.put(:system_event, %{data: "..."})

# DO (HC-01 compliant):
Thunderline.EventBus.publish_event(%{
  name: "system.event.occurred",
  source: "thunderline.core",
  category: :system,
  priority: :normal,
  payload: %{data: "..."}
})
```

### ❌ Inline policy checks
```elixir
# DON'T:
def perform_action(resource, actor) do
  if actor.role == :admin do
    # do something
  else
    {:error, :unauthorized}
  end
end

# DO (use Ash policies):
policies do
  policy action(:perform_action) do
    authorize_if actor_attribute_equals(:role, :admin)
  end
end
```

### ❌ Missing telemetry
```elixir
# DON'T:
def expensive_operation(params) do
  # ... no telemetry
  result
end

# DO:
def expensive_operation(params) do
  start_time = System.monotonic_time()
  
  :telemetry.execute([:thunderline, :domain, :operation, :start], %{}, %{})
  
  result = do_operation(params)
  
  duration = System.monotonic_time() - start_time
  :telemetry.execute([:thunderline, :domain, :operation, :stop], 
    %{duration: duration}, %{})
  
  result
end
```

### ❌ N+1 queries
```elixir
# DON'T:
resources = Ash.read!(MyResource)
Enum.map(resources, fn r -> r.user end) # N+1 query

# DO:
resources =
  MyResource
  |> Ash.Query.load(:user)
  |> Ash.read!()
Enum.map(resources, fn r -> r.user end) # Single query
```

---

## Resources

- **Main Task Doc:** `.azure/THUNDERLINE_REBUILD_INITIATIVE.md`
- **PR Checklist:** `.azure/PR_REVIEW_CHECKLIST.md`
- **Weekly Template:** `.azure/WARDEN_CHRONICLES_TEMPLATE.md`
- **Event Taxonomy:** `documentation/EVENT_TAXONOMY.md` (HC-03)
- **Error Classes:** `documentation/ERROR_CLASSES.md` (HC-03)
- **Feature Flags:** `FEATURE_FLAGS.md` (HC-10)

---

**Last Updated:** October 9, 2025  
**Version:** 1.0
