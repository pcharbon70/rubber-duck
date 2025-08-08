defmodule RubberDuck.Database.ProtectedRepo do
  @moduledoc """
  A wrapper around RubberDuck.Repo that adds circuit breaker protection.

  This module provides the same interface as Ecto.Repo but wraps all database
  operations with circuit breaker logic to prevent cascading failures.

  ## Usage

  Replace direct Repo calls with ProtectedRepo:

      # Instead of:
      RubberDuck.Repo.get(User, id)
      
      # Use:
      RubberDuck.Database.ProtectedRepo.get(User, id)

  Or import and use directly:

      import RubberDuck.Database.ProtectedRepo
      
      get(User, id)
      insert(changeset)
  """

  alias RubberDuck.Database.CircuitBreaker
  alias RubberDuck.Repo

  require Logger

  # Delegate basic configuration to underlying Repo
  defdelegate config(), to: Repo
  defdelegate __adapter__(), to: Repo
  defdelegate start_link(opts \\ []), to: Repo
  defdelegate stop(timeout \\ 5000), to: Repo

  # Read Operations

  @doc """
  Fetches a single struct from the data store where the primary key matches the given id.
  Protected by read circuit breaker.
  """
  def get(queryable, id, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.get(queryable, id, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Similar to get/3 but raises Ecto.NoResultsError if no record was found.
  """
  def get!(queryable, id, opts \\ []) do
    case get(queryable, id, opts) do
      nil -> raise Ecto.NoResultsError, queryable: queryable
      result -> result
    end
  end

  @doc """
  Fetches a single result from the query.
  Protected by read circuit breaker.
  """
  def get_by(queryable, clauses, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.get_by(queryable, clauses, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Similar to get_by/3 but raises Ecto.NoResultsError if no record was found.
  """
  def get_by!(queryable, clauses, opts \\ []) do
    case get_by(queryable, clauses, opts) do
      nil -> raise Ecto.NoResultsError, queryable: queryable
      result -> result
    end
  end

  @doc """
  Fetches all entries from the data store matching the given query.
  Protected by read circuit breaker.
  """
  def all(queryable, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.all(queryable, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Returns true if there exists an entry that matches the given query.
  Protected by read circuit breaker.
  """
  def exists?(queryable, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.exists?(queryable, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Fetches a single result from the query.
  Protected by read circuit breaker.
  """
  def one(queryable, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.one(queryable, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Similar to one/2 but raises Ecto.NoResultsError if no record was found.
  """
  def one!(queryable, opts \\ []) do
    case one(queryable, opts) do
      nil -> raise Ecto.NoResultsError, queryable: queryable
      result -> result
    end
  end

  # Write Operations

  @doc """
  Inserts a struct or changeset.
  Protected by write circuit breaker.
  """
  def insert(struct_or_changeset, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :write,
      fn ->
        Repo.insert(struct_or_changeset, opts)
      end,
      opts
    )
    |> handle_changeset_result()
  end

  @doc """
  Same as insert/2 but returns the struct or raises if the changeset is invalid.
  """
  def insert!(struct_or_changeset, opts \\ []) do
    case insert(struct_or_changeset, opts) do
      {:ok, result} -> result
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset
    end
  end

  @doc """
  Updates a changeset or struct.
  Protected by write circuit breaker.
  """
  def update(changeset, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :write,
      fn ->
        Repo.update(changeset, opts)
      end,
      opts
    )
    |> handle_changeset_result()
  end

  @doc """
  Same as update/2 but returns the struct or raises if the changeset is invalid.
  """
  def update!(changeset, opts \\ []) do
    case update(changeset, opts) do
      {:ok, result} -> result
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset
    end
  end

  @doc """
  Inserts or updates a changeset or struct.
  Protected by write circuit breaker.
  """
  def insert_or_update(changeset, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :write,
      fn ->
        Repo.insert_or_update(changeset, opts)
      end,
      opts
    )
    |> handle_changeset_result()
  end

  @doc """
  Same as insert_or_update/2 but returns the struct or raises if the changeset is invalid.
  """
  def insert_or_update!(changeset, opts \\ []) do
    case insert_or_update(changeset, opts) do
      {:ok, result} -> result
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset
    end
  end

  @doc """
  Deletes a struct.
  Protected by write circuit breaker.
  """
  def delete(struct, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :write,
      fn ->
        Repo.delete(struct, opts)
      end,
      opts
    )
    |> handle_changeset_result()
  end

  @doc """
  Same as delete/2 but returns the struct or raises if the changeset is invalid.
  """
  def delete!(struct, opts \\ []) do
    case delete(struct, opts) do
      {:ok, result} -> result
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset
    end
  end

  # Bulk Operations

  @doc """
  Inserts all entries into the repository.
  Protected by bulk circuit breaker.
  """
  def insert_all(schema_or_source, entries, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :bulk,
      fn ->
        Repo.insert_all(schema_or_source, entries, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Updates all entries matching the given query.
  Protected by bulk circuit breaker.
  """
  def update_all(queryable, updates, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :bulk,
      fn ->
        Repo.update_all(queryable, updates, opts)
      end,
      opts
    )
    |> handle_result()
  end

  @doc """
  Deletes all entries matching the given query.
  Protected by bulk circuit breaker.
  """
  def delete_all(queryable, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :bulk,
      fn ->
        Repo.delete_all(queryable, opts)
      end,
      opts
    )
    |> handle_result()
  end

  # Transaction Operations

  @doc """
  Runs the given function inside a transaction.
  Protected by transaction circuit breaker.
  """
  def transaction(fun_or_multi, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :transaction,
      fn ->
        Repo.transaction(fun_or_multi, opts)
      end,
      Keyword.put(opts, :timeout, 30_000)
    )
    |> handle_transaction_result()
  end

  @doc """
  Rolls back the current transaction.
  """
  defdelegate rollback(value), to: Repo

  # Query Operations

  @doc """
  Executes a raw SQL query.
  Protected by appropriate circuit breaker based on query type.
  """
  def query(sql, params \\ [], opts \\ []) do
    operation_type = determine_query_operation_type(sql)

    CircuitBreaker.with_circuit_breaker(
      operation_type,
      fn ->
        Repo.query(sql, params, opts)
      end,
      opts
    )
    |> handle_query_result()
  end

  @doc """
  Same as query/3 but raises an exception on error.
  """
  def query!(sql, params \\ [], opts \\ []) do
    case query(sql, params, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  # Aggregate Operations

  @doc """
  Calculate the given aggregate over the given query.
  Protected by read circuit breaker.
  """
  def aggregate(queryable, aggregate, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.aggregate(queryable, aggregate, opts)
      end,
      opts
    )
    |> handle_result()
  end

  # Stream Operations

  @doc """
  Returns a stream for the given query.
  Protected by read circuit breaker for initial connection.
  """
  def stream(queryable, opts \\ []) do
    # Circuit breaker only protects the stream initialization
    # The actual streaming happens outside the circuit breaker
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        {:ok, Repo.stream(queryable, opts)}
      end,
      Keyword.put(opts, :timeout, 5000)
    )
    |> case do
      {:ok, stream} ->
        stream

      {:error, reason} ->
        Logger.error("Failed to create database stream: #{inspect(reason)}")
        raise "Database unavailable for streaming: #{inspect(reason)}"
    end
  end

  # Preload Operations

  @doc """
  Preloads associations.
  Protected by read circuit breaker.
  """
  def preload(struct_or_structs_or_nil, preloads, opts \\ []) do
    CircuitBreaker.with_circuit_breaker(
      :read,
      fn ->
        Repo.preload(struct_or_structs_or_nil, preloads, opts)
      end,
      opts
    )
    |> handle_result()
  end

  # Private Functions

  defp handle_result({:ok, result}), do: result

  defp handle_result({:error, :database_unavailable}) do
    Logger.error("Database operation failed: circuit breaker open")
    nil
  end

  defp handle_result({:error, reason}) do
    Logger.error("Database operation failed: #{inspect(reason)}")
    nil
  end

  defp handle_result(result), do: result

  defp handle_changeset_result({:ok, _} = result), do: result
  defp handle_changeset_result({:error, %Ecto.Changeset{}} = result), do: result

  defp handle_changeset_result({:error, :database_unavailable}) do
    Logger.error("Database operation failed: circuit breaker open")
    {:error, :database_unavailable}
  end

  defp handle_changeset_result({:error, reason}) do
    Logger.error("Database operation failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_changeset_result(result), do: result

  defp handle_transaction_result({:ok, _} = result), do: result
  defp handle_transaction_result({:error, _} = result), do: result

  defp handle_transaction_result({:error, :database_unavailable}) do
    Logger.error("Transaction failed: circuit breaker open")
    {:error, :database_unavailable}
  end

  defp handle_transaction_result(result), do: result

  defp handle_query_result({:ok, %Postgrex.Result{}} = result), do: result
  defp handle_query_result({:error, %Postgrex.Error{}} = result), do: result

  defp handle_query_result({:error, :database_unavailable}) do
    Logger.error("Query failed: circuit breaker open")
    {:error, :database_unavailable}
  end

  defp handle_query_result({:error, reason}) do
    Logger.error("Query failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_query_result(result), do: result

  defp determine_query_operation_type(sql) when is_binary(sql) do
    sql_upper = String.upcase(sql)

    cond do
      String.starts_with?(sql_upper, "SELECT") -> :read
      String.starts_with?(sql_upper, "INSERT") -> :write
      String.starts_with?(sql_upper, "UPDATE") -> :write
      String.starts_with?(sql_upper, "DELETE") -> :write
      String.starts_with?(sql_upper, "BEGIN") -> :transaction
      String.starts_with?(sql_upper, "COMMIT") -> :transaction
      String.starts_with?(sql_upper, "ROLLBACK") -> :transaction
      true -> :read
    end
  end
end
