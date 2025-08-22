# Phase 1A Section 1A.1: Ash Persistence Layer - Implementation Plan

## Overview

Phase 1A Section 1A.1 implements the foundational Ash persistence layer for the comprehensive hierarchical runtime configuration system. This section establishes the core data model for user preferences, project overrides, system defaults, and supporting resources that enable runtime configuration management without system restart.

## Problem Statement

The RubberDuck system needs a flexible, hierarchical configuration management system that allows:
- **System administrators** to set intelligent defaults for all users
- **Individual users** to customize their experience and tool behavior
- **Projects** to optionally override user preferences for team consistency
- **Runtime modification** without system restart or code changes
- **Secure storage** of sensitive configuration data (API keys, tokens)
- **Audit trails** for all configuration changes
- **Template-based** configuration sharing and standardization

## Solution Overview

Implement a comprehensive Ash-based persistence layer with:
- **Core Resources**: SystemDefault, UserPreference, ProjectPreference, ProjectPreferenceEnabled
- **Supporting Resources**: PreferenceHistory, PreferenceTemplate, PreferenceValidation, PreferenceCategory
- **Hierarchical Resolution**: System → User → Project (optional) preference inheritance
- **Security Integration**: Role-based access control and encryption for sensitive data
- **Change Tracking**: Complete audit trail with rollback capabilities

## Technical Implementation Plan

### 1A.1.1 Core Preference Resources

#### SystemDefault Resource
**File**: `lib/rubber_duck/preferences/resources/system_default.ex`

**Purpose**: Store intelligent system defaults for all configurable options

**Key Attributes**:
- `preference_key` (string, unique) - Dot-notation preference identifier
- `default_value` (string/json) - The default value (stored as JSON for flexibility)
- `data_type` (enum) - :string, :integer, :float, :boolean, :json, :encrypted
- `category` (string) - Preference category (llm, budgeting, ml, code_quality, etc.)
- `subcategory` (string) - Optional subcategory for organization
- `description` (text) - Human-readable description
- `constraints` (json) - Validation constraints (min/max, allowed values, etc.)
- `sensitive` (boolean) - Whether this preference contains sensitive data
- `version` (integer) - Version for schema evolution
- `deprecated` (boolean) - Mark deprecated preferences
- `replacement_key` (string) - Key for deprecated preference replacement

**Actions**:
- Create, Read, Update (admin only)
- List by category
- Search by key pattern
- Version management

#### UserPreference Resource  
**File**: `lib/rubber_duck/preferences/resources/user_preference.ex`

**Purpose**: Store user-specific preference overrides

**Key Attributes**:
- `user_id` (uuid, foreign key) - Link to user identity
- `preference_key` (string) - Links to SystemDefault.preference_key
- `value` (string/json) - User's preferred value
- `category` (string) - Inherited from SystemDefault
- `source` (enum) - :manual, :template, :migration, :import
- `last_modified` (datetime) - Track when preference was changed
- `modified_by` (string) - Who made the change (for admin modifications)
- `active` (boolean) - Enable/disable specific user preferences
- `notes` (text) - Optional user notes about preference choice

**Actions**:
- CRUD operations (user can modify own preferences)
- Bulk operations for template application
- Category-based operations
- Reset to system defaults

#### ProjectPreference Resource
**File**: `lib/rubber_duck/preferences/resources/project_preference.ex`

**Purpose**: Store project-specific preference overrides (when enabled)

**Key Attributes**:
- `project_id` (uuid, foreign key) - Link to project entity
- `preference_key` (string) - Links to SystemDefault.preference_key
- `value` (string/json) - Project's preferred value
- `inherits_user` (boolean) - Whether this preference inherits from user
- `override_reason` (text) - Justification for project override
- `approved_by` (uuid) - Who approved the project override
- `approved_at` (datetime) - When override was approved
- `effective_from` (datetime) - When override becomes active
- `effective_until` (datetime) - Optional expiration for temporary overrides
- `priority` (integer) - Priority for conflicting overrides

**Actions**:
- CRUD operations (project admins only)
- Bulk apply user preferences to project
- Selective inheritance control
- Temporary override management

#### ProjectPreferenceEnabled Resource
**File**: `lib/rubber_duck/preferences/resources/project_preference_enabled.ex`

**Purpose**: Control whether projects can override user preferences

