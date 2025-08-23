defmodule Thunderline.Thundergate.Domain do
  @moduledoc """
  ThunderGate Ash Domain - Security & Policy Enforcement

  **Boundary**: "Gate permits" - AuthZ/N, rate limiting, API boundaries, policy enforcement, security monitoring

  Consolidated from: ThunderStone (policy management), ThunderEye (observability/monitoring)

  Core responsibilities:
  - Authentication and authorization
  - Rate limiting and API boundary controls
  - Policy enforcement and decision frameworks
  - Security monitoring and observability
  - Audit logging and performance tracking
  - Error monitoring and health checks
  - System action tracking and alerting
  - External API integration and management
  - Data transformation and adaptation
  - Cross-domain federation and communication
  - Protocol translation and standardization
  - Cross-realm identity management and trust
  - Federated message routing and security
  """

  use Ash.Domain

  resources do
    # Accounts → ThunderGate (authentication/security)
    resource Thunderline.Thundergate.Resources.User
    resource Thunderline.Thundergate.Resources.Token

    # Original ThunderGate resources
    resource Thunderline.Thundergate.Resources.ExternalService
    resource Thunderline.Thundergate.Resources.DataAdapter
    resource Thunderline.Thundergate.Resources.FederatedRealm
    resource Thunderline.Thundergate.Resources.RealmIdentity
    resource Thunderline.Thundergate.Resources.FederatedMessage

    # ThunderStone → ThunderGate (policy enforcement)
    resource Thunderline.Thundergate.Resources.DecisionFramework
    resource Thunderline.Thundergate.Resources.PolicyRule

    # ThunderEye → ThunderGate (security monitoring)
    resource Thunderline.Thundergate.Resources.AlertRule
    resource Thunderline.Thundergate.Resources.AuditLog
    resource Thunderline.Thundergate.Resources.ErrorLog
    resource Thunderline.Thundergate.Resources.HealthCheck
    resource Thunderline.Thundergate.Resources.PerformanceTrace
    resource Thunderline.Thundergate.Resources.SystemAction
    resource Thunderline.Thundergate.Resources.SystemMetric
    resource Thunderline.Thundergate.Resources.ThunderbitMonitor
    resource Thunderline.Thundergate.Resources.ThunderboltMonitor


    # Commented out until implementation is available
    # resource Thundergate.Resources.WebhookEndpoint
    # resource Thundergate.Resources.SyncJob
    # resource Thundergate.Resources.FederationBridge
  end
end
