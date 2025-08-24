defmodule RubberDuckWeb.API.PreferencesJSON do
  @moduledoc """
  JSON views for the Preferences API controller.
  """

  @doc """
  Renders a list of preferences.
  """
  def index(%{preferences: preferences}) do
    %{
      data: for(preference <- preferences, do: data(preference)),
      meta: %{
        total: length(preferences),
        timestamp: DateTime.utc_now()
      }
    }
  end

  @doc """
  Renders a single preference.
  """
  def show(%{preference: preference}) do
    %{
      data: data(preference),
      meta: %{
        timestamp: DateTime.utc_now()
      }
    }
  end

  @doc """
  Renders batch operation results.
  """
  def batch(%{results: results}) do
    %{
      data: %{
        total: results.total,
        successful: results.successful,
        failed: results.failed,
        results: Enum.map(results.results, &batch_result/1)
      },
      meta: %{
        timestamp: DateTime.utc_now()
      }
    }
  end

  defp data(preference) do
    base_data = %{
      id: preference.id,
      key: preference.key,
      value: preference.value,
      category: preference.category,
      source: preference.source,
      data_type: preference[:data_type],
      description: preference[:description],
      default_value: preference[:default_value]
    }

    # Add optional fields if present
    base_data
    |> add_if_present(:constraints, preference[:constraints])
    |> add_if_present(:last_modified, preference[:last_modified])
    |> add_if_present(:inheritance, preference[:inheritance])
  end

  defp batch_result({:ok, result}) do
    %{
      status: "success",
      action: result.action,
      key: result.key,
      result: result.result
    }
  end

  defp batch_result({:error, error}) do
    %{
      status: "error",
      action: error.action,
      key: error.key,
      error: format_error(error.error)
    }
  end

  defp add_if_present(map, _key, nil), do: map
  defp add_if_present(map, key, value), do: Map.put(map, key, value)

  defp format_error({:error, reason}) when is_binary(reason), do: reason
  defp format_error(%{message: message}), do: message
  defp format_error(error), do: inspect(error)
end
