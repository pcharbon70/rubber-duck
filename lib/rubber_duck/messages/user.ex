defmodule RubberDuck.Messages.User do
  @moduledoc """
  Typed messages for user management operations.
  """

  defmodule ValidateSession do
    @moduledoc "Message to validate a user session"
    defstruct [:user_id, :session_id, :metadata]
  end

  defmodule UpdatePreferences do
    @moduledoc "Message to update user preferences"
    defstruct [:user_id, :preferences, :merge, metadata: %{}]
  end

  defmodule TrackActivity do
    @moduledoc "Message to track user activity"
    defstruct [:user_id, :action, :context, :timestamp]
  end

  defmodule GenerateSuggestions do
    @moduledoc "Message to generate proactive suggestions"
    defstruct [:user_id, :context, :limit, metadata: %{}]
  end

  defmodule SessionCreated do
    @moduledoc "Message indicating a session was created"
    defstruct [:user_id, :session_id, :timestamp]
  end

  defmodule SessionExpired do
    @moduledoc "Message indicating a session expired"
    defstruct [:user_id, :session_id, :count, :timestamp]
  end

  defmodule PatternDetected do
    @moduledoc "Message indicating a pattern was detected"
    defstruct [:user_id, :patterns, :confidence, :timestamp]
  end

  defmodule PreferenceLearned do
    @moduledoc "Message indicating a preference was learned"
    defstruct [:user_id, :preferences, :confidence, :timestamp]
  end

  defmodule SuggestionGenerated do
    @moduledoc "Message indicating suggestions were generated"
    defstruct [:user_id, :suggestions, :count, :timestamp]
  end

  defmodule UserSignedIn do
    @moduledoc "Message indicating a user signed in"
    defstruct [:user_id, :session_id, :timestamp, metadata: %{}]
  end

  defmodule UserSignedOut do
    @moduledoc "Message indicating a user signed out"
    defstruct [:user_id, :session_id, :timestamp, metadata: %{}]
  end

  defmodule ActionPerformed do
    @moduledoc "Message indicating a user performed an action"
    defstruct [:user_id, :action, :context, :timestamp, metadata: %{}]
  end
end