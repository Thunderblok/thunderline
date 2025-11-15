# Thunderforge → Thunderblock: Sensor-to-STAC System

## Overview

Complete data pipeline from edge sensors through knowledge assembly to tokenized rewards. This system enables "experience becomes computable" by transforming raw sensor data into validated, rewarded knowledge within the Thunderline ecosystem.

**High-Level Flow**: Nerves devices → Thunderbit packets → Decode → Assemble → PAC validation → DAG commit → STAC reward → Staking → STACC certificates

**Status**: Specification phase (HC-24 - P1 priority)

---

## 0. Terminology

- **Thunderbit**: Atomic signed data packet from edge sensor (~100-500 bytes, includes sensor_id, timestamp, payload, signature)
- **Knowledge Item (KI)**: Assembled unit of validated knowledge (Instruction, Milestone, Query, Observation, Metric)
- **Local DAG**: Time-ordered directed acyclic graph of knowledge items showing causal relationships
- **STAC**: "Sensor-Timestamp-Attestation-Certificate" - rewarded knowledge token (ERC-20 compatible)
- **sSTAC**: Staked STAC locked in DAO contract (yields governance rights)
- **STACC**: "STAC Certificate" - proof-of-stake receipt (burn sSTAC → yield STACC, tradeable yield instrument)

---

## 1. High-Level Flow

### Phase 1: Ingestion (Thunderforge)
```
Nerves Device → ThunderGate (mTLS) → Thunderbit Queue (:forge_decode)
```
- Edge devices emit signed Thunderbits (heartbeat, sensor readings, state changes)
- ThunderGate authenticates via client certificates and routes to Oban queue
- Thunderbits stored in `thunderforge.thunderbits` table (raw persistence)

### Phase 2: Decoding (Thunderforge)
```
:forge_decode Worker → Validate signature → Parse schema → Emit decoded event
```
- Oban worker validates ECDSA/Ed25519 signatures
- Schema-specific decoders (heart rate, temperature, GPS, etc.)
- Publishes `system.forge.bit_decoded` event with structured payload

### Phase 3: Assembly (Thunderforge)
```
Decoded bits → Assembly rules → Knowledge Item (KI) candidate
```
- Pattern matching across time windows (e.g., "3 heart rate samples + 1 GPS = Activity")
- Assembly rules defined in Crown policies
- Candidate KIs queued to `:forge_assemble` → `:pac_validate`

### Phase 4: PAC Validation (Thunderbolt)
```
KI candidate → PAC policy check → Pass/Fail → Event emission
```
- Relevance: Does this KI matter to current goals?
- Novelty: Is this information new or redundant?
- Crown Policy: Does it align with governance rules?
- Ownership: Is sensor authorized to produce this KI type?
- Integrity: Are signatures/timestamps valid?
- Cost Budget: Does processing fit resource limits?

### Phase 5: DAG Commit (Thunderblock)
```
Validated KI → DAG node creation → Edge linking → Persistence
```
- Insert node into `thunderblock.knowledge_dag_nodes`
- Create edges to causal parent nodes (correlation_id lineage)
- Update DAG statistics (depth, breadth, component sizes)

### Phase 6: STAC Reward (Thunderblock)
```
Committed KI → Reward function → STAC mint → Ledger entry
```
- Reward function: `R = B * Q(ki) * N(ki) * P(ki) * S(owner)`
- Mint STAC tokens to owner's wallet
- Record in `thunderblock.stac_rewards` ledger
- Emit `system.rewards.stac_minted` event

### Phase 7: Staking (Optional)
```
User stakes STAC → DAO contract → sSTAC receipt → Yield accrual
```
- Lock STAC tokens in governance DAO contract
- Issue sSTAC (staked STAC) receipt
- Accrue yield over staking period
- Burn sSTAC → mint STACC (tradeable yield certificate)

### Phase 8: Federation (Future)
```
Local DAG → ActivityPub → Remote nodes → Federated knowledge graph
```
- Export DAG subgraphs as ActivityPub objects
- Cryptographic proofs for cross-node verification
- Federated queries across Thunderline network

---

## 2. Core Data Models

### Thunderbit (Thunderforge)
```elixir
defmodule Thunderline.Thunderforge.Thunderbit do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events]

  attributes do
    uuid_primary_key :id, type: Ash.Type.UUIDv7
    attribute :sensor_id, :string, allow_nil?: false
    attribute :timestamp, :utc_datetime_usec, allow_nil?: false
    attribute :payload, :map, allow_nil?: false  # Raw sensor data
    attribute :signature, :binary, allow_nil?: false  # ECDSA/Ed25519
    attribute :schema_version, :string, default: "1.0"
    attribute :decoded?, :boolean, default: false
  end

  postgres do
    table "thunderbits"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]
    create :ingest  # From ThunderGate
    update :mark_decoded  # After :forge_decode worker
  end
end
```

