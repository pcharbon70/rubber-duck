defmodule RubberDuck.LLM.Provider do
  @moduledoc """
  Behavior definition for LLM providers.

  Each provider implementation must implement this behavior to ensure
  consistent interfaces across different LLM services (OpenAI, Anthropic, etc).
  """

  @type provider_config :: %{
          required(:api_key) => String.t(),
          optional(:base_url) => String.t() | nil,
          optional(:model) => String.t(),
          optional(:max_tokens) => non_neg_integer(),
          optional(:temperature) => float(),
          optional(:timeout) => non_neg_integer(),
          optional(atom()) => any()
        }

  @type completion_request :: %{
          required(:model) => String.t(),
          required(:messages) => list(message()),
          optional(:max_tokens) => non_neg_integer() | nil,
          optional(:temperature) => float() | nil,
          optional(:stream) => boolean(),
          optional(atom()) => any()
        }

  @type message :: %{
          required(:role) => :system | :user | :assistant,
          required(:content) => String.t()
        }

  @type completion_response :: %{
          required(:id) => String.t(),
          required(:model) => String.t(),
          required(:choices) => list(choice()),
          required(:usage) => usage(),
          required(:created) => non_neg_integer()
        }

  @type choice :: %{
          required(:index) => non_neg_integer(),
          required(:message) => message(),
          optional(:finish_reason) => String.t() | nil
        }

  @type usage :: %{
          required(:prompt_tokens) => non_neg_integer(),
          required(:completion_tokens) => non_neg_integer(),
          required(:total_tokens) => non_neg_integer()
        }

  @type embedding_request :: %{
          required(:model) => String.t(),
          required(:input) => String.t() | list(String.t()),
          optional(atom()) => any()
        }

  @type embedding_response :: %{
          required(:data) => list(embedding()),
          required(:model) => String.t(),
          required(:usage) => usage()
        }

  @type embedding :: %{
          required(:index) => non_neg_integer(),
          required(:embedding) => list(float())
        }

  @type provider_capabilities :: %{
          required(:completion) => boolean(),
          required(:streaming) => boolean(),
          required(:embeddings) => boolean(),
          required(:function_calling) => boolean(),
          required(:vision) => boolean(),
          required(:max_context_length) => non_neg_integer(),
          required(:models) => list(String.t())
        }

  @type error_response :: {:error, atom() | String.t() | map()}

  @doc """
  Initialize the provider with configuration.
  Called when the provider is registered with the service.
  """
  @callback init(provider_config()) :: {:ok, any()} | error_response()

  @doc """
  Generate a completion from the provider.
  """
  @callback complete(completion_request(), provider_config()) ::
              {:ok, completion_response()} | error_response()

  @doc """
  Generate a streaming completion from the provider.
  Returns a stream that emits completion chunks.
  """
  @callback stream(completion_request(), provider_config()) ::
              {:ok, Enumerable.t()} | error_response()

  @doc """
  Generate embeddings for the given input.
  """
  @callback embed(embedding_request(), provider_config()) ::
              {:ok, embedding_response()} | error_response()

  @doc """
  Get the capabilities of this provider.
  """
  @callback capabilities() :: provider_capabilities()

  @doc """
  Check if the provider is healthy and can accept requests.
  """
  @callback health_check(provider_config()) :: :ok | error_response()

  @doc """
  Get the name of the provider.
  """
  @callback name() :: String.t()

  @doc """
  Validate the provider configuration.
  """
  @callback validate_config(provider_config()) :: :ok | error_response()

  @optional_callbacks stream: 2, embed: 2
end
