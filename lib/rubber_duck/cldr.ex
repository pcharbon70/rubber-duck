defmodule RubberDuck.Cldr do
  @moduledoc """
  CLDR (Common Locale Data Repository) configuration for RubberDuck.

  Provides internationalization and localization support.
  """
  use Cldr,
    locales: ["en"],
    default_locale: "en"
end