### Knowledge Item (Thunderblock)
```elixir
defmodule Thunderline.Thunderblock.KnowledgeItem do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id, type: Ash.Type.UUIDv7
    attribute :type, :atom, constraints: [
      one_of: [:instruction, :milestone, :query, :observation, :metric]
    ]
    attribute :content, :map, allow_nil?: false
    attribute :owner_id, Ash.Type.UUID, allow_nil?: false
    attribute :validated_at, :utc_datetime_usec
    attribute :reward_amount, :decimal  # STAC minted
  end

  relationships do
    has_many :dag_nodes, Thunderline.Thunderblock.DAGNode
    has_many :source_thunderbits, Thunderline.Thunderforge.Thunderbit
  end
end
```

### DAG Node (Thunderblock)
```elixir
defmodule Thunderline.Thunderblock.DAGNode do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id, type: Ash.Type.UUIDv7
    attribute :knowledge_item_id, Ash.Type.UUID, allow_nil?: false
    attribute :committed_at, :utc_datetime_usec, allow_nil?: false
    attribute :dag_depth, :integer, default: 0
  end

  relationships do
    belongs_to :knowledge_item, Thunderline.Thunderblock.KnowledgeItem
    many_to_many :parent_nodes, __MODULE__,
      through: Thunderline.Thunderblock.DAGEdge,
      source_attribute: :child_id,
      destination_attribute: :parent_id
  end
end
```

### DAG Edge (Thunderblock)
```elixir
defmodule Thunderline.Thunderblock.DAGEdge do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :parent_id, Ash.Type.UUID, allow_nil?: false
    attribute :child_id, Ash.Type.UUID, allow_nil?: false
    attribute :edge_type, :atom, default: :causal  # :causal, :reference, :supersedes
  end

  identities do
    identity :unique_edge, [:parent_id, :child_id]
  end
end
```

### STAC Rewards Ledger (Thunderblock)
```elixir
defmodule Thunderline.Thunderblock.STACReward do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id, type: Ash.Type.UUIDv7
    attribute :knowledge_item_id, Ash.Type.UUID, allow_nil?: false
    attribute :owner_id, Ash.Type.UUID, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false  # STAC tokens minted
    attribute :quality_score, :decimal  # Q(ki) from reward function
    attribute :novelty_score, :decimal  # N(ki)
    attribute :policy_score, :decimal  # P(ki)
    attribute :stake_multiplier, :decimal  # S(owner)
    attribute :minted_at, :utc_datetime_usec, allow_nil?: false
  end
end
```

---

## 3. Knowledge Schema (5 Types)

### Instruction
```elixir
%{
  type: :instruction,
  content: %{
    action: "calibrate_sensor",
    parameters: %{sensor_id: "ABC123", threshold: 0.95},
    preconditions: ["sensor_online", "temperature_stable"],
    expected_outcome: "Sensor calibrated within 5% tolerance"
  }
}
```

### Milestone
```elixir
%{
  type: :milestone,
  content: %{
    achievement: "10k_steps_daily_streak",
    duration_days: 30,
    evidence: [thunderbit_ids...],
    certified_at: ~U[2025-10-21 12:00:00Z]
  }
}
```

### Query
```elixir
%{
  type: :query,
  content: %{
    question: "What was my average heart rate during sleep last week?",
    time_range: {~U[2025-10-14 00:00:00Z], ~U[2025-10-21 00:00:00Z]},
    required_sensor_types: ["heart_rate"],
    expected_precision: "1 BPM"
  }
}
```

### Observation
```elixir
%{
  type: :observation,
  content: %{
    phenomenon: "heart_rate_spike",
    measured_value: 145,
    baseline_value: 72,
    timestamp: ~U[2025-10-21 14:35:22Z],
    context: "during_exercise",
    confidence: 0.98
  }
}
```

### Metric
```elixir
%{
  type: :metric,
  content: %{
    metric_name: "daily_step_count",
    value: 12543,
    unit: "steps",
    measurement_period: {~U[2025-10-21 00:00:00Z], ~U[2025-10-21 23:59:59Z]},
    quality: "high"  # based on sensor uptime and data completeness
  }
}
```

---

## 4. Oban Queues & Workers

### Queue Configuration
```elixir
config :thunderline, Oban,
  repo: Thunderline.Repo,
  queues: [
    forge_decode: [limit: 50, paused: false],      # Decode Thunderbits
    forge_assemble: [limit: 20, paused: false],    # Assemble KI candidates
    pac_validate: [limit: 10, paused: false],      # PAC policy checks
    dag_commit: [limit: 5, paused: false],         # DAG persistence
    reward_mint: [limit: 3, paused: false],        # STAC minting
    federate: [limit: 2, paused: true]             # ActivityPub export (future)
  ]
```

