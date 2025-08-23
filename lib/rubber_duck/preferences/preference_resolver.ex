defmodule RubberDuck.Preferences.PreferenceResolver do
  @moduledoc """
  Core preference resolution engine implementing three-tier hierarchy.

  Resolves preferences in the following order:
  1. Project preferences (if project overrides enabled)
  2. User preferences  
  3. System defaults

  Provides high-performance cached resolution with real-time invalidation.
  """

  use GenServer
  require Logger

  alias RubberDuck.Preferences.{CacheManager, InheritanceTracker}

  alias RubberDuck.Preferences.Resources.{
    ProjectPreference,
    ProjectPreferenceEnabled,
    SystemDefault,
    UserPreference
  }

  @cache_table :preference_cache
  @default_cache_ttl :timer.minutes(30)

  # Public API

  @doc """
  Resolve a single preference for a user and optional project.

  Returns the effective value using hierarchical resolution:
  - Project preference (if enabled and exists)
  - User preference (if exists)  
  - System default
  """
  @spec resolve(user_id :: binary(), preference_key :: String.t(), project_id :: binary() | nil) ::
          {:ok, any()} | {:error, :not_found}
  def resolve(user_id, preference_key, project_id \\ nil) do
    cache_key = build_cache_key(user_id, preference_key, project_id)

    case CacheManager.get(@cache_table, cache_key) do
      {:ok, cached_value} ->
        {:ok, cached_value}

      {:error, :not_found} ->
        case resolve_uncached(user_id, preference_key, project_id) do
          {:ok, value} ->
            CacheManager.put(@cache_table, cache_key, value, @default_cache_ttl)
            {:ok, value}

          error ->
            error
        end
    end
  end

  @doc """
  Resolve multiple preferences in a single operation for efficiency.
  """
  @spec resolve_batch(
          user_id :: binary(),
          preference_keys :: [String.t()],
          project_id :: binary() | nil
        ) ::
          %{String.t() => any()}
  def resolve_batch(user_id, preference_keys, project_id \\ nil) do
    preference_keys
    |> Enum.map(fn key ->
      case resolve(user_id, key, project_id) do
        {:ok, value} -> {key, value}
        {:error, :not_found} -> {key, nil}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Get all effective preferences for a user and project.
  """
  @spec resolve_all(user_id :: binary(), project_id :: binary() | nil) :: %{String.t() => any()}
  def resolve_all(user_id, project_id \\ nil) do
    # Get all system defaults as base
    system_defaults = get_all_system_defaults()

    # Get user overrides
    user_overrides = get_user_preferences(user_id)

    # Get project overrides if enabled
    project_overrides =
      if project_id && project_overrides_enabled?(project_id) do
        get_project_preferences(project_id)
      else
        %{}
      end

    # Apply hierarchy: system <- user <- project
    system_defaults
    |> Map.merge(user_overrides)
    |> Map.merge(project_overrides)
  end

  @doc """
  Get preference source information for debugging and auditing.
  """
  @spec get_preference_source(
          user_id :: binary(),
          preference_key :: String.t(),
          project_id :: binary() | nil
        ) ::
          {:system_default | :user_preference | :project_preference, map()}
  def get_preference_source(user_id, preference_key, project_id \\ nil) do
    InheritanceTracker.track_source(user_id, preference_key, project_id)
  end

  @doc """
  Invalidate cache for specific preference or user.
  """
  @spec invalidate_cache(
          user_id :: binary(),
          preference_key :: String.t() | :all,
          project_id :: binary() | nil
        ) :: :ok
  def invalidate_cache(user_id, preference_key_or_all, project_id \\ nil) do
    case preference_key_or_all do
      :all ->
        CacheManager.invalidate_pattern(@cache_table, "#{user_id}:*")

      preference_key ->
        cache_key = build_cache_key(user_id, preference_key, project_id)
        CacheManager.invalidate(@cache_table, cache_key)
    end
  end

  # GenServer implementation

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize ETS cache table
    CacheManager.create_table(@cache_table, [:set, :public, :named_table])

    # Subscribe to preference change events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "preference_changes")

    Logger.info("PreferenceResolver started with cache table: #{@cache_table}")

    {:ok, %{}}
  end

  @impl true
  def handle_info({:preference_changed, user_id, preference_key, project_id}, state) do
    invalidate_cache(user_id, preference_key, project_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:user_preferences_reset, user_id}, state) do
    invalidate_cache(user_id, :all)
    {:noreply, state}
  end

  @impl true
  def handle_info({:project_overrides_toggled, project_id}, state) do
    # Invalidate all caches that might involve this project
    CacheManager.invalidate_pattern(@cache_table, "*:*:#{project_id}")
    {:noreply, state}
  end

  # Private functions

  defp resolve_uncached(user_id, preference_key, project_id) do
    # 1. Check project preference (if project overrides enabled)
    if project_id && project_overrides_enabled?(project_id) do
      case get_project_preference(project_id, preference_key) do
        {:ok, value} ->
          InheritanceTracker.record_resolution(
            user_id,
            preference_key,
            project_id,
            :project_preference
          )

          {:ok, parse_preference_value(value)}

        {:error, :not_found} ->
          resolve_user_or_system(user_id, preference_key, project_id)
      end
    else
      resolve_user_or_system(user_id, preference_key, project_id)
    end
  end

  defp resolve_user_or_system(user_id, preference_key, project_id) do
    # 2. Check user preference
    case get_user_preference(user_id, preference_key) do
      {:ok, value} ->
        InheritanceTracker.record_resolution(
          user_id,
          preference_key,
          project_id,
          :user_preference
        )

        {:ok, parse_preference_value(value)}

      {:error, :not_found} ->
        # 3. Fall back to system default
        case get_system_default(preference_key) do
          {:ok, value} ->
            InheritanceTracker.record_resolution(
              user_id,
              preference_key,
              project_id,
              :system_default
            )

            {:ok, parse_preference_value(value)}

          {:error, :not_found} ->
            Logger.warning("Preference not found: #{preference_key}")
            {:error, :not_found}
        end
    end
  end

  defp project_overrides_enabled?(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [%{enabled: true}]} -> true
      _ -> false
    end
  end

  defp get_project_preference(project_id, preference_key) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} ->
        case Enum.find(preferences, &(&1.preference_key == preference_key && &1.active)) do
          %{value: value} -> {:ok, value}
          nil -> {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp get_user_preference(user_id, preference_key) do
    case UserPreference.by_user(user_id) do
      {:ok, preferences} ->
        case Enum.find(preferences, &(&1.preference_key == preference_key && &1.active)) do
          %{value: value} -> {:ok, value}
          nil -> {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp get_system_default(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key && !&1.deprecated)) do
          %{default_value: value} -> {:ok, value}
          nil -> {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp get_all_system_defaults do
    case SystemDefault.non_deprecated() do
      {:ok, defaults} ->
        defaults
        |> Enum.map(&{&1.preference_key, parse_preference_value(&1.default_value)})
        |> Enum.into(%{})

      {:error, _} ->
        %{}
    end
  end

  defp get_user_preferences(user_id) do
    case UserPreference.by_user(user_id) do
      {:ok, preferences} ->
        preferences
        |> Enum.filter(& &1.active)
        |> Enum.map(&{&1.preference_key, parse_preference_value(&1.value)})
        |> Enum.into(%{})

      {:error, _} ->
        %{}
    end
  end

  defp get_project_preferences(project_id) do
    case ProjectPreference.active_for_project(project_id) do
      {:ok, preferences} ->
        preferences
        |> Enum.map(&{&1.preference_key, parse_preference_value(&1.value)})
        |> Enum.into(%{})

      {:error, _} ->
        %{}
    end
  end

  defp parse_preference_value(json_value) when is_binary(json_value) do
    case Jason.decode(json_value) do
      {:ok, value} -> value
      # Return as string if not valid JSON
      {:error, _} -> json_value
    end
  end

  defp parse_preference_value(value), do: value

  defp build_cache_key(user_id, preference_key, project_id) do
    "#{user_id}:#{preference_key}:#{project_id || "global"}"
  end
end
