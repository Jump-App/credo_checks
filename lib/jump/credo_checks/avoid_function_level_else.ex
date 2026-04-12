defmodule Jump.CredoChecks.AvoidFunctionLevelElse do
  @moduledoc """
  Ensures that `else` is not used at the top-level of `def`/`defp` function bodies.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [],
    explanations: [
      check: """
      Ensures that `else` is not used at the top-level of `def`/`defp` function bodies.

      Elixir allows `else` at the function level because the function body acts
      as an implicit `try`. However, this is almost always a mistake from a
      botched refactor—e.g., removing a `with` block but leaving its `else`
      clause behind. The code will compile without warnings, but behaves unexpectedly
      (raising `TryClauseError` if no clause matches).

          # ❌ Bad — function-level else
          def foo(bar) do
            something(bar)
          else
            {:error, reason} -> handle_error(reason)
          end

          # Good — use with/else or case instead
          def foo(bar) do
            with {:ok, result} <- something(bar) do
              result
            else
              {:error, reason} -> handle_error(reason)
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
    |> find_function_level_else(issue_meta)
  end

  defp find_function_level_else(ast, issue_meta) do
    {_ast, issues} = Macro.prewalk(ast, [], &traverse(&1, &2, issue_meta))
    issues
  end

  defp traverse({kind, meta, [_name_args, block_kw]} = node, issues, issue_meta)
       when kind in [:def, :defp] and is_list(block_kw) do
    if Keyword.has_key?(block_kw, :else) do
      issue =
        format_issue(
          issue_meta,
          message:
            "Function-level `else` is almost always a mistake. " <>
              "Use `with`/`else`, `case`, or `try`/`rescue` instead.",
          trigger: "#{kind}",
          line_no: meta[:line]
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}
end
