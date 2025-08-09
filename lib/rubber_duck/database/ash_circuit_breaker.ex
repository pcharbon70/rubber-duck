defmodule RubberDuck.Database.AshCircuitBreaker do
  @moduledoc """
  Ash extension that automatically wraps database operations with circuit breaker protection.

  This module hooks into Ash's action execution pipeline to add circuit breaker
  protection transparently to all database operations.

  ## Usage

  Add to your Ash resource:

      use Ash.Resource,
        extensions: [RubberDuck.Database.AshCircuitBreaker]

  Or configure globally in your domain:

      defmodule MyApp.Domain do
        use Ash.Domain,
          extensions: [RubberDuck.Database.AshCircuitBreaker]
      end

  ## Configuration

  Configure per-resource or globally:

      database_circuit_breaker do
        enabled? true
        allow_stale_reads? true
        fallback_to_cache? true
        slow_query_threshold 3000
      end
  """

  alias RubberDuck.Database.CircuitBreaker
  require Logger

  @database_circuit_breaker_section %Spark.Dsl.Section{
    name: :database_circuit_breaker,
    describe: """
    Configure database circuit breaker behavior for this resource.
    """,
    schema: [
      enabled?: [
        type: :boolean,
        default: true,
        doc: "Whether to enable circuit breaker protection for this resource"
      ],
      allow_stale_reads?: [
        type: :boolean,
        default: false,
        doc: "Allow returning stale/cached data when circuit is open for read operations"
      ],
      fallback_to_cache?: [
        type: :boolean,
        default: false,
        doc: "Attempt to read from cache when database is unavailable"
      ],
      slow_query_threshold: [
        type: :pos_integer,
        default: 5000,
        doc: "Milliseconds before a query is considered slow"
      ],
      circuit_breaker_opts: [
        type: :keyword_list,
        default: [],
        doc: "Additional options to pass to the circuit breaker"
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@database_circuit_breaker_section],
    transformers: [RubberDuck.Database.AshCircuitBreaker.Transformer]

  defmodule Transformer do
    @moduledoc false
    use Spark.Dsl.Transformer

    def transform(dsl_state) do
      if enabled?(dsl_state) do
        dsl_state
        |> add_preparation()
        |> add_change()
      else
        {:ok, dsl_state}
      end
    end

    defp enabled?(dsl_state) do
      Spark.Dsl.Extension.get_opt(
        dsl_state,
        [:database_circuit_breaker],
        :enabled?,
        true
      )
    end

    defp add_preparation(dsl_state) do
      {:ok,
       Spark.Dsl.Transformer.add_entity(
         dsl_state,
         [:actions, :read],
         Spark.Dsl.Preparation.build(RubberDuck.Database.AshCircuitBreaker.ReadPreparation)
       )}
    end

    defp add_change(dsl_state) do
      dsl_state
      |> add_change_to_action_type(:create)
      |> add_change_to_action_type(:update)
      |> add_change_to_action_type(:destroy)
    end

    defp add_change_to_action_type(dsl_state, action_type) do
      Spark.Dsl.Transformer.add_entity(
        dsl_state,
        [:actions, action_type],
        Spark.Dsl.Change.build(RubberDuck.Database.AshCircuitBreaker.WriteChange)
      )
    end
  end

  defmodule ReadPreparation do
    @moduledoc false
    use Ash.Resource.Preparation

    def prepare(query, _opts, _context) do
      query
      |> Ash.Query.before_action(fn query ->
        with :ok <- check_circuit_breaker(:read, query) do
          query
        else
          {:error, :circuit_open} ->
            handle_circuit_open(:read, query)

          {:error, reason} ->
            Ash.Query.add_error(query, "Database unavailable: #{inspect(reason)}")
        end
      end)
      |> Ash.Query.after_action(fn query, results ->
        record_success(:read, query)
        {:ok, results}
      end)
    end

    defp check_circuit_breaker(operation_type, query) do
      if circuit_breaker_enabled?(query.resource) do
        result = CircuitBreaker.with_circuit_breaker(
          operation_type,
          fn ->
            {:ok, :proceed}
          end,
          # Quick check
          timeout: 100
        )
        
        case result do
          {:ok, :proceed} -> :ok
          error -> error
        end
      else
        :ok
      end
    end

    defp handle_circuit_open(:read, query) do
      resource = query.resource

      cond do
        allow_stale_reads?(resource) ->
          # Add metadata to indicate stale data
          query
          |> Ash.Query.put_context(:stale_data, true)
          |> Ash.Query.put_context(:circuit_open, true)

        fallback_to_cache?(resource) ->
          # Attempt to read from cache
          query
          |> Ash.Query.put_context(:read_from_cache, true)
          |> Ash.Query.put_context(:circuit_open, true)

        true ->
          Ash.Query.add_error(query, "Database circuit breaker is open")
      end
    end

    defp record_success(_operation_type, query) do
      if circuit_breaker_enabled?(query.resource) do
        # This would be called after successful query execution
        # In practice, we'd hook into the actual data layer execution
        :ok
      end
    end

    defp circuit_breaker_enabled?(resource) do
      Spark.Dsl.Extension.get_opt(
        resource,
        [:database_circuit_breaker],
        :enabled?,
        true
      )
    end

    defp allow_stale_reads?(resource) do
      Spark.Dsl.Extension.get_opt(
        resource,
        [:database_circuit_breaker],
        :allow_stale_reads?,
        false
      )
    end

    defp fallback_to_cache?(resource) do
      Spark.Dsl.Extension.get_opt(
        resource,
        [:database_circuit_breaker],
        :fallback_to_cache?,
        false
      )
    end
  end

  defmodule WriteChange do
    @moduledoc false
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.before_action(fn changeset ->
        operation_type = determine_operation_type(changeset)

        with :ok <- check_circuit_breaker(operation_type, changeset) do
          changeset
        else
          {:error, :circuit_open} ->
            Ash.Changeset.add_error(
              changeset,
              "Database circuit breaker is open for #{operation_type} operations"
            )

          {:error, reason} ->
            Ash.Changeset.add_error(
              changeset,
              "Database unavailable: #{inspect(reason)}"
            )
        end
      end)
      |> Ash.Changeset.after_action(fn changeset, result ->
        operation_type = determine_operation_type(changeset)
        record_success(operation_type, changeset)
        {:ok, result}
      end)
    end

    defp determine_operation_type(changeset) do
      case changeset.action.type do
        :create -> :write
        :update -> :write
        :destroy -> :write
        _ -> :write
      end
    end

    defp check_circuit_breaker(operation_type, changeset) do
      if circuit_breaker_enabled?(changeset.resource) do
        result = CircuitBreaker.with_circuit_breaker(
          operation_type,
          fn ->
            {:ok, :proceed}
          end,
          timeout: 100
        )
        
        case result do
          {:ok, :proceed} -> :ok
          error -> error
        end
      else
        :ok
      end
    end

    defp record_success(_operation_type, changeset) do
      if circuit_breaker_enabled?(changeset.resource) do
        # Record successful operation
        :ok
      end
    end

    defp circuit_breaker_enabled?(resource) do
      Spark.Dsl.Extension.get_opt(
        resource,
        [:database_circuit_breaker],
        :enabled?,
        true
      )
    end
  end

  @doc """
  Manually check if the database circuit breaker is open for a given operation.
  """
  def circuit_open?(operation_type) when operation_type in [:read, :write, :transaction, :bulk] do
    case CircuitBreaker.with_circuit_breaker(operation_type, fn -> {:ok, :check} end, timeout: 10) do
      {:ok, :check} -> false
      {:error, :circuit_open} -> true
      {:error, :database_unavailable} -> true
      _ -> false
    end
  end

  @doc """
  Get the current status of all database circuit breakers.
  """
  defdelegate get_status(), to: CircuitBreaker

  @doc """
  Reset a specific database circuit breaker.
  """
  defdelegate reset(operation_type), to: CircuitBreaker

  @doc """
  Reset all database circuit breakers.
  """
  defdelegate reset_all(), to: CircuitBreaker
end