### Worker: DecodeThunderbit
```elixir
defmodule Thunderline.Thunderbolt.Workers.DecodeThunderbit do
  use Oban.Worker, queue: :forge_decode, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thunderbit_id" => id}}) do
    thunderbit = Thunderline.Thunderforge.get_thunderbit!(id)
    
    with :ok <- verify_signature(thunderbit),
         {:ok, decoded} <- decode_schema(thunderbit.payload, thunderbit.schema_version),
         {:ok, _} <- mark_decoded(thunderbit),
         {:ok, _} <- publish_decoded_event(decoded, thunderbit) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_signature(thunderbit), do: ...
  defp decode_schema(payload, version), do: ...
  defp mark_decoded(thunderbit), do: ...
  defp publish_decoded_event(decoded, thunderbit), do: ...
end
```

### Worker: AssembleKnowledgeItem
```elixir
defmodule Thunderline.Thunderbolt.Workers.AssembleKnowledgeItem do
  use Oban.Worker, queue: :forge_assemble, max_attempts: 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"decoded_bits" => bits}}) do
    # Pattern match across time window to assemble KI
    # Example: 3 heart rate + 1 GPS + 1 accelerometer = "activity" KI
    case match_assembly_pattern(bits) do
      {:ok, ki_candidate} ->
        enqueue_pac_validation(ki_candidate)
      :no_match ->
        :ok  # Not enough bits yet
    end
  end
end
```

### Worker: ValidateWithPAC
```elixir
defmodule Thunderline.Thunderbolt.Workers.ValidateWithPAC do
  use Oban.Worker, queue: :pac_validate, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ki_candidate" => ki}}) do
    checks = [
      &check_relevance/1,
      &check_novelty/1,
      &check_crown_policy/1,
      &check_ownership/1,
      &check_integrity/1,
      &check_cost_budget/1
    ]

    case run_pac_checks(ki, checks) do
      :pass ->
        enqueue_dag_commit(ki)
        publish_event("system.pac.validated", ki)
      {:fail, reason} ->
        publish_event("system.pac.rejected", ki, reason)
    end
  end
end
```

### Worker: CommitToDAG
```elixir
defmodule Thunderline.Thunderbolt.Workers.CommitToDAG do
  use Oban.Worker, queue: :dag_commit, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ki" => ki}}) do
    with {:ok, node} <- create_dag_node(ki),
         {:ok, _edges} <- link_to_parents(node, ki.correlation_ids),
         {:ok, _} <- update_dag_stats() do
      enqueue_reward_mint(ki, node)
      publish_event("system.block.dag_committed", node)
      :ok
    end
  end
end
```

### Worker: MintSTAC
```elixir
defmodule Thunderline.Thunderbolt.Workers.MintSTAC do
  use Oban.Worker, queue: :reward_mint, max_attempts: 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ki_id" => ki_id, "node_id" => node_id}}) do
    ki = get_knowledge_item!(ki_id)
    
    # Calculate reward: R = B * Q(ki) * N(ki) * P(ki) * S(owner)
    reward_amount = calculate_stac_reward(ki)
    
    with {:ok, ledger_entry} <- record_reward(ki, reward_amount),
         {:ok, _} <- mint_tokens(ki.owner_id, reward_amount) do
      publish_event("system.rewards.stac_minted", ledger_entry)
      :ok
    end
  end

  defp calculate_stac_reward(ki) do
    base_rate = Application.get_env(:thunderline, :stac_base_rate, 1.0)
    quality_score = assess_quality(ki)
    novelty_score = assess_novelty(ki)
    policy_score = assess_policy_compliance(ki)
    stake_multiplier = get_owner_stake_multiplier(ki.owner_id)
    
    base_rate * quality_score * novelty_score * policy_score * stake_multiplier
  end
end
```

---

## 5. PAC Validation Policy

### Six-Dimensional Check
```elixir
defmodule Thunderline.Thunderbolt.PACValidator do
  @moduledoc """
  Policy-Aware Computation (PAC) validation for Knowledge Items.
  Implements six-dimensional checking before DAG commit.
  """

  @doc "Check 1: Relevance - Does this KI align with current goals?"
  def check_relevance(ki) do
    # Query active goals/missions from Crown
    # Score KI against goal embeddings
    # Pass if cosine similarity > threshold
  end

  @doc "Check 2: Novelty - Is this information new or redundant?"
  def check_novelty(ki) do
    # Query DAG for similar KIs (embedding search)
    # Calculate novelty decay factor
    # Pass if novelty score > threshold
  end

  @doc "Check 3: Crown Policy - Does it comply with governance?"
  def check_crown_policy(ki) do
    # Load active Crown policies
    # Check KI type, owner permissions, content rules
    # Pass if all policy rules satisfied
  end

  @doc "Check 4: Ownership - Is sensor authorized for this KI type?"
  def check_ownership(ki) do
    # Verify sensor_id → owner_id chain of trust
    # Check if owner has permission to produce this KI type
    # Pass if ownership chain valid
  end

  @doc "Check 5: Integrity - Are signatures and timestamps valid?"
  def check_integrity(ki) do
    # Verify all Thunderbit signatures
    # Check timestamp ordering (no future-dated bits)
    # Validate schema compliance
    # Pass if all integrity checks pass
  end

  @doc "Check 6: Cost Budget - Does processing fit resource limits?"
  def check_cost_budget(ki) do
    # Estimate compute/storage cost for DAG commit
    # Check against owner's quota and global limits
    # Pass if cost within budget
  end
end
```

