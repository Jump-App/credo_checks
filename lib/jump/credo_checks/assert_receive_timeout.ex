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
      this check with a `min_assert_receive_timeout` to enforce a floor; any timeout
      at or above the minimum will be allowed, and omitting the timeout entirely
      (falling back to ExUnit's default) is always allowed.

      A timeout held in a module attribute counts, as long as the attribute is
      assigned exactly once in the same module and holds an integer literal:

          # ✅ Good — @timeout resolves to 5_000
          defmodule MyTest do
            @timeout 5_000

            test "sms arrives" do
              assert_receive {:sms, _}, @timeout
            end
          end

      Any other timeout — a variable, a function call, or an attribute that is
      never assigned, assigned more than once, or holds something other than an
      integer literal — cannot be verified statically, so it is flagged.

      Additionally, you can configure `max_refute_receive_timeout` to cap how long
      a `refute_receive` is allowed to block. Because `refute_receive` *always* waits
      its full timeout (including ExUnit's default when none is specified), the
      timeout sets a *minimum* bound on how long the test takes to run. When this
      param is set, every `refute_receive` must specify an explicit timeout the check
      can verify is at or below the configured maximum — bare `refute_receive` calls
      are flagged too, since they fall back to a default that also blocks the test.
      """,
      params: [
        min_assert_receive_timeout:
          "If set, allows explicit `assert_receive` timeouts that are an integer literal greater than or equal to this value " <>
            "(a module attribute assigned exactly once to an integer literal counts too). " <>
            "Defaults to `nil` (no explicit timeout allowed). As with the built-in timeout type, units are milliseconds.",
        max_refute_receive_timeout:
          "If set, flags `refute_receive` calls whose timeout is an integer literal greater than this value, " <>
            "whose timeout cannot be statically verified, or which omit an explicit timeout entirely. " <>
            "A module attribute assigned exactly once to an integer literal is verified like a literal. " <>
            "Defaults to `nil` (no `refute_receive` timeout is flagged). As with the built-in timeout type, units are milliseconds."
      ]
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    min_assert = Params.get(params, :min_assert_receive_timeout, __MODULE__)
    max_refute = Params.get(params, :max_refute_receive_timeout, __MODULE__)

    source_file
    |> SourceFile.ast()
    |> walk_body(%{}, issue_meta, min_assert, max_refute)
    |> Enum.sort_by(& &1.line_no)
  end

  # Walks one module body (or the top level) with that module's own attribute
  # assignments, recursing into nested modules so their attributes don't leak.
  defp walk_body(body, attrs, issue_meta, min_assert, max_refute) do
    body
    |> Macro.prewalk([], fn
      {:defmodule, _meta, [_alias, [do: nested_body]]}, issues ->
        nested_attrs = attribute_values(nested_body)
        {nil, walk_body(nested_body, nested_attrs, issue_meta, min_assert, max_refute) ++ issues}

      node, issues ->
        traverse(node, issues, issue_meta, attrs, min_assert, max_refute)
    end)
    |> elem(1)
  end

  # Groups every module attribute assignment in the body by name, so an
  # `assert_receive :foo, @timeout` can be resolved to the attribute's value.
  defp attribute_values(body) do
    body
    |> Macro.prewalk([], fn
      {:defmodule, _meta, _args}, acc -> {nil, acc}
      {:@, _meta, [{name, _, [value]}]} = node, acc when is_atom(name) -> {node, [{name, value} | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
    |> Enum.group_by(fn {name, _value} -> name end, fn {_name, value} -> value end)
  end

  # Resolves `@name` to its value when the attribute is assigned exactly once in
  # the module and holds an integer literal; every other expression is returned
  # as is, and therefore fails the `is_integer/1` bound checks below.
  defp resolve_timeout({:@, _meta, [{name, _, context}]} = timeout, attrs) when is_atom(name) and is_atom(context) do
    case Map.get(attrs, name) do
      [value] when is_integer(value) -> value
      _ -> timeout
    end
  end

  defp resolve_timeout(timeout, _attrs), do: timeout

  # assert_receive pattern, timeout
  defp traverse({:assert_receive, meta, [_pattern, timeout]} = ast, issues, issue_meta, attrs, min_assert, _max_refute) do
    maybe_add_assert_issue(ast, issues, issue_meta, min_assert, timeout, attrs, meta)
  end

  # assert_receive pattern, timeout, failure_message
  defp traverse(
         {:assert_receive, meta, [_pattern, timeout, _failure_message]} = ast,
         issues,
         issue_meta,
         attrs,
         min_assert,
         _max_refute
       ) do
    maybe_add_assert_issue(ast, issues, issue_meta, min_assert, timeout, attrs, meta)
  end

  # refute_receive pattern (no explicit timeout — ExUnit's default still blocks the test for its full duration)
  defp traverse({:refute_receive, meta, [_pattern]} = ast, issues, issue_meta, attrs, _min_assert, max_refute) do
    maybe_add_refute_issue(ast, issues, issue_meta, max_refute, :no_timeout, attrs, meta)
  end

  # refute_receive pattern, timeout
  defp traverse({:refute_receive, meta, [_pattern, timeout]} = ast, issues, issue_meta, attrs, _min_assert, max_refute) do
    maybe_add_refute_issue(ast, issues, issue_meta, max_refute, timeout, attrs, meta)
  end

  # refute_receive pattern, timeout, failure_message
  defp traverse(
         {:refute_receive, meta, [_pattern, timeout, _failure_message]} = ast,
         issues,
         issue_meta,
         attrs,
         _min_assert,
         max_refute
       ) do
    maybe_add_refute_issue(ast, issues, issue_meta, max_refute, timeout, attrs, meta)
  end

  defp traverse(ast, issues, _issue_meta, _attrs, _min_assert, _max_refute), do: {ast, issues}

  defp maybe_add_assert_issue(ast, issues, issue_meta, min_assert, timeout, attrs, meta) do
    if assert_allowed?(resolve_timeout(timeout, attrs), min_assert) do
      {ast, issues}
    else
      {ast, [assert_issue_for(issue_meta, min_assert, timeout, meta[:line]) | issues]}
    end
  end

  defp maybe_add_refute_issue(ast, issues, _issue_meta, nil, _timeout, _attrs, _meta), do: {ast, issues}

  defp maybe_add_refute_issue(ast, issues, issue_meta, max_refute, timeout, attrs, meta) do
    if refute_allowed?(resolve_timeout(timeout, attrs), max_refute) do
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
