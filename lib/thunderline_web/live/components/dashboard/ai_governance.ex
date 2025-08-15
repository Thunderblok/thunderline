defmodule ThunderlineWeb.DashboardComponents.AiGovernance do
  use Phoenix.Component

  attr :governance_data, :map, required: true

  def ai_governance_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">🧠</div>
        <h3 class="text-lg font-bold text-white">AI Governance</h3>
      </div>

      <div class="space-y-4 flex-1">
        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="flex items-center justify-between mb-3">
            <span class="text-sm text-gray-300">Governance Status</span>
            <div class={[
              "px-2 py-1 text-xs rounded-full",
              governance_status_class(@governance_data.status)
            ]}>
              {String.upcase(@governance_data.status)}
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div class="text-center">
              <div class="text-xl font-bold text-cyan-300">
                {@governance_data.active_policies}
              </div>
              <div class="text-xs text-gray-400">Policies</div>
            </div>
            <div class="text-center">
              <div class="text-xl font-bold text-purple-300">
                {@governance_data.compliance_score}%
              </div>
              <div class="text-xs text-gray-400">Compliance</div>
            </div>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Policy Violations</div>
          <div class="space-y-2 max-h-32 overflow-y-auto">
            <%= for violation <- @governance_data.recent_violations do %>
              <div class="flex items-center justify-between p-2 bg-black/20 rounded">
                <div class="flex items-center space-x-2">
                  <div class={[
                    "w-2 h-2 rounded-full",
                    severity_indicator_class(violation.severity)
                  ]}>
                  </div>
                  <span class="text-xs text-gray-300 truncate">{violation.policy}</span>
                </div>
                <div class="flex items-center space-x-2">
                  <span class="text-xs text-gray-400">{violation.agent}</span>
                  <span class={[
                    "text-xs px-1 py-0.5 rounded",
                    severity_class(violation.severity)
                  ]}>
                    {violation.severity}
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-3">Agent Oversight</div>
          <div class="space-y-2">
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Monitored Agents</span>
              <span class="text-blue-300">{@governance_data.monitored_agents}</span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Audit Trail Events</span>
              <span class="text-green-300">{@governance_data.audit_events}</span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Risk Assessment</span>
              <span class={[
                risk_color(@governance_data.risk_level)
              ]}>
                {String.upcase(@governance_data.risk_level)}
              </span>
            </div>
          </div>
        </div>

        <div class="bg-black/20 backdrop-blur-sm rounded-lg p-3">
          <div class="text-sm text-gray-300 mb-2">Decision Transparency</div>
          <div class="space-y-1">
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Explainable Decisions</span>
              <span class="text-cyan-300">{@governance_data.explainable_percentage}%</span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Human Oversight</span>
              <span class="text-purple-300">{@governance_data.human_oversight_percentage}%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp governance_status_class("compliant"),
    do: "bg-green-500/20 text-green-300 border border-green-500/30"

  defp governance_status_class("monitoring"),
    do: "bg-blue-500/20 text-blue-300 border border-blue-500/30"

  defp governance_status_class("violation"),
    do: "bg-red-500/20 text-red-300 border border-red-500/30"

  defp governance_status_class("review"),
    do: "bg-yellow-500/20 text-yellow-300 border border-yellow-500/30"

  defp governance_status_class(_), do: "bg-gray-500/20 text-gray-300 border border-gray-500/30"

  defp severity_indicator_class("critical"), do: "bg-red-400 animate-pulse"
  defp severity_indicator_class("high"), do: "bg-orange-400"
  defp severity_indicator_class("medium"), do: "bg-yellow-400"
  defp severity_indicator_class("low"), do: "bg-green-400"
  defp severity_indicator_class(_), do: "bg-gray-400"

  defp severity_class("critical"), do: "bg-red-500/20 text-red-300"
  defp severity_class("high"), do: "bg-orange-500/20 text-orange-300"
  defp severity_class("medium"), do: "bg-yellow-500/20 text-yellow-300"
  defp severity_class("low"), do: "bg-green-500/20 text-green-300"
  defp severity_class(_), do: "bg-gray-500/20 text-gray-300"

  defp risk_color("low"), do: "text-green-300"
  defp risk_color("medium"), do: "text-yellow-300"
  defp risk_color("high"), do: "text-orange-300"
  defp risk_color("critical"), do: "text-red-300"
  defp risk_color(_), do: "text-gray-300"
end
