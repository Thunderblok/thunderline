defmodule ThunderlineWeb.DashboardComponents.MemoryMetrics do
  use Phoenix.Component

  attr :metrics, :map, required: true

  def memory_metrics_panel(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex items-center space-x-3 mb-4">
        <div class="text-2xl">💾</div>
        <h3 class="text-lg font-bold text-white">Memory & Storage</h3>
      </div>

      <div class="space-y-4 flex-1">
        <div>
          <div class="text-sm text-gray-300 mb-2">ThunderMemory</div>
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex justify-between text-xs mb-1">
              <span class="text-gray-400">Used</span>
              <span class="text-blue-300">{@metrics[:thunder_memory][:used]}MB</span>
            </div>
            <div class="flex justify-between text-xs mb-1">
              <span class="text-gray-400">Hit Rate</span>
              <span class="text-green-300">
                {Float.round(@metrics[:thunder_memory][:hit_rate] * 100, 1)}%
              </span>
            </div>
          </div>
        </div>

        <div>
          <div class="text-sm text-gray-300 mb-2">Mnesia</div>
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex justify-between text-xs mb-1">
              <span class="text-gray-400">Tables</span>
              <span class="text-blue-300">{@metrics[:mnesia][:tables]}</span>
            </div>
            <div class="flex justify-between text-xs mb-1">
              <span class="text-gray-400">TPS</span>
              <span class="text-cyan-300">{@metrics[:mnesia][:transactions_per_sec]}</span>
            </div>
          </div>
        </div>

        <div>
          <div class="text-sm text-gray-300 mb-2">PostgreSQL</div>
          <div class="bg-black/20 rounded-lg p-3">
            <div class="flex justify-between text-xs mb-1">
              <span class="text-gray-400">Connections</span>
              <span class="text-purple-300">{@metrics[:postgresql][:connections]}</span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="text-gray-400">Query Time</span>
              <span class="text-yellow-300">
                {Float.round(@metrics[:postgresql][:query_time], 1)}ms
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