**Key Attributes**:
- `project_id` (uuid, foreign key, unique) - One record per project
- `enabled` (boolean) - Master toggle for project preference overrides
- `enabled_categories` (json array) - Specific categories enabled for override
- `enablement_reason` (text) - Why project overrides were enabled
- `enabled_by` (uuid) - Who enabled project overrides
- `enabled_at` (datetime) - When overrides were enabled
- `override_count` (integer, calculated) - Number of active overrides
- `last_override_at` (datetime) - Most recent override activity

**Actions**:
- Enable/disable project overrides
- Category-specific enablement
- Override usage analytics
- Audit trail for enablement changes

### 1A.1.2 Supporting Resources

#### PreferenceHistory Resource
**File**: `lib/rubber_duck/preferences/resources/preference_history.ex`

**Purpose**: Track all preference changes for audit and rollback

**Key Attributes**:
- `change_id` (uuid, primary key)
- `user_id` (uuid) - User who made the change
- `project_id` (uuid, optional) - Project if project preference change
- `preference_key` (string) - Which preference was changed
- `old_value` (json) - Previous value
- `new_value` (json) - New value
- `change_type` (enum) - :create, :update, :delete, :template_apply, :reset
- `change_reason` (text) - Why the change was made
- `changed_by` (uuid) - User who made the change (may differ from user_id for admin changes)
- `changed_at` (datetime) - When change occurred
- `rollback_possible` (boolean) - Whether change can be rolled back
- `source_template_id` (uuid, optional) - If applied from template

**Actions**:
- Record all preference changes automatically
- Query change history by user/project/preference
- Rollback to previous values
- Generate change reports

#### PreferenceTemplate Resource
**File**: `lib/rubber_duck/preferences/resources/preference_template.ex`

**Purpose**: Define reusable preference sets for common scenarios

**Key Attributes**:
- `template_id` (uuid, primary key)
- `name` (string) - Template name (e.g., "Conservative LLM Usage")
- `description` (text) - Detailed template description
- `category` (string) - Template category (development, security, performance)
- `preferences` (json) - Map of preference_key -> value
- `template_type` (enum) - :system, :team, :public, :private
- `created_by` (uuid) - Template creator
- `created_at` (datetime)
- `version` (integer) - Template version
- `usage_count` (integer) - How many times template has been applied
- `rating` (float) - Average user rating
- `tags` (json array) - Tags for searchability

**Actions**:
- CRUD operations for templates
- Apply template to user/project preferences
- Template marketplace operations
- Usage analytics and ratings

#### PreferenceValidation Resource
**File**: `lib/rubber_duck/preferences/resources/preference_validation.ex`

**Purpose**: Store validation rules for preference values

**Key Attributes**:
- `validation_id` (uuid, primary key)
- `preference_key` (string) - Which preference this validates
- `validation_type` (enum) - :range, :enum, :regex, :function, :dependency
- `validation_rule` (json) - The validation rule definition
- `error_message` (string) - Custom error message for validation failure
- `severity` (enum) - :error, :warning, :info
- `active` (boolean) - Enable/disable validation rule
- `created_at` (datetime)
- `updated_at` (datetime)

**Actions**:
- Define validation rules per preference
- Validate preference values against rules
- Custom validation function support
- Cross-preference dependency validation

#### PreferenceCategory Resource
**File**: `lib/rubber_duck/preferences/resources/preference_category.ex`

**Purpose**: Define preference groupings and hierarchy

**Key Attributes**:
- `category_id` (uuid, primary key)
- `name` (string) - Category name
- `parent_category_id` (uuid, optional) - For nested categories
- `description` (text) - Category description
- `display_order` (integer) - Sort order in UI
- `icon` (string) - Icon for UI display
- `color` (string) - Color for UI theming
- `preferences_count` (integer, calculated) - Number of preferences in category
- `default_access_level` (enum) - :public, :user, :admin, :superadmin

**Actions**:
- CRUD operations for categories
- Hierarchical category management
- Category-based preference operations
- Access control by category

### 1A.1.3 Relationships and Calculated Fields

