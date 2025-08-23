defmodule RubberDuck.Preferences.InheritanceTracker do
  @moduledoc """
  Tracks preference inheritance and source attribution for debugging and auditing.

  Provides detailed information about where each preference value comes from
  in the resolution hierarchy and enables debugging of complex inheritance scenarios.
  """

  require Logger

  alias RubberDuck.Preferences.Resources.{
    ProjectPreference,
    ProjectPreferenceEnabled,
    SystemDefault,
    UserPreference
  }

  @type preference_source :: :system_default | :user_preference | :project_preference
  @type source_info :: %{
          source: preference_source(),
          value: any(),
          source_details: map(),
          resolved_at: DateTime.t()
        }

  @doc """
  Track the source of a preference resolution for debugging.
  """
  @spec track_source(
          user_id :: binary(),
          preference_key :: String.t(),
          project_id :: binary() | nil
        ) ::
          {preference_source(), map()}
  def track_source(user_id, preference_key, project_id \\ nil) do
    # Check project preference first if enabled
    if project_id && project_overrides_enabled?(project_id) do
      case get_project_preference_details(project_id, preference_key) do
        {:ok, details} ->
          {:project_preference, details}

        {:error, :not_found} ->
          track_user_or_system_source(user_id, preference_key)
      end
    else
      track_user_or_system_source(user_id, preference_key)
    end
  end

  @doc """
  Record a preference resolution for analytics and debugging.
  """
  @spec record_resolution(
          user_id :: binary(),
          preference_key :: String.t(),
          project_id :: binary() | nil,
          preference_source()
        ) :: :ok
  def record_resolution(user_id, preference_key, project_id, source) do
    # Emit telemetry event for analytics
    :telemetry.execute(
      [:rubber_duck, :preferences, :resolution],
      %{count: 1},
      %{
        user_id: user_id,
        preference_key: preference_key,
        project_id: project_id,
        source: source
      }
    )

    Logger.debug("Preference resolved: #{preference_key} for user #{user_id} from #{source}")
    :ok
  end

  @doc """
  Get inheritance chain for a preference showing full resolution path.
  """
  @spec get_inheritance_chain(
          user_id :: binary(),
          preference_key :: String.t(),
          project_id :: binary() | nil
        ) ::
          [source_info()]
  def get_inheritance_chain(user_id, preference_key, project_id \\ nil) do
    chain = []

    # System default (always exists as base)
    chain = chain ++ [get_system_default_info(preference_key)]

    # User preference (if exists)
    chain =
      case get_user_preference_details(user_id, preference_key) do
        {:ok, user_info} -> chain ++ [user_info]
        {:error, :not_found} -> chain
      end

    # Project preference (if exists and enabled)
    final_chain =
      if project_id && project_overrides_enabled?(project_id) do
        case get_project_preference_details(project_id, preference_key) do
          {:ok, project_info} -> chain ++ [project_info]
          {:error, :not_found} -> chain
        end
      else
        chain
      end

    # Filter out nil entries and sort by precedence
    final_chain
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&source_precedence(&1.source))
  end

  @doc """
  Analyze inheritance patterns for a user across all preferences.
  """
  @spec analyze_user_inheritance(user_id :: binary(), project_id :: binary() | nil) :: %{
          total_preferences: non_neg_integer(),
          system_defaults: non_neg_integer(),
          user_overrides: non_neg_integer(),
          project_overrides: non_neg_integer(),
          override_percentage: float()
        }
  def analyze_user_inheritance(user_id, project_id \\ nil) do
    all_preferences = get_all_preference_keys()

    sources =
      all_preferences
      |> Enum.map(&track_source(user_id, &1, project_id))
      |> Enum.group_by(fn {source, _} -> source end)

    system_count = length(Map.get(sources, :system_default, []))
    user_count = length(Map.get(sources, :user_preference, []))
    project_count = length(Map.get(sources, :project_preference, []))
    total = length(all_preferences)

    %{
      total_preferences: total,
      system_defaults: system_count,
      user_overrides: user_count,
      project_overrides: project_count,
      override_percentage:
        if(total > 0, do: (user_count + project_count) / total * 100, else: 0.0)
    }
  end

  @doc """
  Get category-level inheritance statistics.
  """
  @spec get_category_inheritance(
          user_id :: binary(),
          category :: String.t(),
          project_id :: binary() | nil
        ) :: map()
  def get_category_inheritance(user_id, category, project_id \\ nil) do
    case get_preferences_in_category(category) do
      {:ok, preference_keys} ->
        sources =
          preference_keys
          |> Enum.map(&track_source(user_id, &1, project_id))
          |> Enum.group_by(fn {source, _} -> source end)

        %{
          category: category,
          total_preferences: length(preference_keys),
          sources: sources,
          override_count:
            length(Map.get(sources, :user_preference, [])) +
              length(Map.get(sources, :project_preference, []))
        }

      {:error, _} ->
        %{category: category, error: "Category not found"}
    end
  end

  # Private functions

  defp track_user_or_system_source(user_id, preference_key) do
    case get_user_preference_details(user_id, preference_key) do
      {:ok, details} ->
        {:user_preference, details}

      {:error, :not_found} ->
        case get_system_default_info(preference_key) do
          nil -> {:system_default, %{error: "not_found"}}
          info -> {:system_default, info}
        end
    end
  end

  defp project_overrides_enabled?(project_id) do
    case ProjectPreferenceEnabled.by_project(project_id) do
      {:ok, [%{enabled: true}]} -> true
      _ -> false
    end
  end

  defp get_project_preference_details(project_id, preference_key) do
    case ProjectPreference.by_project(project_id) do
      {:ok, preferences} ->
        case Enum.find(preferences, &(&1.preference_key == preference_key)) do
          %{} = pref ->
            {:ok,
             %{
               source: :project_preference,
               value: pref.value,
               source_details: %{
                 project_id: project_id,
                 approved_by: pref.approved_by,
                 approved_at: pref.approved_at,
                 override_reason: pref.override_reason,
                 temporary: pref.temporary,
                 effective_until: pref.effective_until
               },
               resolved_at: DateTime.utc_now()
             }}

          nil ->
            {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp get_user_preference_details(user_id, preference_key) do
    case UserPreference.by_user(user_id) do
      {:ok, preferences} ->
        case Enum.find(preferences, &(&1.preference_key == preference_key)) do
          %{} = pref ->
            {:ok,
             %{
               source: :user_preference,
               value: pref.value,
               source_details: %{
                 user_id: user_id,
                 last_modified: pref.last_modified,
                 source: pref.source,
                 modified_by: pref.modified_by,
                 notes: pref.notes
               },
               resolved_at: DateTime.utc_now()
             }}

          nil ->
            {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp get_system_default_info(preference_key) do
    case SystemDefault.read() do
      {:ok, defaults} ->
        case Enum.find(defaults, &(&1.preference_key == preference_key && !&1.deprecated)) do
          %{} = default ->
            %{
              source: :system_default,
              value: default.default_value,
              source_details: %{
                category: default.category,
                subcategory: default.subcategory,
                data_type: default.data_type,
                version: default.version,
                description: default.description
              },
              resolved_at: DateTime.utc_now()
            }

          nil ->
            nil
        end

      {:error, _} ->
        nil
    end
  end

  defp get_all_preference_keys do
    case SystemDefault.non_deprecated() do
      {:ok, defaults} -> Enum.map(defaults, & &1.preference_key)
      {:error, _} -> []
    end
  end

  defp get_preferences_in_category(category) do
    case SystemDefault.by_category(category) do
      {:ok, defaults} -> {:ok, Enum.map(defaults, & &1.preference_key)}
      error -> error
    end
  end

  # Define precedence order for inheritance chain sorting
  defp source_precedence(:system_default), do: 1
  defp source_precedence(:user_preference), do: 2
  defp source_precedence(:project_preference), do: 3
end
