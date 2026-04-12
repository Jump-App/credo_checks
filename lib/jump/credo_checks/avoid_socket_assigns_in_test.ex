defmodule Jump.CredoChecks.AvoidSocketAssignsInTest do
  @moduledoc """
  Ensures that tests don't introspect `socket.assigns`.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      excluded: []
    ],
    explanations: [
      check: """
      Tests should assert expected behavior from the user's perspective rather than
      coupling to internal LiveView state via `socket.assigns`.

      Instead of accessing `socket.assigns.foo`, use PhoenixTest-style assertions
      like `assert_has`, `await_has`, `await_gone`, etc.

      Use `@moduletag :plug_test`, `@describetag :plug_test`, or `@tag :plug_test`
      to opt out for tests that legitimately need to test Plug/conn assigns.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    if String.ends_with?(filename, "_test.exs") do
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  # var.assigns.field — e.g. socket.assigns.foo, result_socket.assigns.bar
  defp traverse({{:., meta, [{{:., _, [{var_name, _, _}, :assigns]}, _, _}, _field]}, _, _} = ast, issues, issue_meta)
       when is_atom(var_name) and var_name != :conn do
    maybe_add_issue(ast, meta, issues, issue_meta, "socket.assigns")
  end

  # var.assigns standalone — e.g. Map.has_key?(socket.assigns, :key)
  defp traverse({{:., meta, [{var_name, _, _}, :assigns]}, _, _} = ast, issues, issue_meta)
       when is_atom(var_name) and var_name != :conn do
    maybe_add_issue(ast, meta, issues, issue_meta, "socket.assigns")
  end

  defp traverse(node, issues, _issue_meta) do
    {node, issues}
  end

  defp maybe_add_issue(ast, meta, issues, issue_meta, trigger) do
    if plug_test_module?(issue_meta) or plug_test?(issue_meta, meta[:line]) do
      {nil, issues}
    else
      {nil, [create_issue(issue_meta, Macro.to_string(ast), meta[:line], trigger) | issues]}
    end
  end

  defp plug_test_module?({_, %SourceFile{} = source_file, _}) do
    source_file
    |> Credo.SourceFile.ast()
    |> plug_test_module?()
  end

  defp plug_test_module?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{:moduletag, _, [:plug_test]}]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp plug_test?({_, %SourceFile{} = source_file, _}, line_no) do
    ast = Credo.SourceFile.ast(source_file)

    describetag_plug_test?(ast, line_no) or
      test_level_plug_test?(ast, line_no)
  end

  defp test_level_plug_test?(ast, line_no) do
    this_test_line = most_recent_test_line(ast, line_no)
    prev_test_line = most_recent_test_line(ast, this_test_line)
    plug_test_tag_within_range?(ast, (prev_test_line + 1)..this_test_line//1)
  end

  defp describetag_plug_test?(ast, line_no) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:describe, _, [_name, [do: block]]} = node, acc ->
          if block_contains_line?(block, line_no) and
               block_has_tag?(block, :describetag, :plug_test) do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp block_has_tag?({:__block__, _, statements}, tag_name, tag_value) do
    Enum.any?(statements, &match?({:@, _, [{^tag_name, _, [^tag_value]}]}, &1))
  end

  defp block_has_tag?(_, _, _), do: false

  defp block_contains_line?(ast, line_no) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {_, meta, _} = node, acc when is_list(meta) ->
          if meta[:line] == line_no, do: {node, true}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp plug_test_tag_within_range?(ast, start..last//1) when start <= last do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{:tag, meta, [:plug_test]}]} = node, acc ->
          line = meta[:line]

          if line in start..last//1 do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp plug_test_tag_within_range?(_ast, _zero_or_negative_range), do: false

  defp most_recent_test_line(ast, line_no) do
    {_ast, found} =
      Macro.prewalk(ast, 0, fn
        {:test, meta, _body} = node, acc ->
          line = meta[:line]

          if line < line_no do
            {node, line}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp create_issue(issue_meta, trigger, line_no, trigger_text) do
    format_issue(
      issue_meta,
      message: "Avoid introspecting #{trigger_text} in tests. Test user-observable behavior instead.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