#### Resource Relationships:
```elixir
# UserPreference
belongs_to :user, RubberDuck.Accounts.User
belongs_to :system_default, SystemDefault, define_attribute?: false

# ProjectPreference  
belongs_to :project, RubberDuck.Projects.Project
belongs_to :system_default, SystemDefault, define_attribute?: false

# PreferenceHistory
belongs_to :user, RubberDuck.Accounts.User
belongs_to :project, RubberDuck.Projects.Project, allow_nil?: true
belongs_to :template, PreferenceTemplate, allow_nil?: true

# ProjectPreferenceEnabled
belongs_to :project, RubberDuck.Projects.Project

# PreferenceTemplate
belongs_to :created_by_user, RubberDuck.Accounts.User
has_many :history_entries, PreferenceHistory

# PreferenceValidation
belongs_to :system_default, SystemDefault, define_attribute?: false

# PreferenceCategory
belongs_to :parent_category, PreferenceCategory, allow_nil?: true
has_many :child_categories, PreferenceCategory
has_many :system_defaults, SystemDefault
```

#### Calculated Fields:
```elixir
# SystemDefault
calculate :usage_count, :integer, expr(count(user_preferences.preference_key))
calculate :override_percentage, :float, expr(usage_count / total_users * 100)

# UserPreference  
calculate :effective_value, :string, expr(resolve_preference_value(...))
calculate :is_overridden, :boolean, expr(value != system_default.default_value)

# ProjectPreference
calculate :inheritance_chain, :json, expr(build_inheritance_chain(...))
calculate :user_value, :string, expr(get_user_preference_value(...))

# ProjectPreferenceEnabled
calculate :active_override_count, :integer, expr(count(project_preferences))
calculate :override_percentage, :float, expr(active_override_count / total_preferences * 100)
```

## Implementation Strategy

### Phase A: Core Resources (Week 1)
1. **SystemDefault Resource**: Foundation with all system defaults
2. **UserPreference Resource**: User-specific overrides
3. **Basic validation**: Ensure data integrity
4. **Simple resolution**: Basic system → user hierarchy

### Phase B: Project Override System (Week 2)  
1. **ProjectPreference Resource**: Project-specific overrides
2. **ProjectPreferenceEnabled Resource**: Toggle project overrides
3. **Three-tier resolution**: System → User → Project hierarchy
4. **Override management**: Enable/disable project overrides

### Phase C: Supporting Infrastructure (Week 3)
1. **PreferenceHistory Resource**: Complete audit trail
2. **PreferenceTemplate Resource**: Template system
3. **PreferenceValidation Resource**: Advanced validation
4. **PreferenceCategory Resource**: Organization and hierarchy

### Phase D: Advanced Features (Week 4)
1. **Calculated fields**: Inheritance chains and analytics
2. **Complex relationships**: Cross-resource queries
3. **Performance optimization**: Caching and indexing
4. **Security integration**: Encryption and access control

## Success Criteria

### Functional Requirements:
- ✅ **Hierarchical Resolution**: System → User → Project preference inheritance
- ✅ **Runtime Flexibility**: Hot-reloadable preferences without restart
- ✅ **Project Autonomy**: Optional project-level overrides
- ✅ **Security**: Encrypted sensitive preferences with RBAC
- ✅ **Audit Trail**: Complete change history with rollback
- ✅ **Templates**: Shareable configuration templates

### Technical Requirements:
- ✅ **Ash Framework Integration**: Proper resource definitions with actions
- ✅ **Performance**: Efficient preference resolution with caching
- ✅ **Validation**: Comprehensive preference validation rules
- ✅ **Extensibility**: Easy addition of new preference types
- ✅ **Testing**: Complete unit test coverage for all resources

### Quality Requirements:
- ✅ **Clean Compilation**: No warnings with --warnings-as-errors
- ✅ **Zero Credo Issues**: Premium code quality standards
- ✅ **Documentation**: Comprehensive resource documentation
- ✅ **Integration Ready**: Foundation for subsequent Phase 1A sections

## Data Model Overview

### Preference Resolution Flow:
```
1. Query preference_key for user/project
2. Check ProjectPreferenceEnabled for project
3. If project overrides enabled:
   - Look for ProjectPreference value
   - If found and not inherits_user: return project value
4. Look for UserPreference value
5. If found: return user value
6. Return SystemDefault.default_value
```

### Category Hierarchy:
```
llm
├── providers (openai, anthropic, google)
├── models (gpt-4, claude-3, gemini)
├── fallback (provider_chain, retry_policies)
└── cost_optimization (budget_aware, token_optimization)

budgeting
├── limits (daily, weekly, monthly)
├── alerts (thresholds, escalation)
├── enforcement (hard_stop, soft_warning)
└── reporting (analytics, forecasting)

ml
├── enablement (global_toggle, feature_flags)
├── performance (accuracy_vs_speed, resources)
├── learning (learning_rate, iterations)
└── data (retention, privacy, sharing)

code_quality
├── smell_detection (35+ detectors)
├── refactoring_agents (82+ agents)
├── anti_patterns (24+ patterns)
└── credo_integration (rules, enforcement)
```

