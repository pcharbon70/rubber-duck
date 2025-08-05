defmodule RubberDuck.Agents do
  @moduledoc """
  Domain for agent state persistence and management.

  Provides operations for persisting and retrieving agent learnings,
  experiences, insights, and performance metrics across restarts.
  """

  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Agents.AgentState do
      define :create_agent_state, action: :create
      define :get_agent_state, action: :read, get_by: [:id]
      define :get_agent_state_by_name, action: :by_name, args: [:agent_name]
      define :update_agent_state, action: :update
      define :checkpoint_agent_state, action: :checkpoint
    end

    resource RubberDuck.Agents.AgentExperience do
      define :create_experience, action: :create
      define :list_experiences, action: :read
      define :prune_old_experiences, action: :prune
    end

    resource RubberDuck.Agents.AgentInsight do
      define :create_insight, action: :create
      define :list_insights, action: :read
      define :get_latest_insights, action: :latest
    end

    resource RubberDuck.Agents.ProviderPerformance do
      define :upsert_performance, action: :upsert
      define :get_performance, action: :read
      define :get_provider_performance, action: :by_provider
    end
  end
end
