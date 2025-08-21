defmodule RubberDuck.Skills.UserManagementSkill do
  @moduledoc """
  User management skill with behavior learning and session management.

  Provides capabilities for managing user sessions, tracking preferences,
  and learning from user behavior patterns.
  """

  use Jido.Skill,
    name: "user_management_skill",
    opts_key: :user_management_state,
    signal_patterns: [
      "user.initialize_session",
      "user.update_activity",
      "user.save_preference",
      "user.get_session_info"
    ]

  alias RubberDuck.Accounts.User
  alias RubberDuck.Repo

  @doc """
  Initialize user session with behavioral tracking.
  """
  def initialize_session(%{user_id: user_id} = _params, state) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :user_not_found, state}

      user ->
        session_data = %{
          user_id: user_id,
          email: user.email,
          session_start: DateTime.utc_now(),
          activity_count: 0,
          last_seen: DateTime.utc_now()
        }

        new_state = Map.put(state, :session_data, session_data)
        {:ok, session_data, new_state}
    end
  end

  @doc """
  Update session activity and track patterns.
  """
  def update_session_activity(%{activity_type: activity_type} = _params, state) do
    session_data = Map.get(state, :session_data, %{})

    updated_session =
      session_data
      |> Map.put(:activity_count, Map.get(session_data, :activity_count, 0) + 1)
      |> Map.put(:last_seen, DateTime.utc_now())
      |> Map.put(:last_activity_type, activity_type)

    new_state = Map.put(state, :session_data, updated_session)

    {:ok, updated_session, new_state}
  end

  @doc """
  Save user preferences.
  """
  def save_preference(%{key: key, value: value} = _params, state) do
    current_preferences = Map.get(state, :preferences, %{})
    updated_preferences = Map.put(current_preferences, key, value)

    new_state = Map.put(state, :preferences, updated_preferences)

    {:ok, updated_preferences, new_state}
  end

  @doc """
  Get user session information.
  """
  def get_session_info(_params, state) do
    session_data = Map.get(state, :session_data, %{})
    {:ok, session_data, state}
  end
end