### Scoring Thresholds (Configurable)
```elixir
config :thunderline, :pac_validation,
  relevance_threshold: 0.7,       # Cosine similarity to active goals
  novelty_threshold: 0.5,         # Novelty decay factor
  integrity_max_age_hours: 24,    # Reject old Thunderbits
  cost_budget_multiplier: 1.0,    # Global scaling factor
  policy_strict_mode: true        # Fail hard on policy violations
```

---

## 6. STAC Reward Function

### Mathematical Definition
```
R = B * Q(ki) * N(ki) * P(ki) * S(owner)

Where:
- R = STAC reward amount (decimal)
- B = Base rate (configured per KI type, e.g., 1.0 for Observation)
- Q(ki) = Quality score [0, 1] (data completeness, sensor accuracy)
- N(ki) = Novelty score [0, 1] (exponential decay: e^(-λ * similarity))
- P(ki) = Policy score [0, 1] (Crown compliance bonus)
- S(owner) = Stake multiplier [1.0, 2.0] (based on sSTAC holdings)
```

### Quality Score (Q)
```elixir
def assess_quality(ki) do
  completeness = count_required_fields(ki) / total_required_fields(ki.type)
  accuracy = sensor_calibration_score(ki.source_sensors)
  confidence = avg_confidence(ki.content)
  
  (completeness + accuracy + confidence) / 3.0
end
```

### Novelty Score (N)
```elixir
def assess_novelty(ki) do
  # Query DAG for similar KIs in last 30 days
  similar_kis = search_dag_by_embedding(ki, days: 30, limit: 10)
  
  if Enum.empty?(similar_kis) do
    1.0  # Completely novel
  else
    max_similarity = Enum.max_by(similar_kis, & &1.cosine_similarity).cosine_similarity
    lambda = 2.0  # Decay rate
    :math.exp(-lambda * max_similarity)
  end
end
```

### Policy Score (P)
```elixir
def assess_policy_compliance(ki) do
  # Base score: 0.5 (neutral)
  # +0.5 if KI aligns with active Crown mandates
  # +0.2 if owner has good compliance history
  # -0.3 if KI type flagged for review
  base = 0.5
  mandate_bonus = if aligns_with_mandates?(ki), do: 0.5, else: 0.0
  history_bonus = owner_compliance_bonus(ki.owner_id)
  review_penalty = if flagged_for_review?(ki.type), do: -0.3, else: 0.0
  
  Enum.max([0.0, base + mandate_bonus + history_bonus + review_penalty])
end
```

### Stake Multiplier (S)
```elixir
def get_owner_stake_multiplier(owner_id) do
  staked_amount = get_sSTAC_balance(owner_id)
  
  cond do
    staked_amount >= 10_000 -> 2.0  # Whale tier
    staked_amount >= 1_000 -> 1.5   # Committed tier
    staked_amount >= 100 -> 1.2     # Active tier
    true -> 1.0                     # Base tier
  end
end
```

### Anti-Sybil Mechanisms
- **Novelty Decay**: Repeated similar KIs earn exponentially less
- **Cost Budget**: Quota per owner per day (prevents spam)
- **Collusion Detector**: Flag clusters of similar KIs from different owners (future)

---

## 7. Staking & STACC Issuance

### Staking Flow
```
User locks STAC → DAO contract → Receive sSTAC → Accrue yield → Burn sSTAC → Mint STACC
```

### sSTAC (Staked STAC)
- ERC-20 compatible receipt token
- 1:1 with locked STAC initially
- Value increases over time due to yield accrual
- Governance rights: 1 sSTAC = 1 vote in DAO proposals

### STACC (STAC Certificate)
- Tradeable yield instrument
- Minted when user burns sSTAC after staking period
- Represents accumulated yield (e.g., 100 STAC staked for 1 year → 110 STACC)
- Can be sold on secondary market

### Smart Contract Interface (Conceptual)
```solidity
contract STACStaking {
  function stake(uint256 amount) external;
  function unstake(uint256 amount) external;
  function claimYield() external returns (uint256 staccAmount);
  function getStakeMultiplier(address owner) external view returns (uint256);
}
```

