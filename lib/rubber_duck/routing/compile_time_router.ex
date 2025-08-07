defmodule RubberDuck.Routing.CompileTimeRouter do
  @moduledoc """
  Compile-time optimized message routing with O(1) dispatch.

  This module generates pattern-matching dispatch functions at compile time,
  eliminating runtime lookups and providing maximum performance for message routing.

  ## Features

  - O(1) message dispatch via compile-time pattern matching
  - Compile-time route validation
  - Zero runtime overhead for route resolution
  - Automatic handler function validation
  - Comprehensive telemetry integration

  ## Usage

      defmodule MyRouter do
        use RubberDuck.Routing.CompileTimeRouter
        
        # Routes are defined at compile time
        route RubberDuck.Messages.Code.Analyze, 
              to: RubberDuck.Skills.CodeAnalysisSkill,
              function: :handle_analyze
      end
  """

  @doc """
  Macro to enable compile-time routing in a module.
  """
  defmacro __using__(opts) do
    quote do
      import RubberDuck.Routing.CompileTimeRouter
      Module.register_attribute(__MODULE__, :routes, accumulate: true)
      Module.register_attribute(__MODULE__, :route_modules, accumulate: true)

      @before_compile RubberDuck.Routing.CompileTimeRouter
      @opts unquote(opts)
    end
  end

  @doc """
  Define a compile-time route.

  ## Examples

      route MyMessage, to: MyHandler
      route MyMessage, to: MyHandler, function: :process
  """
  defmacro route(message_module, options) do
    handler = Keyword.fetch!(options, :to)
    function = Keyword.get(options, :function, :handle)

    quote do
      @routes {unquote(message_module), unquote(handler), unquote(function)}
      @route_modules unquote(message_module)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    route_list = Module.get_attribute(env.module, :routes, [])
    routes = route_list
    |> Enum.reverse()
    |> Enum.uniq()

    # Generate dispatch function clauses
    dispatch_clauses =
      for {message_module, handler, function} <- routes do
        quote do
          def dispatch(%unquote(message_module){} = message, context) do
            start_time = System.monotonic_time(:microsecond)

            # Emit telemetry start
            MessageTelemetry.emit_routing_start(message, context)

            # Direct call to handler - no runtime lookup needed
            result = apply(unquote(handler), unquote(function), [message, context])

            # Emit telemetry stop
            duration = System.monotonic_time(:microsecond) - start_time
            MessageTelemetry.emit_routing_stop(message, duration, result, context)

            result
          end
        end
      end

    # Generate fast dispatch function clauses
    dispatch_fast_clauses =
      for {message_module, handler, function} <- routes do
        quote do
          def dispatch_fast(%unquote(message_module){} = message, context) do
            apply(unquote(handler), unquote(function), [message, context])
          end
        end
      end

    # Generate get_handler function clauses
    get_handler_clauses =
      for {message_module, handler, function} <- routes do
        quote do
          def get_handler(unquote(message_module)) do
            {:ok, {unquote(handler), unquote(function)}}
          end
        end
      end

    quote do
      alias RubberDuck.Telemetry.MessageTelemetry
      require Logger

      # Store routes for introspection
      @all_routes unquote(Macro.escape(routes))
      @route_modules unquote(Macro.escape(Enum.map(routes, fn {m, _, _} -> m end)))

      @doc """
      Routes a message using compile-time optimized dispatch.

      This function is generated at compile time with pattern matching
      for all registered message types, providing O(1) dispatch.
      """
      @spec dispatch(struct(), map()) :: {:ok, term()} | {:error, term()}
      def dispatch(message, context \\ %{})

      # Inject generated dispatch clauses
      unquote_splicing(dispatch_clauses)

      # Fallback for unknown message types
      def dispatch(%module{} = message, context) do
        Logger.warning("No compile-time route for message type: #{inspect(module)}")
        {:error, {:no_route_defined, module}}
      end

      @doc """
      Fast dispatch without telemetry for maximum performance.
      """
      @spec dispatch_fast(struct(), map()) :: {:ok, term()} | {:error, term()}
      def dispatch_fast(message, context \\ %{})

      # Inject generated fast dispatch clauses
      unquote_splicing(dispatch_fast_clauses)

      # Fast fallback
      def dispatch_fast(%module{} = _message, _context) do
        {:error, {:no_route_defined, module}}
      end

      @doc """
      Batch dispatch with compile-time optimization.
      """
      @spec dispatch_batch([struct()], keyword()) :: [term()]
      def dispatch_batch(messages, opts \\ []) do
        max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online() * 2)
        timeout = Keyword.get(opts, :timeout, 5000)

        messages
        |> Task.async_stream(
          fn message -> dispatch(message, %{batch: true}) end,
          max_concurrency: max_concurrency,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, :timeout} -> {:error, :timeout}
          {:exit, reason} -> {:error, {:task_failed, reason}}
        end)
      end

      @doc """
      Returns all registered routes for introspection.
      """
      @spec routes() :: [{module(), module(), atom()}]
      def routes do
        @all_routes
      end

      @doc """
      Checks if a route exists for a message type.
      """
      @spec route_exists?(module()) :: boolean()
      def route_exists?(message_module) do
        message_module in @route_modules
      end

      @doc """
      Returns the handler for a message type.
      """
      @spec get_handler(module()) :: {:ok, {module(), atom()}} | {:error, :not_found}
      def get_handler(message_module)

      # Inject generated get_handler clauses
      unquote_splicing(get_handler_clauses)

      def get_handler(_), do: {:error, :not_found}

      @doc """
      Validates that all routes have valid handlers at runtime.
      """
      @spec validate_routes() :: :ok | {:error, [{module(), module(), atom()}]}
      def validate_routes do
        invalid_routes =
          @all_routes
          |> Enum.filter(fn {_msg_module, handler, function} ->
            not (Code.ensure_loaded?(handler) and function_exported?(handler, function, 2))
          end)

        case invalid_routes do
          [] -> :ok
          routes -> {:error, routes}
        end
      end
    end
  end
end
