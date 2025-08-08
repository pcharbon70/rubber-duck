defmodule RubberDuckWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.
  """
  use RubberDuckWeb, :html

  embed_templates "page_html/*"
end