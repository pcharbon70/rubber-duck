defmodule RubberDuckWeb.API.TemplatesJSON do
  @moduledoc """
  JSON views for the Templates API controller.
  """

  @doc """
  Renders a list of templates.
  """
  def index(%{templates: templates}) do
    %{
      data: for(template <- templates, do: data(template)),
      meta: %{
        total: length(templates),
        timestamp: DateTime.utc_now()
      }
    }
  end

  @doc """
  Renders a single template.
  """
  def show(%{template: template}) do
    %{
      data: data(template),
      meta: %{
        timestamp: DateTime.utc_now()
      }
    }
  end

  @doc """
  Renders template application results.
  """
  def apply_result(%{result: result}) do
    %{
      data: %{
        dry_run: result.dry_run,
        target_type: result.target_type,
        target_id: result.target_id,
        applied_count: result[:applied_count],
        skipped_count: result[:skipped_count],
        error_count: result[:error_count],
        changes_preview: result[:changes_preview],
        summary: result[:summary],
        errors: result[:errors] || []
      },
      meta: %{
        timestamp: DateTime.utc_now()
      }
    }
  end

  defp data(template) do
    %{
      id: template.template_id,
      name: template.name,
      description: template.description,
      category: template.category,
      type: template.template_type,
      created_by: template.created_by,
      preferences: template.preferences,
      metadata: %{
        rating: template[:rating],
        usage_count: template[:usage_count] || 0,
        preference_count: map_size(template.preferences || %{}),
        created_at: template[:created_at],
        updated_at: template[:updated_at]
      }
    }
  end
end
