defmodule RubberDuck.Adapters.SignalAdapter do
  @moduledoc """
  Bidirectional adapter between typed messages and Jido signals.

  This adapter provides seamless conversion between the new protocol-based
  message system and the existing Jido signal infrastructure, ensuring
  backward compatibility during migration.

  ## Usage

      # Convert typed message to Jido signal
      message = %Code.Analyze{file_path: "/lib/foo.ex", analysis_type: :security}
      {:ok, signal} = SignalAdapter.to_signal(message)
      
      # Convert Jido signal to typed message
      signal = %{type: "code.analyze.file", data: %{...}}
      {:ok, message} = SignalAdapter.from_signal(signal)
      
      # Batch conversion
      {messages, errors} = SignalAdapter.from_signals(signals)
  """

  alias RubberDuck.Messages.Registry
  alias RubberDuck.Protocol.Message
  require Logger

  @doc """
  Converts a typed message to a Jido signal.

  Returns `{:ok, signal}` if successful, or `{:error, reason}` if the
  message doesn't implement the Message protocol.
  """
  @spec to_signal(struct()) :: {:ok, map()} | {:error, term()}
  def to_signal(%module{} = message) do
    # Check if the protocol is implemented
    if function_exported?(module, :__struct__, 0) and Message.impl_for(message) do
      try do
        signal = Message.to_jido_signal(message)
        {:ok, signal}
      rescue
        e ->
          Logger.error("Failed to convert message to signal: #{inspect(e)}")
          {:error, {:conversion_failed, e}}
      end
    else
      {:error, {:protocol_not_implemented, module}}
    end
  end

  def to_signal(_), do: {:error, :not_a_struct}

  @doc """
  Converts a Jido signal to a typed message.

  Returns `{:ok, message}` if successful, or `{:error, reason}` if the
  signal type is unknown or data is invalid.
  """
  @spec from_signal(map()) :: {:ok, struct()} | {:error, term()}
  def from_signal(%{type: type, data: data} = signal) when is_binary(type) do
    case Registry.lookup_type(type) do
      nil ->
        Logger.debug("Unknown signal type: #{type}")
        {:error, {:unknown_signal_type, type}}

      module ->
        try do
          # Normalize the data
          normalized_data = normalize_signal_data(data)

          # Apply signal-specific transformations
          normalized_data = apply_signal_transformations(type, normalized_data)

          # Add metadata if present
          normalized_data =
            if Map.has_key?(signal, :metadata) do
              Map.put(normalized_data, :metadata, signal.metadata)
            else
              normalized_data
            end

          # Create the struct
          message = struct!(module, normalized_data)

          # Validate the message
          case Message.validate(message) do
            {:ok, validated} -> {:ok, validated}
            {:error, reason} -> {:error, {:validation_failed, reason}}
          end
        rescue
          e in [ArgumentError, KeyError] ->
            Logger.error("Failed to create message from signal: #{inspect(e)}")
            {:error, {:invalid_signal_data, e}}
        end
    end
  end

  def from_signal(%{type: type}) when is_binary(type) do
    {:error, {:missing_signal_data, type}}
  end

  def from_signal(_), do: {:error, :invalid_signal_format}

  @doc """
  Converts multiple signals to messages in parallel.

  Returns `{messages, errors}` where messages is a list of successfully
  converted messages and errors is a list of conversion failures.
  """
  @spec from_signals([map()]) :: {[struct()], [term()]}
  def from_signals(signals) when is_list(signals) do
    signals
    |> Task.async_stream(&from_signal/1,
      max_concurrency: System.schedulers_online() * 2,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce({[], []}, fn
      {:ok, {:ok, msg}}, {msgs, errs} ->
        {[msg | msgs], errs}

      {:ok, {:error, _} = err}, {msgs, errs} ->
        {msgs, [err | errs]}

      {:exit, reason}, {msgs, errs} ->
        {msgs, [{:error, {:conversion_timeout, reason}} | errs]}
    end)
    |> then(fn {msgs, errs} ->
      {Enum.reverse(msgs), Enum.reverse(errs)}
    end)
  end

  @doc """
  Converts multiple messages to signals in parallel.

  Returns `{signals, errors}`.
  """
  @spec to_signals([struct()]) :: {[map()], [term()]}
  def to_signals(messages) when is_list(messages) do
    messages
    |> Task.async_stream(&to_signal/1,
      max_concurrency: System.schedulers_online() * 2,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce({[], []}, fn
      {:ok, {:ok, signal}}, {sigs, errs} ->
        {[signal | sigs], errs}

      {:ok, {:error, _} = err}, {sigs, errs} ->
        {sigs, [err | errs]}

      {:exit, reason}, {sigs, errs} ->
        {sigs, [{:error, {:conversion_timeout, reason}} | errs]}
    end)
    |> then(fn {sigs, errs} ->
      {Enum.reverse(sigs), Enum.reverse(errs)}
    end)
  end

  @doc """
  Checks if a signal type can be converted to a typed message.

  Supports wildcard patterns.
  """
  @spec convertible?(String.t() | map()) :: boolean()
  def convertible?(type) when is_binary(type) do
    Registry.pattern_registered?(type)
  end

  def convertible?(%{type: type}) when is_binary(type) do
    convertible?(type)
  end

  def convertible?(_), do: false

  @doc """
  Routes a wildcard signal to all matching message handlers.

  Returns a list of results from all matching handlers.
  """
  @spec route_wildcard_signal(map()) :: [{:ok, struct()} | {:error, term()}]
  def route_wildcard_signal(%{type: pattern} = signal) when is_binary(pattern) do
    alias RubberDuck.Messages.PatternMatcher

    if PatternMatcher.has_wildcard?(pattern) do
      # Find all message types that match the wildcard pattern
      matching_modules = Registry.lookup_types_matching(pattern)

      # Convert the signal to each matching message type
      Enum.map(matching_modules, fn module ->
        # Create a signal with the concrete type for this module
        concrete_type = Registry.pattern_for_type(module)
        concrete_signal = %{signal | type: concrete_type}

        from_signal(concrete_signal)
      end)
    else
      # Not a wildcard, use normal conversion
      [from_signal(signal)]
    end
  end

  # Private functions

  defp normalize_signal_data(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {ensure_atom_key(k), v} end)
    |> Map.new()
  end

  defp normalize_signal_data(data), do: data

  # Apply signal-specific transformations to map legacy signal data to message fields
  defp apply_signal_transformations("code.analyze.file", data) do
    data
    |> Map.put_new(:analysis_type, :comprehensive)
    |> Map.put_new(:depth, :moderate)
    |> Map.put_new(:auto_fix, false)
  end

  defp apply_signal_transformations("code.quality.check", data) do
    data
    |> Map.put_new(:analysis_type, :quality)
    |> Map.put_new(:depth, :moderate)
  end

  defp apply_signal_transformations("code.security.scan", data) do
    data
    |> Map.put_new(:scan_type, :comprehensive)
    |> Map.put_new(:severity_threshold, :medium)
  end

  defp apply_signal_transformations("code.performance.analyze", data) do
    data
    |> Map.put_new(:analysis_depth, :moderate)
    |> Map.put_new(:include_suggestions, true)
  end

  defp apply_signal_transformations("code.impact.assess", data) do
    data
    |> Map.put_new(:assessment_scope, :comprehensive)
    |> Map.put_new(:include_dependencies, true)
  end

  # Default: no transformation needed
  defp apply_signal_transformations(_type, data), do: data

  defp ensure_atom_key(key) when is_atom(key), do: key

  defp ensure_atom_key(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> String.to_atom(key)
    end
  end

  defp ensure_atom_key(key), do: key
end