### Yield Calculation
```elixir
def calculate_yield(owner_id) do
  stake_record = get_stake_record(owner_id)
  days_staked = DateTime.diff(DateTime.utc_now(), stake_record.staked_at, :day)
  base_apy = 0.10  # 10% annual
  
  # Bonus APY for longer lock periods
  lock_bonus = case stake_record.lock_period_days do
    d when d >= 365 -> 0.05  # +5% for 1 year+
    d when d >= 180 -> 0.03  # +3% for 6 months+
    d when d >= 90 -> 0.01   # +1% for 3 months+
    _ -> 0.0
  end
  
  total_apy = base_apy + lock_bonus
  stake_record.amount * total_apy * (days_staked / 365.0)
end
```

---

## 8. Canonical Events

### Event Taxonomy
All events follow `system.<domain>.<type>` naming convention and are published via `Thunderline.Thunderflow.EventBus.publish_event/1`.

#### Thunderforge Events
```elixir
# Thunderbit ingested from edge device
"system.forge.bit_ingested"
%{thunderbit_id: uuid, sensor_id: string, timestamp: datetime}

# Thunderbit decoded successfully
"system.forge.bit_decoded"
%{thunderbit_id: uuid, schema_version: string, payload: map}

# KI candidate assembled
"system.forge.ki_assembled"
%{ki_candidate_id: uuid, type: atom, source_bits: [uuid]}

# Assembly failed (insufficient data)
"system.forge.assembly_incomplete"
%{pattern: string, missing: [sensor_types]}
```

#### PAC Validation Events
```elixir
# KI passed PAC validation
"system.pac.validated"
%{ki_id: uuid, checks_passed: [atom], scores: map}

# KI failed PAC validation
"system.pac.rejected"
%{ki_id: uuid, failed_check: atom, reason: string}

# PAC check timeout
"system.pac.timeout"
%{ki_id: uuid, check: atom, elapsed_ms: integer}
```

#### Thunderblock Events
```elixir
# DAG node committed
"system.block.dag_committed"
%{node_id: uuid, ki_id: uuid, depth: integer, parent_count: integer}

# DAG edge created
"system.block.edge_created"
%{edge_id: uuid, parent_id: uuid, child_id: uuid, edge_type: atom}

# DAG integrity violation detected
"system.block.dag_integrity_violation"
%{node_id: uuid, violation_type: atom, details: string}
```

#### Reward Events
```elixir
# STAC reward minted
"system.rewards.stac_minted"
%{reward_id: uuid, ki_id: uuid, owner_id: uuid, amount: decimal, quality: float, novelty: float}

# Staking action
"system.rewards.stac_staked"
%{stake_id: uuid, owner_id: uuid, amount: decimal, lock_period_days: integer}

# STACC claimed
"system.rewards.stacc_claimed"
%{claim_id: uuid, owner_id: uuid, sSTAC_burned: decimal, STACC_minted: decimal}
```

---

## 9. GraphQL API Schema

### Types
```graphql
type KnowledgeItem {
  id: ID!
  type: KnowledgeItemType!
  content: JSON!
  owner: User!
  validatedAt: DateTime
  rewardAmount: Decimal
  dagNodes: [DAGNode!]!
  sourceThunderbits: [Thunderbit!]!
}

enum KnowledgeItemType {
  INSTRUCTION
  MILESTONE
  QUERY
  OBSERVATION
  METRIC
}

type DAGNode {
  id: ID!
  knowledgeItem: KnowledgeItem!
  committedAt: DateTime!
  dagDepth: Int!
  parentNodes: [DAGNode!]!
  childNodes: [DAGNode!]!
}

type STACReward {
  id: ID!
  knowledgeItem: KnowledgeItem!
  owner: User!
  amount: Decimal!
  qualityScore: Float!
  noveltyScore: Float!
  policyScore: Float!
  stakeMultiplier: Float!
  mintedAt: DateTime!
}

type StakeRecord {
  id: ID!
  owner: User!
  stakedAmount: Decimal!
  sSTACAmount: Decimal!
  stakedAt: DateTime!
  lockPeriodDays: Int!
  yieldAccrued: Decimal!
}
```

### Queries
```graphql
type Query {
  knowledgeItem(id: ID!): KnowledgeItem
  knowledgeItems(filter: KnowledgeItemFilter, limit: Int, offset: Int): [KnowledgeItem!]!
  dagNode(id: ID!): DAGNode
  dagSubgraph(rootId: ID!, maxDepth: Int): DAGSubgraph!
  stacRewards(ownerId: ID!, fromDate: DateTime, toDate: DateTime): [STACReward!]!
  myStakeRecords: [StakeRecord!]!
  stakeYield(ownerId: ID!): Decimal!
}

input KnowledgeItemFilter {
  types: [KnowledgeItemType!]
  ownerId: ID
  validatedAfter: DateTime
  rewardAmountMin: Decimal
}

type DAGSubgraph {
  nodes: [DAGNode!]!
  edges: [DAGEdge!]!
  statistics: DAGStatistics!
}

type DAGStatistics {
  nodeCount: Int!
  edgeCount: Int!
  maxDepth: Int!
  avgBranching: Float!
}
```

