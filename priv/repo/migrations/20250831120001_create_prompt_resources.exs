defmodule RubberDuck.Repo.Migrations.CreatePromptResources do
  @moduledoc """
  Create prompt management tables with multi-tenant Row-Level Security.
  
  Creates comprehensive prompt management infrastructure including:
  - prompt_categories: Hierarchical category organization
  - prompts: Core prompt storage with three-tier hierarchy
  - prompt_versions: Complete version history tracking
  - prompt_usages: Usage analytics and performance metrics
  
  Includes optimized indexes for hierarchical queries and Row-Level Security
  policies for multi-tenant data isolation.
  """
  
  use Ecto.Migration

  def up do
    # Enable Row-Level Security
    execute "ALTER DATABASE #{repo().config()[:database]} SET row_security = on"
    
    # Create prompt_categories table
    create table(:prompt_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :slug, :string, null: false
      add :tenant_id, :binary_id, null: false
      add :category_type, :string, null: false, default: "general"
      add :access_level, :string, null: false, default: "public"
      add :parent_id, references(:prompt_categories, type: :binary_id, on_delete: :restrict)
      add :sort_order, :integer, default: 0
      add :color_code, :string
      add :icon, :string
      add :metadata, :map, default: %{}
      add :usage_count, :integer, default: 0
      add :popularity_score, :decimal
      add :is_template_category, :boolean, default: false
      add :tags, {:array, :string}, default: []
      
      timestamps()
    end

    # Create prompts table
    create table(:prompts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :content, :text, null: false
      add :prompt_type, :string, null: false
      add :tenant_id, :binary_id, null: false
      add :project_id, :binary_id
      add :user_id, :binary_id
      add :category_id, references(:prompt_categories, type: :binary_id, on_delete: :nilify_all)
      add :parent_id, references(:prompts, type: :binary_id, on_delete: :restrict)
      add :status, :string, null: false, default: "draft"
      add :priority, :integer, default: 0
      add :variables, {:array, :string}, default: []
      add :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :is_template, :boolean, default: false
      add :effectiveness_score, :decimal
      
      timestamps()
    end

    # Create prompt_versions table
    create table(:prompt_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :prompt_id, references(:prompts, type: :binary_id, on_delete: :cascade), null: false
      add :version_number, :integer, null: false
      add :content_snapshot, :text, null: false
      add :change_summary, :string
      add :diff_data, :map, default: %{}
      add :created_by_id, :binary_id, null: false
      add :metadata, :map, default: %{}
      add :content_hash, :string
      add :size_bytes, :integer
      add :change_type, :string
      
      timestamps()
    end

    # Create prompt_usages table
    create table(:prompt_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :prompt_id, references(:prompts, type: :binary_id, on_delete: :cascade), null: false
      add :used_by_id, :binary_id, null: false
      add :context_type, :string, null: false
      add :request_id, :binary_id
      add :response_time_ms, :integer
      add :tokens_used, :integer
      add :success, :boolean, null: false, default: true
      add :error_type, :string
      add :error_message, :text
      add :effectiveness_score, :decimal
      add :user_satisfaction, :integer
      add :performance_metrics, :map, default: %{}
      add :usage_metadata, :map, default: %{}
      add :variables_used, :map, default: %{}
      
      timestamps()
    end

    # Create indexes for performance optimization
    
    # Category indexes
    create index(:prompt_categories, [:tenant_id])
    create index(:prompt_categories, [:slug, :tenant_id], unique: true)
    create index(:prompt_categories, [:category_type, :tenant_id])
    create index(:prompt_categories, [:parent_id])
    create index(:prompt_categories, [:sort_order, :name])
    create index(:prompt_categories, [:popularity_score], order_by: [desc: :popularity_score])
    create index(:prompt_categories, [:tags], using: :gin)

    # Prompt indexes
    create index(:prompts, [:tenant_id])
    create index(:prompts, [:name, :prompt_type, :tenant_id, :project_id, :user_id], unique: true)
    create index(:prompts, [:prompt_type, :tenant_id])
    create index(:prompts, [:project_id]) 
    create index(:prompts, [:user_id])
    create index(:prompts, [:category_id])
    create index(:prompts, [:parent_id])
    create index(:prompts, [:status, :prompt_type])
    create index(:prompts, [:priority], order_by: [desc: :priority])
    create index(:prompts, [:effectiveness_score], order_by: [desc: :effectiveness_score])
    create index(:prompts, [:tags], using: :gin)
    create index(:prompts, [:variables], using: :gin)
    create index(:prompts, [:inserted_at, :prompt_type])

    # Version indexes
    create index(:prompt_versions, [:prompt_id, :version_number], unique: true)
    create index(:prompt_versions, [:prompt_id, :inserted_at])
    create index(:prompt_versions, [:created_by_id])
    create index(:prompt_versions, [:change_type])
    create index(:prompt_versions, [:content_hash])

    # Usage indexes
    create index(:prompt_usages, [:prompt_id, :inserted_at])
    create index(:prompt_usages, [:used_by_id, :inserted_at])
    create index(:prompt_usages, [:context_type, :inserted_at])
    create index(:prompt_usages, [:success, :inserted_at])
    create index(:prompt_usages, [:request_id])
    create index(:prompt_usages, [:response_time_ms])
    create index(:prompt_usages, [:tokens_used])
    create index(:prompt_usages, [:effectiveness_score], order_by: [desc: :effectiveness_score])

    # Create Row-Level Security policies
    
    # Enable RLS on all prompt tables
    execute "ALTER TABLE prompt_categories ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE prompts ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE prompt_versions ENABLE ROW LEVEL SECURITY"  
    execute "ALTER TABLE prompt_usages ENABLE ROW LEVEL SECURITY"

    # Categories RLS policy
    execute """
    CREATE POLICY categories_tenant_isolation ON prompt_categories
    FOR ALL USING (tenant_id = current_setting('app.tenant_id')::uuid)
    """

    # Prompts RLS policy
    execute """
    CREATE POLICY prompts_tenant_isolation ON prompts
    FOR ALL USING (tenant_id = current_setting('app.tenant_id')::uuid)
    """

    # Versions RLS policy (inherit from parent prompt)
    execute """
    CREATE POLICY versions_tenant_isolation ON prompt_versions
    FOR ALL USING (
      prompt_id IN (
        SELECT id FROM prompts WHERE tenant_id = current_setting('app.tenant_id')::uuid
      )
    )
    """

    # Usages RLS policy (inherit from parent prompt)
    execute """
    CREATE POLICY usages_tenant_isolation ON prompt_usages
    FOR ALL USING (
      prompt_id IN (
        SELECT id FROM prompts WHERE tenant_id = current_setting('app.tenant_id')::uuid
      )
    )
    """

    # Add check constraints for data integrity
    
    # Prompt type constraints
    execute """
    ALTER TABLE prompts 
    ADD CONSTRAINT prompts_type_check 
    CHECK (prompt_type IN ('system', 'project', 'user'))
    """

    execute """
    ALTER TABLE prompts 
    ADD CONSTRAINT prompts_status_check 
    CHECK (status IN ('draft', 'pending', 'approved', 'archived'))
    """

    # Category constraints
    execute """
    ALTER TABLE prompt_categories 
    ADD CONSTRAINT categories_type_check 
    CHECK (category_type IN ('system', 'project', 'user', 'general', 'template'))
    """

    execute """
    ALTER TABLE prompt_categories 
    ADD CONSTRAINT categories_access_check 
    CHECK (access_level IN ('public', 'private', 'restricted', 'admin_only'))
    """

    # Usage constraints
    execute """
    ALTER TABLE prompt_usages 
    ADD CONSTRAINT usages_context_check 
    CHECK (context_type IN ('llm_request', 'workflow_step', 'rag_query', 'template_expansion', 'test_execution'))
    """

    execute """
    ALTER TABLE prompt_usages 
    ADD CONSTRAINT usages_error_type_check 
    CHECK (error_type IN ('timeout', 'validation_error', 'security_violation', 'provider_error', 'content_error'))
    """

    # Version constraints
    execute """
    ALTER TABLE prompt_versions 
    ADD CONSTRAINT versions_change_type_check 
    CHECK (change_type IN ('create', 'update', 'approve', 'archive', 'restore'))
    """

    # Business logic constraints
    
    # Project prompts must have project_id
    execute """
    ALTER TABLE prompts 
    ADD CONSTRAINT prompts_project_id_required 
    CHECK (
      (prompt_type != 'project') OR 
      (prompt_type = 'project' AND project_id IS NOT NULL)
    )
    """

    # User prompts must have user_id
    execute """
    ALTER TABLE prompts 
    ADD CONSTRAINT prompts_user_id_required 
    CHECK (
      (prompt_type != 'user') OR 
      (prompt_type = 'user' AND user_id IS NOT NULL)
    )
    """

    # System prompts cannot have project_id or user_id
    execute """
    ALTER TABLE prompts 
    ADD CONSTRAINT prompts_system_isolation 
    CHECK (
      (prompt_type != 'system') OR 
      (prompt_type = 'system' AND project_id IS NULL AND user_id IS NULL)
    )
    """

    # Version numbers must be positive and sequential
    execute """
    ALTER TABLE prompt_versions 
    ADD CONSTRAINT versions_positive_number 
    CHECK (version_number > 0)
    """

    # Performance and analytics constraints
    execute """
    ALTER TABLE prompt_usages 
    ADD CONSTRAINT usages_response_time_positive 
    CHECK (response_time_ms IS NULL OR response_time_ms >= 0)
    """

    execute """
    ALTER TABLE prompt_usages 
    ADD CONSTRAINT usages_tokens_positive 
    CHECK (tokens_used IS NULL OR tokens_used >= 0)
    """

    execute """
    ALTER TABLE prompt_usages 
    ADD CONSTRAINT usages_satisfaction_range 
    CHECK (user_satisfaction IS NULL OR (user_satisfaction >= 1 AND user_satisfaction <= 5))
    """

    # Create functions for RLS policy support
    execute """
    CREATE OR REPLACE FUNCTION set_tenant_context(tenant_uuid uuid)
    RETURNS void AS $$
    BEGIN
      PERFORM set_config('app.tenant_id', tenant_uuid::text, true);
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE OR REPLACE FUNCTION get_tenant_context()
    RETURNS uuid AS $$
    BEGIN
      RETURN current_setting('app.tenant_id', true)::uuid;
    EXCEPTION
      WHEN OTHERS THEN
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  def down do
    # Drop functions
    execute "DROP FUNCTION IF EXISTS set_tenant_context(uuid)"
    execute "DROP FUNCTION IF EXISTS get_tenant_context()"

    # Drop tables in reverse order (respecting foreign keys)
    drop table(:prompt_usages)
    drop table(:prompt_versions)
    drop table(:prompts)
    drop table(:prompt_categories)
  end
end