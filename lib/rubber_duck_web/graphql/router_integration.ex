defmodule RubberDuckWeb.GraphQL.RouterIntegration do
  @moduledoc """
  Integration instructions for adding GraphQL to the Phoenix router.

  This file demonstrates how to integrate the GraphQL API once Absinthe
  dependencies are added to mix.exs.

  Required dependencies:
  {:absinthe, "~> 1.7"},
  {:absinthe_phoenix, "~> 2.0"},
  {:absinthe_plug, "~> 1.5"}
  """

  @doc """
  Router configuration to add to RubberDuckWeb.Router.

  Add this to your router.ex file:
  """
  def router_config do
    """
    # Add to the top of router.ex
    import Absinthe.Phoenix.Router

    # Add this pipeline after the existing :api pipeline
    pipeline :graphql do
      plug :accepts, ["json"]
      plug AshAuthentication.Plug.LoadFromBearer, resource: RubberDuck.Accounts.User
      plug :set_actor, :user
      plug RubberDuckWeb.GraphQL.Context
    end

    # Add this scope after the existing API scope
    scope "/graphql" do
      pipe_through :graphql
      
      forward "/", Absinthe.Plug,
        schema: RubberDuckWeb.GraphQL.Schema,
        context: %{pubsub: RubberDuckWeb.Endpoint}
    end

    # Add GraphiQL interface for development
    if Application.compile_env(:rubber_duck, :dev_routes) do
      scope "/" do
        pipe_through :browser
        
        forward "/graphiql", Absinthe.Plug.GraphiQL,
          schema: RubberDuckWeb.GraphQL.Schema,
          interface: :playground,
          context: %{pubsub: RubberDuckWeb.Endpoint}
      end
    end
    """
  end

  @doc """
  Context plug for GraphQL authentication and authorization.
  """
  def context_plug_example do
    """
    defmodule RubberDuckWeb.GraphQL.Context do
      @behaviour Plug
      
      import Plug.Conn
      
      def init(opts), do: opts
      
      def call(conn, _opts) do
        context = build_context(conn)
        Absinthe.Plug.put_options(conn, context: context)
      end
      
      defp build_context(conn) do
        %{
          current_user: conn.assigns[:current_user],
          ip_address: get_peer_data(conn).address,
          user_agent: get_req_header(conn, "user-agent") |> List.first()
        }
      end
    end
    """
  end

  @doc """
  Subscription configuration for Phoenix.Endpoint.
  """
  def subscription_config do
    """
    # Add to your endpoint.ex file
    use Absinthe.Phoenix.Endpoint

    # In the socket configuration
    socket "/socket", RubberDuckWeb.UserSocket,
      websocket: true,
      longpoll: false
      
    socket "/graphql_socket", Absinthe.Phoenix.Socket,
      websocket: [
        subprotocols: ["graphql-ws"]
      ]
    """
  end

  @doc """
  Example GraphQL queries that would work with the implemented schema.
  """
  def example_queries do
    """
    # Get all preferences
    query GetPreferences {
      preferences {
        edges {
          node {
            id
            key
            value
            category
            source
            description
            lastModified
          }
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
        }
        totalCount
      }
    }

    # Get preferences with filtering
    query GetFilteredPreferences($filter: PreferenceFilter, $pagination: Pagination) {
      preferences(filter: $filter, pagination: $pagination) {
        edges {
          node {
            id
            key
            value
            category
            source
            inheritedFrom {
              key
              value
            }
          }
        }
      }
    }

    # Get specific preference
    query GetPreference($id: ID!) {
      preference(id: $id) {
        id
        key
        value
        category
        source
        description
        dataType
        defaultValue
        constraints
        lastModified
        overrides {
          key
          value
          source
        }
      }
    }

    # Get templates
    query GetTemplates($filter: TemplateFilter) {
      templates(filter: $filter) {
        id
        name
        description
        category
        templateType
        createdBy
        preferences
        metadata {
          preferenceCount
          categories
        }
        rating
        usageCount
      }
    }

    # Get analytics data
    query GetAnalytics($filter: AnalyticsFilter) {
      analytics(filter: $filter) {
        summary {
          totalPreferences
          userOverrides
          recentChanges
          categoriesUsed
        }
        categoryDistribution {
          category
          count
          percentage
        }
        trends {
          timeSeries {
            timestamp
            changes
            uniquePreferences
          }
          changeFrequency {
            averageChangesPerDay
            trendDirection
          }
        }
        recommendations {
          id
          type
          preferenceKey
          currentValue
          recommendedValue
          reason
          confidence
          impact
        }
        inheritanceAnalysis {
          summary {
            systemDefaults
            userOverrides
            projectOverrides
          }
          inheritanceTree {
            key
            systemValue
            userValue
            projectValue
            effectiveValue
            source
          }
        }
      }
    }
    """
  end

  @doc """
  Example GraphQL mutations.
  """
  def example_mutations do
    """
    # Create preference
    mutation CreatePreference($input: PreferenceInput!) {
      createPreference(input: $input) {
        id
        key
        value
        category
        source
        lastModified
      }
    }

    # Update preference
    mutation UpdatePreference($id: ID!, $input: PreferenceUpdateInput!) {
      updatePreference(id: $id, input: $input) {
        id
        key
        value
        lastModified
      }
    }

    # Delete preference
    mutation DeletePreference($id: ID!) {
      deletePreference(id: $id)
    }

    # Create template
    mutation CreateTemplate($input: TemplateInput!) {
      createTemplate(input: $input) {
        id
        name
        description
        preferences
        metadata {
          preferenceCount
        }
      }
    }

    # Apply template
    mutation ApplyTemplate($id: ID!, $input: TemplateApplicationInput!) {
      applyTemplate(id: $id, input: $input) {
        success
        appliedCount
        skippedCount
        errorCount
        changes {
          key
          oldValue
          newValue
          action
        }
        errors
      }
    }

    # Batch update preferences
    mutation BatchUpdatePreferences($inputs: [PreferenceInput!]!) {
      batchUpdatePreferences(inputs: $inputs) {
        totalCount
        successCount
        errorCount
        results {
          success
          preference {
            id
            key
            value
          }
          error
        }
      }
    }
    """
  end

  @doc """
  Example GraphQL subscriptions.
  """
  def example_subscriptions do
    """
    # Subscribe to preference changes
    subscription PreferenceChanged($scope: PreferenceScope, $userId: ID) {
      preferenceChanged(scope: $scope, userId: $userId) {
        id
        key
        value
        category
        source
        lastModified
      }
    }

    # Subscribe to template applications
    subscription TemplateApplied($templateId: ID!) {
      templateApplied(templateId: $templateId) {
        success
        appliedCount
        changes {
          key
          newValue
          action
        }
      }
    }

    # Subscribe to analytics updates
    subscription AnalyticsUpdated($userId: ID) {
      analyticsUpdated(userId: $userId) {
        summary {
          totalPreferences
          userOverrides
          recentChanges
        }
        categoryDistribution {
          category
          count
          percentage
        }
      }
    }
    """
  end

  @doc """
  Installation and setup instructions.
  """
  def setup_instructions do
    """
    # Setup Instructions for GraphQL Implementation

    ## 1. Add Dependencies to mix.exs

    Add these dependencies to your deps/0 function:

    {:absinthe, "~> 1.7"},
    {:absinthe_phoenix, "~> 2.0"},
    {:absinthe_plug, "~> 1.5"}

    ## 2. Update Router

    Add the router configuration shown in router_config/0 to your router.ex file.

    ## 3. Update Endpoint

    Add the subscription configuration from subscription_config/0 to your endpoint.ex.

    ## 4. Update Schema Module

    Replace the mock schema in RubberDuckWeb.GraphQL.Schema with actual Absinthe schema:

    defmodule RubberDuckWeb.GraphQL.Schema do
      use Absinthe.Schema
      
      import_types Absinthe.Type.Custom
      import_types RubberDuckWeb.GraphQL.Types.PreferenceTypes
      import_types RubberDuckWeb.GraphQL.Types.TemplateTypes
      import_types RubberDuckWeb.GraphQL.Types.AnalyticsTypes
      
      alias RubberDuckWeb.GraphQL.Resolvers
      
      # ... (use the schema definition from schema_definition/0)
    end

    ## 5. Create Type Modules

    Create separate type modules for better organization:
    - RubberDuckWeb.GraphQL.Types.PreferenceTypes
    - RubberDuckWeb.GraphQL.Types.TemplateTypes  
    - RubberDuckWeb.GraphQL.Types.AnalyticsTypes

    ## 6. Update Resolvers

    Remove the mock comments from the resolver modules and implement actual
    Absinthe resolver functions.

    ## 7. Test the API

    After setup, visit /graphiql in development to test the GraphQL API
    using the example queries, mutations, and subscriptions provided.

    ## 8. Integration with Existing Systems

    Connect the GraphQL resolvers to the existing preference management
    system by updating the resolver functions to use actual Ash resources
    and business logic modules.
    """
  end
end