### Mutations
```graphql
type Mutation {
  ingestThunderbit(input: ThunderbitInput!): Thunderbit!
  stakeSTAC(amount: Decimal!, lockPeriodDays: Int!): StakeRecord!
  unstakeSTAC(stakeId: ID!): StakeRecord!
  claimYield(stakeId: ID!): STACCClaim!
}

input ThunderbitInput {
  sensorId: String!
  timestamp: DateTime!
  payload: JSON!
  signature: String!
  schemaVersion: String
}

type STACCClaim {
  id: ID!
  owner: User!
  sSTACBurned: Decimal!
  STACCMinted: Decimal!
  claimedAt: DateTime!
}
```

---

## 10. Module Structure

```
lib/thunderline/
├── thunderforge/
│   ├── resources/
│   │   ├── thunderbit.ex          # Ash resource
│   │   └── decoded_bit.ex         # Intermediate representation
│   ├── decoders/
│   │   ├── heart_rate_decoder.ex
│   │   ├── gps_decoder.ex
│   │   └── schema_registry.ex
│   └── assembly/
│       ├── pattern_matcher.ex     # Assembly rules engine
│       └── assembly_rules.ex      # Rule definitions
│
├── thunderbolt/
│   ├── workers/
│   │   ├── decode_thunderbit.ex   # Oban worker
│   │   ├── assemble_ki.ex         # Oban worker
│   │   ├── validate_pac.ex        # Oban worker
│   │   ├── commit_dag.ex          # Oban worker
│   │   └── mint_stac.ex           # Oban worker
│   ├── pac_validator.ex           # Six-dimensional checking
│   └── reward_calculator.ex       # STAC reward function
│
└── thunderblock/
    ├── resources/
    │   ├── knowledge_item.ex      # Ash resource
    │   ├── dag_node.ex            # Ash resource
    │   ├── dag_edge.ex            # Ash resource
    │   ├── stac_reward.ex         # Ash resource
    │   └── stake_record.ex        # Ash resource
    ├── dag/
    │   ├── graph_engine.ex        # DAG operations
    │   ├── integrity_checker.ex   # Cycle detection, orphan cleanup
    │   └── statistics.ex          # DAG metrics
    └── staking/
        ├── stake_manager.ex       # Staking operations
        ├── yield_calculator.ex    # Yield accrual
        └── stacc_minter.ex        # STACC issuance
```

---

## 11. Security, Privacy & Governance

### Security
- **mTLS Enrollment**: All Nerves devices authenticated via client certificates (managed by ThunderGate)
- **Signature Verification**: Every Thunderbit verified using ECDSA/Ed25519 before processing
- **Signer Rotation**: Certificate renewal every 90 days, old certs revoked gracefully
- **Rate Limiting**: Per-sensor and per-owner quotas to prevent DoS (enforced in PAC validation)

### Privacy
- **Crown-First Policy**: All KI types must be approved by Crown policies before DAG commit
- **Scoped Storage**: KI content encrypted at rest, decryption keys scoped to owner + authorized agents
- **Audit Trail**: All PAC checks and reward calculations logged with event lineage (correlation_id chains)
- **Consent Management**: Future extension for user consent records (GDPR compliance)

### Governance
- **DAO Voting**: sSTAC holders vote on Crown policy updates, reward function parameters, base rates
- **Proposal Lifecycle**: Draft → Community Review (7 days) → Vote (3 days) → Execution (if passed)
- **Emergency Powers**: Multi-sig committee can pause minting/staking in case of exploit (time-locked revocation)

---

## 12. Observability & SLOs

### Latency SLOs
- **P50 (median)**: < 150ms from Thunderbit ingestion to `bit_decoded` event
- **P95**: < 500ms from PAC validation to DAG commit
- **P99**: < 2s end-to-end (ingestion → STAC mint)

### Quality Dashboards
- **Novelty Distribution**: Histogram of N(ki) scores (track decay over time)
- **PAC Rejection Rate**: % of KI candidates failing validation (target: <5%)
- **DAG Growth Rate**: Nodes/day, edges/day (monitor for spam attacks)
- **STAC Velocity**: Minting rate, staking rate, STACC claims (economic health)

### Telemetry Events
```elixir
[:thunderline, :forge, :decode, :start | :stop | :exception]
[:thunderline, :pac, :validate, :start | :stop]
[:thunderline, :block, :dag_commit, :duration]
[:thunderline, :rewards, :stac_mint, :amount]
[:thunderline, :staking, :stake_action]
```

### Alerts
- **High PAC Rejection Rate**: Alert if >10% of KIs rejected in 1 hour window
- **DAG Integrity Violation**: Page on-call if cycle detected or orphan count > 100
- **STAC Minting Stall**: Alert if no mints in 5 minutes (indicates pipeline blockage)