## Implementation Details

### Resource Action Patterns:
```elixir
# Standard CRUD actions for all resources
actions do
  defaults [:create, :read, :update, :destroy]
  
  # Custom actions for preference-specific operations
  read :by_category do
    argument :category, :string, allow_nil?: false
    filter expr(category == ^arg(:category))
  end
  
  read :effective_value do
    argument :user_id, :uuid, allow_nil?: false
    argument :project_id, :uuid, allow_nil?: true
    argument :preference_key, :string, allow_nil?: false
    # Complex resolution logic
  end
  
  update :bulk_update do
    argument :preferences, {:array, :map}, allow_nil?: false
    # Batch preference updates
  end
end
```

### Security Considerations:
```elixir
# Encryption for sensitive preferences
attribute :value, :string do
  allow_nil? false
  
  # Auto-encrypt sensitive preferences
  change {RubberDuck.Preferences.Changes.ConditionalEncryption, 
          sensitive_field: :sensitive}
end

# Role-based access control
policies do
  # Users can modify their own preferences
  policy action_type(:read) do
    authorize_if expr(user_id == ^actor(:id))
  end
  
  policy action_type([:create, :update, :destroy]) do
    authorize_if expr(user_id == ^actor(:id))
  end
  
  # Admins can modify any preferences
  policy action_type(:*) do
    authorize_if actor_attribute_equals(:role, :admin)
  end
end
```

### Performance Optimizations:
```elixir
# Indexes for efficient queries
postgres do
  table "user_preferences"
  
  index [:user_id, :preference_key], unique: true
  index [:preference_key]
  index [:category]
  index [:last_modified]
end

# Prepared queries for resolution
preparations do
  prepare build(load: [:system_default, :user, :project])
end
```

## Integration Points

### With Phase 1 Foundation:
- **User Management**: UserPreference links to existing User resource
- **Project Management**: ProjectPreference links to Project resource
- **Security System**: Leverages existing authentication and authorization
- **Agent System**: Agents will query preferences for behavior modification

### With Future Phases:
- **Phase 2 LLM Orchestration**: Provider selection based on preferences
- **Phase 11 Cost Management**: Budget preferences control spending
- **Phase 14 Refactoring Agents**: Agent enablement and aggressiveness settings
- **Phase 15 Code Smell Detection**: Detector configuration via preferences
- **Phase 16 Anti-Pattern Detection**: Pattern detection preferences

## Risk Mitigation

### Potential Challenges:
1. **Performance**: Preference resolution on every agent operation
2. **Complexity**: Three-tier hierarchy with inheritance logic
3. **Security**: Protecting sensitive preference data
4. **Migration**: Evolving preference schemas over time

### Mitigation Strategies:
1. **Caching Layer**: In-memory preference cache with smart invalidation
2. **Batch Operations**: Bulk preference resolution to minimize queries
3. **Encryption**: Automatic encryption for sensitive preferences
4. **Versioning**: Schema versioning with migration support

## Expected Outcomes

### Deliverables:
1. **8 Ash Resources**: Complete preference persistence layer
2. **Hierarchical Resolution**: System → User → Project inheritance
3. **Security Framework**: Encryption and access control
4. **Change Tracking**: Complete audit trail with rollback
5. **Template System**: Configuration sharing and standardization
6. **Validation Framework**: Comprehensive preference validation
7. **Unit Tests**: 100% test coverage for all resources
8. **Documentation**: Complete resource and API documentation

### Quality Metrics:
- Clean compilation with --warnings-as-errors
- Zero credo issues (warnings, refactoring, readability)
- 100% unit test coverage
- Comprehensive integration with existing Phase 1 foundation

## Next Steps After Completion

Phase 1A Section 1A.1 completion provides the persistence foundation for:
- **Section 1A.2**: Preference hierarchy system and resolution engine
- **Section 1A.3**: LLM provider preferences
- **Section 1A.4**: Budgeting and cost controls
- **Section 1A.5**: Machine learning preferences
- **Section 1A.6**: Code quality and analysis preferences

This establishes the data layer that enables runtime configuration management throughout the entire RubberDuck system.