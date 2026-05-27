defmodule Jump.CredoChecks.AssertReceiveTimeout do
  @moduledoc """
  Flags `assert_receive` calls that specify an explicit timeout, and optionally
  `refute_receive` calls whose timeout exceeds a configured maximum.
  """

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [min_assert_receive_timeout: nil, max_refute_receive_timeout: nil],
    explanations: [
      check: """
      Tests should rely on the default `:ex_unit` `:assert_receive_timeout` rather than
      specifying their own. Custom timeouts inflate suite duration when the message
      never arrives and tend to drift higher over time as people paper over flaky tests.

          # ❌ Bad — explicit timeout
          assert_receive :foo, 1_000

          # ✅ Good — rely on the configured default
          assert_receive :foo

      If you want to be able to specify a *longer* timeout than default, configure
      this check with a `min_assert_receive_timeout` to enforce a floor; any literal
      timeout at or above the minimum will be allowed, and omitting the timeout
      entirely (falling back to ExUnit's default) is always allowed.

      Additionally, you can configure `max_refute_receive_timeout` to cap how long
      a `refute_receive` is allowed to block. Because `refute_receive` *always* waits
      its full timeout (including ExUnit's default when none is specified), the
      timeout sets a *minimum* bound on how long the test takes to run. When this
      param is set, every `refute_receive` must specify an explicit literal timeout
      at or below the configured maximum — bare `refute_receive` calls are flagged
      too, since they fall back to a default that also blocks the test.
      """,
      params: [
        min_assert_receive_timeout:
          "If set, allows explicit `assert_receive` timeouts that are an integer literal greater than or equal to this value. " <>
            "Defaults to `nil` (no explicit timeout allowed). As with the built-in timeout type, units are milliseconds.",
        max_refute_receive_timeout:
          "If set, flags `refute_receive` calls whose timeout is an integer literal greater than this value, " <>
            "whose timeout cannot be statically verified, or which omit an explicit timeout entirely. " <>
            "Defaults to `nil` (no `refute_receive` timeout is flagged). As with the built-in timeout type, units are milliseconds."
      ]
    ]

  alias Credo.IssueMeta

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    min_assert = Params.get(params, :min_assert_receive_timeout, __MODULE__)
    max_refute = Params.get(params, :max_refute_receive_timeout, __MODULE__)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, min_assert, max_refute))
  end

  # assert_receive pattern, timeout
  defp traverse({:assert_receive, meta, [_pattern, timeout]} = ast, issues, issue_meta, min_assert, _max_refute) do
    maybe_add_assert_issue(ast, issues, issue_meta, min_assert, timeout, meta)
  end

  # assert_receive pattern, timeout, failure_message
  defp traverse(
         {:assert_receive, meta, [_pattern, timeout, _failure_message]} = ast,
         issues,
         issue_meta,
         min_assert,
         _max_refute
       ) do
    maybe_add_assert_issue(ast, issues, issue_meta, min_assert, timeout, meta)
  end

  # refute_receive pattern (no explicit timeout — ExUnit's default still blocks the test for its full duration)
  defp traverse({:refute_receive, meta, [_pattern]} = ast, issues, issue_meta, _min_assert, max_refute) do
    maybe_add_refute_issue(ast, issues, issue_meta, max_refute, :no_timeout, meta)
  end

  # refute_receive pattern, timeout
  defp traverse({:refute_receive, meta, [_pattern, timeout]} = ast, issues, issue_meta, _min_assert, max_refute) do
    maybe_add_refute_issue(ast, issues, issue_meta, max_refute, timeout, meta)
  end

  # refute_receive pattern, timeout, failure_message
  defp traverse(
         {:refute_receive, meta, [_pattern, timeout, _failure_message]} = ast,
         issues,
         issue_meta,
         _min_assert,
         max_refute
       ) do
    maybe_add_refute_issue(ast, issues, issue_meta, max_refute, timeout, meta)
  end

  defp traverse(ast, issues, _issue_meta, _min_assert, _max_refute), do: {ast, issues}

  defp maybe_add_assert_issue(ast, issues, issue_meta, min_assert, timeout, meta) do
    if assert_allowed?(timeout, min_assert) do
      {ast, issues}
    else
      {ast, [assert_issue_for(issue_meta, min_assert, timeout, meta[:line]) | issues]}
    end
  end

  defp maybe_add_refute_issue(ast, issues, _issue_meta, nil, _timeout, _meta), do: {ast, issues}

  defp maybe_add_refute_issue(ast, issues, issue_meta, max_refute, timeout, meta) do
    if refute_allowed?(timeout, max_refute) do
      {ast, issues}
    else
      {ast, [refute_issue_for(issue_meta, max_refute, timeout, meta[:line]) | issues]}
    end
  end

  defp assert_allowed?(_timeout, nil), do: false
  defp assert_allowed?(timeout, min_assert) when is_integer(timeout), do: timeout >= min_assert
  defp assert_allowed?(_timeout, _min_assert), do: false

  defp refute_allowed?(timeout, max_refute) when is_integer(timeout), do: timeout <= max_refute
  defp refute_allowed?(_timeout, _max_refute), do: false

  defp assert_issue_for(issue_meta, nil, timeout, line_no) do
    format_issue(
      issue_meta,
      message:
        "Avoid specifying an explicit `assert_receive` timeout. Omit the timeout to use ExUnit's configured default.",
      trigger: Macro.to_string(timeout),
      line_no: line_no
    )
  end

  defp assert_issue_for(issue_meta, min_assert, timeout, line_no) do
    format_issue(
      issue_meta,
      message:
        "`assert_receive` timeout must be a literal integer >= #{min_assert}, or omitted entirely to use ExUnit's configured default.",
      trigger: Macro.to_string(timeout),
      line_no: line_no
    )
  end

  defp refute_issue_for(issue_meta, max_refute, :no_timeout, line_no) do
    format_issue(
      issue_meta,
      message:
        "`refute_receive` must specify an explicit timeout <= #{max_refute}. " <>
          "`refute_receive` always blocks for its full timeout (including ExUnit's default), setting a minimum bound " <>
          "on the entire test's runtime, so any `refute_receive` slows down the whole test suite.",
      trigger: "refute_receive",
      line_no: line_no
    )
  end

  defp refute_issue_for(issue_meta, max_refute, timeout, line_no) do
    format_issue(
      issue_meta,
      message:
        "`refute_receive` timeout must be a literal integer <= #{max_refute}. " <>
          "`refute_receive` always blocks for its full timeout, setting a minimum bound on the entire test's runtime, " <>
          "so long `refute_receive` calls slow down the whole test suite.",
      trigger: Macro.to_string(timeout),
      line_no: line_no
    )
  end
end