---

## 13. MVP Cut (2 Sprints, ~4 Weeks)

### Sprint 1: Foundational Plumbing (Weeks 1-2)
**Goal**: Thunderbit → Decode → Assemble → PAC → DAG (no rewards yet)

**Deliverables**:
1. Ash Resources: `Thunderbit`, `KnowledgeItem`, `DAGNode`, `DAGEdge`
2. Oban Workers: `DecodeThunderbit`, `AssembleKI`, `ValidateWithPAC`, `CommitToDAG`
3. PAC Validator: Implement 4/6 checks (Integrity, Ownership, Cost, Novelty - skip Relevance, Policy for MVP)
4. Event Publishing: Wire up `system.forge.*`, `system.pac.*`, `system.block.*` events
5. Basic Telemetry: Emit latency metrics for each worker
6. GraphQL Queries: `knowledgeItem(id)`, `knowledgeItems(filter)`, `dagNode(id)`

**Test Scenarios**:
- Ingest 100 Thunderbits (heart rate sensor)
- Decode all successfully
- Assemble 10 KIs (5 pass PAC, 5 fail novelty)
- Commit 5 nodes to DAG
- Query DAG via GraphQL

### Sprint 2: Reward Mechanics (Weeks 3-4)
**Goal**: STAC minting + basic staking (no STACC yet)

**Deliverables**:
1. Ash Resources: `STACReward`, `StakeRecord`
2. Oban Worker: `MintSTAC`
3. Reward Calculator: Implement Q(ki), N(ki), S(owner) functions (P=1.0 for MVP)
4. Staking Manager: `stake/2`, `unstake/2` functions (no yield calculation yet)
5. GraphQL Mutations: `stakeSTAC`, `unstakeSTAC`
6. GraphQL Queries: `stacRewards`, `myStakeRecords`
7. Anti-Sybil: Implement novelty decay + cost budget
8. Event Publishing: `system.rewards.stac_minted`, `system.rewards.stac_staked`

**Test Scenarios**:
- Mint STAC for 5 committed KIs
- Verify reward amounts vary by quality/novelty scores
- Stake 100 STAC, unstake 50 STAC
- Query stake records and verify multipliers apply

### Post-MVP (Future Sprints)
- Yield calculation + STACC issuance
- Full PAC checks (Relevance via embedding search, Policy via Crown integration)
- Federation via ActivityPub
- Advanced anti-sybil (collusion detection)
- Rate card system (dynamic pricing based on demand)

---

## 14. End-to-End Example

### Scenario: Heart Rate Sensor → STAC Mint → Stake → Yield

**Step 1: Device Emits Thunderbits**
```elixir
# On Nerves device
{:ok, thunderbit} = Thunderline.Thunderforge.ingest_thunderbit(%{
  sensor_id: "heart_rate_001",
  timestamp: ~U[2025-10-21 14:00:00Z],
  payload: %{bpm: 72, quality: "high"},
  signature: <<...>>,  # ECDSA signature
  schema_version: "1.0"
})
# Enqueued to :forge_decode
```

**Step 2: Decode Worker Processes**
```elixir
# Oban worker validates signature and decodes
{:ok, decoded} = HeartRateDecoder.decode(thunderbit.payload)
# Publishes: "system.forge.bit_decoded"
# decoded: %{bpm: 72, quality: "high", sensor_type: "heart_rate"}
```

**Step 3: Assembly Worker Finds Pattern**
```elixir
# After 3 heart rate bits in 5-minute window:
{:ok, ki_candidate} = PatternMatcher.match([bit1, bit2, bit3])
# ki_candidate.type = :observation
# ki_candidate.content = %{phenomenon: "resting_heart_rate", avg_bpm: 71.3, ...}
# Enqueued to :pac_validate
```

**Step 4: PAC Validation**
```elixir
# Six checks executed:
# - Integrity: ✓ (all signatures valid)
# - Ownership: ✓ (sensor owned by user_123)
# - Cost: ✓ (within daily quota)
# - Novelty: ✓ (N=0.85, no similar observation in 24h)
# - Relevance: ✓ (matches user goal "improve heart health")
# - Policy: ✓ (Crown allows health observations)
# Result: PASS
# Publishes: "system.pac.validated"
# Enqueued to :dag_commit
```

**Step 5: DAG Commit**
```elixir
# Create node linked to previous observations
{:ok, node} = DAGEngine.commit_node(ki_candidate)
# node.id = "550e8400-e29b-41d4-a716-446655440000"
# node.dag_depth = 42 (this is the 42nd node in user's DAG)
# Publishes: "system.block.dag_committed"
# Enqueued to :reward_mint
```

