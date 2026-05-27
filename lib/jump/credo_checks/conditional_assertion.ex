defmodule Jump.CredoChecks.ConditionalAssertion do
  @moduledoc """
  Flags `assert` calls whose top-level expression is a boolean `or`/`||`,
  since those make the test non-deterministic.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Tests should be deterministic: you should be able to confidently say which
      branch will be taken every time the test runs. An assertion of the form
      `assert a or b` (or `assert a || b`) indicates you don't really know what's
      going on in your test.

      If you genuinely don't know which value to expect, that's a signal the test
      setup is non-deterministic; fix the source of the non-determinism instead
      of papering over it in the assertion.

          # ❌ Non-deterministic
          assert foo == :bar or baz == :bop
          assert foo in [:bar, :baz] || bop in [:whiz, :bang]

          # ✅ Deterministic
          assert foo == :bar
          assert bop in [:whiz, :bang]
      """
    ]

  alias Credo.IssueMeta

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:assert, meta, [{op, _, [_, _]} = expr | _rest]} = ast, issues, issue_meta) when op in [:or, :||] do
    {ast, [issue_for(issue_meta, Macro.to_string(expr), meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Asserting on an `or`/`||` expression makes the test non-deterministic — it passes for either branch. Assert the specific value you expect.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
