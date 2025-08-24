defmodule RubberDuckWeb.API.FallbackController do
  @moduledoc """
  Translates controller action results into valid HTTP responses.

  Handles common error cases and formats them as JSON responses.
  """

  use RubberDuckWeb, :controller

  # Handle authentication errors
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: %{
        code: "unauthorized",
        message: "Authentication required",
        details: "You must be authenticated to access this resource"
      }
    })
  end

  # Handle authorization errors
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{
        code: "forbidden",
        message: "Insufficient permissions",
        details: "You don't have permission to access this resource"
      }
    })
  end

  # Handle not found errors
  def call(conn, {:error, %{field: :not_found, message: message}}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: %{
        code: "not_found",
        message: message || "Resource not found",
        details: "The requested resource could not be found"
      }
    })
  end

  # Handle validation errors
  def call(conn, {:error, %{field: :validation_error, message: message, details: details}}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        code: "validation_error",
        message: message || "Validation failed",
        details: details
      }
    })
  end

  def call(conn, {:error, %{field: :validation_error, message: message}}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        code: "validation_error",
        message: message || "Validation failed"
      }
    })
  end

  # Handle rate limiting
  def call(conn, {:error, :rate_limited}) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", "60")
    |> json(%{
      error: %{
        code: "rate_limited",
        message: "Too many requests",
        details: "Please wait before making another request"
      }
    })
  end

  # Handle not implemented features
  def call(conn, {:error, %{field: :not_implemented, message: message}}) do
    conn
    |> put_status(:not_implemented)
    |> json(%{
      error: %{
        code: "not_implemented",
        message: message || "Feature not implemented",
        details: "This feature is not yet available"
      }
    })
  end

  # Handle Ash errors (when available)
  def call(conn, {:error, error}) when is_struct(error) do
    # Generic struct error handling for Ash errors
    error_type = error.__struct__

    {status, code, message} =
      case to_string(error_type) do
        "Elixir.Ash.Error.Invalid" -> {:bad_request, "invalid_request", "Invalid request data"}
        "Elixir.Ash.Error.Query" -> {:bad_request, "query_error", "Query execution failed"}
        "Elixir.Ash.Error.Forbidden" -> {:forbidden, "forbidden", "Access denied"}
        _ -> {:internal_server_error, "internal_error", "An error occurred"}
      end

    conn
    |> put_status(status)
    |> json(%{
      error: %{
        code: code,
        message: message,
        details: format_struct_errors(error)
      }
    })
  end

  # Handle Ecto changeset errors
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "Validation failed",
        details: format_changeset_errors(changeset)
      }
    })
  end

  # Handle generic string errors
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      error: %{
        code: "internal_error",
        message: reason
      }
    })
  end

  # Handle generic atom errors
  def call(conn, {:error, reason}) when is_atom(reason) do
    message =
      case reason do
        :not_found -> "Resource not found"
        :invalid -> "Invalid request"
        :timeout -> "Request timeout"
        _ -> "An error occurred"
      end

    status =
      case reason do
        :not_found -> :not_found
        :invalid -> :bad_request
        :timeout -> :request_timeout
        _ -> :internal_server_error
      end

    conn
    |> put_status(status)
    |> json(%{
      error: %{
        code: to_string(reason),
        message: message
      }
    })
  end

  # Catch-all for unexpected errors
  def call(conn, error) do
    # Log the unexpected error for debugging
    require Logger
    Logger.error("Unexpected API error: #{inspect(error)}")

    conn
    |> put_status(:internal_server_error)
    |> json(%{
      error: %{
        code: "internal_error",
        message: "An unexpected error occurred"
      }
    })
  end

  # Private helper functions

  defp format_ash_errors(errors) do
    errors
    |> Enum.map(fn error ->
      %{
        field: Map.get(error, :field),
        message: Map.get(error, :message),
        code: Map.get(error, :code)
      }
    end)
  end

  defp format_struct_errors(error) do
    case Map.get(error, :errors) do
      nil -> to_string(error)
      errors when is_list(errors) -> format_ash_errors(errors)
      errors -> inspect(errors)
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
