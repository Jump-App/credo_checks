defmodule Jump.CredoChecks.NoWordSigilInterpolation do
  @moduledoc """
  Disallows interpolation in lowercase word sigils.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Use an explicit list instead of interpolation inside `~w`.

      Word sigils split their contents on whitespace after interpolation.
      Quoting a phrase does not keep it together, and interpolated values can
      unexpectedly become multiple list items. This is confusing and hard to
      remember, so it's better to avoid it altogether.

      Use an explicit list such as `["name", "net worth", "balance"]` when
      items require interpolation. This applies to all lowercase `~w` modifiers:
      strings, atoms, and charlists.
      """
    ]

  alias Credo.IssueMeta

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Sigils without a delimiter in their metadata were not written by hand (e.g., macro-generated).
  defp traverse({:sigil_w, meta, [{:<<>>, _, parts}, _modifiers]} = ast, issues, issue_meta) do
    if meta[:delimiter] && Enum.any?(parts, &(not is_binary(&1))) do
      {ast, [issue_for(issue_meta, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, meta) do
    format_issue(
      issue_meta,
      message: "Use an explicit list instead of interpolation inside `~w`.",
      trigger: "~w",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
