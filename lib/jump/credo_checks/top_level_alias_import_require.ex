defmodule Jump.CredoChecks.TopLevelAliasImportRequire do
  @moduledoc """
  Ensures that `alias`, `import`, and `require` statements are at the top level of a module.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [],
    explanations: [
      check: """
      Ensures that `alias`, `import`, and `require` statements are at the top level of a module.

      Placing `alias`, `import`, or `require` statements inside functions, `describe` blocks, or
      `test` blocks makes code harder to read and understand. Instead, these should be declared
      at the module level.

          # Bad
          defmodule Foo do
            def bar(baz) do
              import Ecto.Query
              # ...
            end
          end

          # Good
          defmodule Foo do
            import Ecto.Query

            def bar(baz) do
              # ...
            end
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.ast()
    |> find_nested_import_alias(issue_meta)
  end

  defp find_nested_import_alias(ast, issue_meta) do
    {_ast, issues} = Macro.prewalk(ast, [], &traverse(&1, &2, issue_meta, 0))
    issues
  end

  defp traverse({:defmodule, _, [_module_name, [do: body]]}, issues, issue_meta, _depth) do
    {_body, new_issues} = traverse_module_body(body, [], issue_meta)
    {{:__skip__, nil, nil}, issues ++ new_issues}
  end

  defp traverse(node, issues, _issue_meta, _depth), do: {node, issues}

  defp traverse_module_body({:__block__, _, statements}, issues, issue_meta) do
    new_issues =
      Enum.flat_map(statements, fn statement ->
        check_statement(statement, issue_meta)
      end)

    {{:__skip__, nil, nil}, issues ++ new_issues}
  end

  defp traverse_module_body(single_statement, issues, issue_meta) do
    new_issues = check_statement(single_statement, issue_meta)
    {{:__skip__, nil, nil}, issues ++ new_issues}
  end

  @block_keywords [:def, :defp, :describe, :test, :setup, :setup_all]

  defp check_statement({kw, _, args}, issue_meta) when kw in @block_keywords and is_list(args) do
    Enum.flat_map(args, fn
      [do: body] -> find_issues_in_do_block(body, issue_meta)
      _ -> []
    end)
  end

  defp check_statement(_node, _issue_meta), do: []

  defp find_issues_in_do_block(body, issue_meta) do
    {_ast, {issues, skip?}} =
      Macro.prewalk(body, {[], false}, fn
        # Skip checking macro definitions, since imports/aliases inside quote blocks
        # are meant to be injected into calling modules, not used in the current module.
        {:quote, _, _}, {acc, _skip?} ->
          {nil, {acc, true}}

        # Also skip nested defmodule (used in tests)
        {:defmodule, _, _}, {acc, _skip?} ->
          {nil, {acc, true}}

        {kw, meta, [_ | _]} = node, {acc, false} when kw in [:import, :alias, :require] ->
          {node, {[create_issue(issue_meta, kw, meta[:line]) | acc], false}}

        node, issues_and_skip ->
          {node, issues_and_skip}
      end)

    if skip? do
      []
    else
      issues
    end
  end

  defp create_issue(issue_meta, type, line_no) do
    format_issue(
      issue_meta,
      message: "`#{type}` statements should be at the top level of the module, not nested inside functions or blocks.",
      trigger: "#{type}",
      line_no: line_no
    )
  end
end