**Step 6: STAC Minting**
```elixir
# Calculate reward:
# B = 1.0 (base rate for observations)
# Q = 0.95 (high quality sensor)
# N = 0.85 (good novelty)
# P = 1.0 (policy compliant)
# S = 1.2 (user has 150 sSTAC staked)
# R = 1.0 * 0.95 * 0.85 * 1.0 * 1.2 = 0.969 STAC

{:ok, reward} = STACMinter.mint(ki_candidate, amount: 0.969)
# Publishes: "system.rewards.stac_minted"
# user_123 wallet += 0.969 STAC
```

**Step 7: User Stakes STAC**
```elixir
# User locks 100 STAC for 180 days
{:ok, stake} = StakeManager.stake(user_id: "user_123", amount: 100.0, lock_period_days: 180)
# Receives 100 sSTAC
# Future KI rewards now get S=1.2 multiplier
```

**Step 8: Yield Accrual (After 180 Days)**
```elixir
# User claims yield
{:ok, claim} = YieldCalculator.claim_yield(stake.id)
# claim.sSTAC_burned = 100.0
# claim.STACC_minted = 103.0 (3% yield for 6-month lock + 10% base APY prorated)
# User can sell 103 STACC on secondary market
```

---

## 15. Anti-Grief Patterns

### Novelty Decay
```elixir
# Repeated similar KIs earn exponentially less
def calculate_novelty_decay(ki, history) do
  similar_count = count_similar_in_window(ki, history, days: 7)
  decay_factor = :math.exp(-0.5 * similar_count)
  
  # First similar KI: N=1.0
  # Second similar KI: N=0.6
  # Third similar KI: N=0.36
  # Fourth similar KI: N=0.22
  # Eventually asymptotes to zero
  decay_factor
end
```

### Collusion Detector (Future)
```elixir
def detect_collusion(kis) do
  # Cluster KIs by embedding similarity
  clusters = cluster_by_embedding(kis, threshold: 0.9)
  
  # Flag clusters with >5 KIs from different owners submitted within 1 hour
  Enum.filter(clusters, fn cluster ->
    unique_owners = Enum.uniq_by(cluster, & &1.owner_id) |> length()
    time_spread = time_diff(List.first(cluster), List.last(cluster), :minutes)
    
    unique_owners > 5 and time_spread < 60
  end)
end
```

### Rate Cards (Future)
```elixir
def calculate_dynamic_rate(ki_type, current_demand) do
  base_rate = base_rate_for_type(ki_type)
  demand_multiplier = cond do
    current_demand > 1000 -> 0.5  # High demand = lower rewards (anti-spam)
    current_demand > 500 -> 0.75
    current_demand > 100 -> 1.0
    true -> 1.5  # Low demand = higher rewards (incentivize)
  end
  
  base_rate * demand_multiplier
end
```

---

## 16. Pitch: "Experience Becomes Computable"

**The Problem**: Your daily experiences—walks, meals, conversations, sleep—generate data via sensors, but that data just sits in silos earning nothing. You create knowledge, but you don't own it.

**The Solution**: Thunderline transforms raw sensor data into **validated, tokenized knowledge** that earns you STAC rewards. Your lived experience becomes a computational asset.

**How It Works**:
1. **Nerves devices** on your person emit **Thunderbits** (signed sensor packets)
2. **Thunderforge** decodes and assembles bits into **Knowledge Items** (observations, milestones, metrics)
3. **PAC validation** ensures quality (relevance, novelty, integrity)
4. **Thunderblock** commits KIs to a persistent **DAG** (your personal knowledge graph)
5. **STAC rewards** are minted based on quality, novelty, and your stake
6. **Stake STAC** to earn yield (sSTAC → STACC) and boost future rewards

**The Vision**: A world where your quantified self isn't just data—it's **computable knowledge** with economic value. You control it, you earn from it, and you govern its future through DAO participation.

**Tagline**: *"Your experience. Your knowledge. Your rewards."*

---

## Status & Next Steps

**Current State**: Specification complete, ready for implementation (HC-24 action item)

**Owners**: Forge + Bolt + Block Stewards

**Priority**: P1 (Post-launch hardening, gates M2-KNOWLEDGE-ECONOMY milestone)

**Next Actions**:
1. Review spec with team (estimate: 1 sprint kickoff meeting)
2. Scaffold Ash resources (Sprint 1, Week 1)
3. Implement Oban workers (Sprint 1, Week 2)
4. Wire up GraphQL schema (Sprint 2, Week 3)
5. Integration testing with mock Nerves device (Sprint 2, Week 4)
6. Production rollout behind `features.sensor_to_stac` flag (Sprint 3)

**Related Documentation**:
- [Thundra & Nerves Integration](../THUNDERLINE_MASTER_PLAYBOOK.md#thundra--nerves-integration-hc-23-high-command-directive) (edge runtime)
- [Event Taxonomy](../EVENT_TAXONOMY.md) (canonical event names)
- [Error Classes](../ERROR_CLASSES.md) (error handling patterns)
- [Feature Flags](../FEATURE_FLAGS.md) (rollout control)
