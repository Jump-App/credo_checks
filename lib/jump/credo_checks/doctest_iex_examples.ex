defmodule Jump.CredoChecks.DoctestIExExamples do
  @moduledoc """
  Ensures that modules with interactive Elixir examples in their docstrings
  have a corresponding test file that runs those doctests.
  """
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      derive_test_path: fn filename ->
        filename
        |> String.replace_leading("lib/", "test/")
        |> String.replace_trailing(".ex", "_test.exs")
      end
    ],
    explanations: [
      check: """
      Modules that contain interactive Elixir examples (`iex>`) in their
      `@doc` or `@moduledoc` attributes should have those examples exercised
      via `doctest` in a corresponding test file.

      For a file at `lib/jump/foo.ex` defining `Jump.Foo`, this check expects
      a sibling test file `lib/jump/foo_test.exs` that contains:

          doctest Jump.Foo

      Without this, the examples are just decoration — they won't be
      compiled or verified, and can silently drift out of date.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    if contains_doctestable_example?(source_file) do
      check_for_doctest(source_file, params)
    else
      []
    end
  end

  defp contains_doctestable_example?(%SourceFile{filename: filename} = source_file) do
    String.ends_with?(filename, ".ex") and SourceFile.source(source_file) =~ ~r/iex>/
  end

  defp check_for_doctest(source_file, params) do
    ast = SourceFile.ast(source_file)

    case find_iex_in_docs(ast) do
      nil ->
        []

      iex_line ->
        issue_meta = IssueMeta.for(source_file, params)
        module_name = extract_module_name(ast)

        derive_test_path =
          case params[:derive_test_path] do
            fun when is_function(fun, 1) ->
              fun

            _ ->
              fn filename ->
                filename
                |> String.replace_leading("lib/", "test/")
                |> String.replace_trailing(".ex", "_test.exs")
              end
          end

        if module_name do
          test_file = derive_test_path.(source_file.filename)
          check_test_file(test_file, module_name, iex_line, issue_meta)
        else
          []
        end
    end
  end

  # Walk the AST looking for @doc or @moduledoc attributes whose string
  # value contains "iex>". Returns the line number of the attribute, or nil.
  defp find_iex_in_docs(ast) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        # @doc "..." or @moduledoc "..."
        {:@, _, [{attr, meta, [value]}]} = node, nil when attr in [:doc, :moduledoc] ->
          if doc_contains_iex?(value) do
            {node, meta[:line]}
          else
            {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp doc_contains_iex?(value) when is_binary(value), do: String.contains?(value, "iex>")

  # Handle heredoc-style sigils like ~S, which appear as {:sigil_S, _, [string, _]}
  defp doc_contains_iex?({:sigil_S, _, [{:<<>>, _, [value]}, _]}) when is_binary(value),
    do: String.contains?(value, "iex>")

  defp doc_contains_iex?({:<<>>, _, parts}) do
    Enum.any?(parts, fn
      part when is_binary(part) -> String.contains?(part, "iex>")
      _ -> false
    end)
  end

  defp doc_contains_iex?(_), do: false

  defp extract_module_name(ast) do
    {_ast, module_name} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, nil ->
          {node, parts |> Module.concat() |> inspect()}

        node, acc ->
          {node, acc}
      end)

    module_name
  end

  defp check_test_file(test_file, module_name, iex_line, issue_meta) do
    cond do
      File.exists?(test_file) and test_file_has_doctest?(test_file, module_name) ->
        []

      File.exists?(test_file) ->
        [
          format_issue(issue_meta,
            message: "Module `#{module_name}` has iex> examples but its test file is missing `doctest #{module_name}`.",
            trigger: "iex>",
            line_no: iex_line
          )
        ]

      # When the exact test file doesn't exist (e.g. it was split into multiple files),
      # check sibling test files in the same directory for the doctest.
      sibling_has_doctest?(test_file, module_name) ->
        []

      true ->
        [
          format_issue(issue_meta,
            message: "Module `#{module_name}` has iex> examples but no test file at `#{Path.basename(test_file)}`.",
            trigger: "iex>",
            line_no: iex_line
          )
        ]
    end
  end

  defp sibling_has_doctest?(test_file, module_name) do
    test_file
    |> Path.dirname()
    |> Path.join("*_test.exs")
    |> Path.wildcard()
    |> Enum.any?(&test_file_has_doctest?(&1, module_name))
  end

  defp test_file_has_doctest?(test_file, module_name) do
    components = String.split(module_name, ".")
    possible_names = for i <- 1..length(components), do: components |> Enum.take(-i) |> Enum.join(".")

    test_file
    # sobelow_skip ["Traversal.FileModule"]
    |> File.read!()
    |> String.contains?(Enum.map(possible_names, &"doctest #{&1}"))
  end
end
