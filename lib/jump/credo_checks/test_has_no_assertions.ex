defmodule Jump.CredoChecks.TestHasNoAssertions do
  @moduledoc """
  Flags test blocks that contain zero assertion calls.

  A test without assertions only verifies that code doesn't crash,
  which provides minimal value. Add an assert, refute, or pattern
  match assertion to verify behavior.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Tests should have at least one assertion. A test without assertions
      only verifies that code doesn't crash, which provides minimal value.

      Add an assert, refute, or pattern match assertion to verify behavior.
      """
    ],
    param_defaults: [
      custom_assertion_functions: []
    ]

  @default_assertion_functions ~w(
    assert refute assert_raise assert_receive assert_received
    refute_receive refute_received assert_in_delta refute_in_delta
    assert_has refute_has assert_empty refute_empty
    assert_equal_ci assert_ids_match assert_sorted_equal
    assert_issue assert_issues refute_issues assert_enqueued refute_enqueued
    assert_reply assert_broadcast assert_push
    flunk
    json_response text_response html_response response
    assert_element refute_element assert_path assert_redirect
    assert_patched assert_redirected_to assert_redirected
    assert_html refute_html assert_email_sent assert_span
    assert_query_param
    assert_patch assert_text_in_order refute_push_event assert_push_event
    assert_connection_modal_opened
  )a

  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    if String.ends_with?(filename, "_test.exs") do
      functions = List.wrap(params[:custom_assertion_functions]) ++ @default_assertion_functions
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, functions))
    else
      []
    end
  end

  # Test block without context: test "name" do ... end
  defp traverse({:test, meta, [name, [do: body]]} = _ast, issues, issue_meta, functions) when is_binary(name) do
    if has_assertion?(body, functions) do
      {:ok, issues}
    else
      {:ok, [issue_for(issue_meta, meta, name) | issues]}
    end
  end

  # Test block with context: test "name", %{} do ... end
  defp traverse({:test, meta, [name, _context, [do: body]]} = _ast, issues, issue_meta, functions)
       when is_binary(name) do
    if has_assertion?(body, functions) do
      {:ok, issues}
    else
      {:ok, [issue_for(issue_meta, meta, name) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta, _functions) do
    {ast, issues}
  end

  defp issue_for(issue_meta, meta, name) do
    format_issue(
      issue_meta,
      message: "This test has no assertions. Add an assert/refute call, or delete the test if it provides no value.",
      trigger: name,
      line_no: meta[:line]
    )
  end

  # Walks the test body AST looking for any assertion call.
  defp has_assertion?(body, functions) do
    {_, found?} = Macro.prewalk(body, false, &find_assertion(&1, &2, functions))
    found?
  end

  # Short-circuit once we've found an assertion.
  defp find_assertion(node, true, _functions), do: {node, true}

  # Structural pattern match: {:ok, _} = expr, %{key: val} = expr, [h | t] = expr
  # Only counts when the LHS is a tuple, map, or list — not a bare variable.
  # IMPORTANT: This clause must come before the generic function call clause,
  # because {:=, meta, [pattern, expr]} also matches {atom, meta, list}.
  defp find_assertion({:=, _, [pattern, _expr]} = node, false, _functions) do
    if structural_pattern?(pattern) do
      {node, true}
    else
      {node, false}
    end
  end

  # case expression with specific pattern clauses counts as an assertion
  # IMPORTANT: Must come before the generic function call clause for the same reason.
  defp find_assertion({:case, _, [_expr, [do: clauses]]} = node, false, _functions) when is_list(clauses) do
    {node, case_has_assertion?(clauses)}
  end

  # Piped case: expr |> case do ... end
  # In AST the case node only has one arg (the [do: clauses]) since the expr comes from the pipe.
  defp find_assertion({:case, _, [[do: clauses]]} = node, false, _functions) when is_list(clauses) do
    {node, case_has_assertion?(clauses)}
  end

  # Piped assertion: expr |> assert_has(...)
  # The pipe operator rewrites `a |> f(b)` to `{:|>, _, [a, {f, _, [b]}]}`.
  # IMPORTANT: Must come before the generic function call clause for the same reason.
  defp find_assertion({:|>, _, [_lhs, {fn_name, _meta, _args}]} = node, false, functions) when is_atom(fn_name) do
    if assert_function?(fn_name, functions) do
      {node, true}
    else
      {node, false}
    end
  end

  # Qualified assertion call: Module.assert_has(expr), Playwright.assert_has(expr), etc.
  # In AST: {{:., _, [{:__aliases__, _, _}, fn_name]}, _, args}
  defp find_assertion({{:., _, [{:__aliases__, _, _}, fn_name]}, _meta, args} = node, false, functions)
       when is_atom(fn_name) and is_list(args) do
    if assert_function?(fn_name, functions) do
      {node, true}
    else
      {node, false}
    end
  end

  # Direct assertion call: assert(expr), refute(expr), etc.
  defp find_assertion({fn_name, _meta, args} = node, false, functions) when is_atom(fn_name) and is_list(args) do
    if assert_function?(fn_name, functions) do
      {node, true}
    else
      {node, false}
    end
  end

  defp find_assertion(node, false, _functions), do: {node, false}

  defp assert_function?(fn_name, functions) do
    fn_name in functions or String.starts_with?(to_string(fn_name), ["assert_", "refute_"])
  end

  defp case_has_assertion?(clauses) do
    Enum.any?(clauses, fn
      {:->, _, [[pattern], _body]} -> structural_pattern?(pattern) or literal_value?(pattern)
      _ -> false
    end)
  end

  # A map literal: %{...}
  defp structural_pattern?({:%{}, _, _}), do: true

  # A list literal
  defp structural_pattern?(list) when is_list(list), do: true

  # A cons cell: [h | t]
  defp structural_pattern?({:|, _, _}), do: true

  # A two-element tuple in AST: {a, b} where `a` is not a special form atom.
  # In Elixir AST, a two-element tuple `{:ok, val}` is represented literally
  # as `{:ok, ast_node}` — not wrapped in a `{:{}, ...}` tuple.
  # We need to distinguish from AST nodes like `{:some_var, meta, context}` (3-element)
  # and special forms. A two-element tuple where the first element is an atom
  # that is NOT a known special form/operator is a structural pattern.
  defp structural_pattern?({first, _second}) when is_atom(first) do
    first not in [:__block__, :__aliases__, :., :@, :&, :fn, :|>, :<<>>, :^]
  end

  # Two-element tuple where first element is not an atom (e.g., {var, val})
  defp structural_pattern?({_first, _second}), do: true

  # Explicit tuple: {a, b, c} with 3+ elements is `{:{}, _, elements}`
  defp structural_pattern?({:{}, _, _}), do: true

  defp structural_pattern?(_), do: false

  # Literal values used in case clauses act as assertions (crash if no match).
  defp literal_value?(value) when is_number(value), do: true
  defp literal_value?(value) when is_binary(value), do: true
  defp literal_value?(value) when is_atom(value) and value not in [nil, true, false], do: true
  defp literal_value?(_), do: false
end
