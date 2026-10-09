defmodule Jump.CredoChecks.AvoidModifyingStructBeforeChangeset do
  @moduledoc """
  Flags structs that are modified before being passed into a changeset function, silently bypassing all validation.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Modifying a struct before passing it into a changeset function silently bypasses validation.

      This can occur via `%{struct | field: value}`, `Map.put/3`, `struct/2`, or a helper
      function that does the same.

      Changing the struct this way bakes the new value into the changeset's base data, rather than
      tracking it as a change; changeset validation only looks at changes, so the value bypasses
      validation entirely. On both insert and update, Ecto writes *every* field of the struct
      (with changes overlaid atop the base data), so whatever you put into the struct generally
      gets written to the database unconditionally.

      (Of course, if the changeset happens to cast or put that same field, your value will instead
      be overwritten, in which case it was pointless to set it on the struct in the first place.)

      Instead, route the value through the changeset, so that it's tracked as a change
      and validated.

          # ❌ Bad — account_id skips validation, but gets written anyway
          %{existing_user | account_id: account_id}
          |> User.changeset(params)
          |> Repo.update()

          # ✅ Good
          existing_user
          |> User.changeset(params, account_id)
          |> Repo.update()

          # ❌ Bad — name skips validation, but gets written anyway
          existing_user
          |> Map.put(:name, name)
          |> User.changeset(params)
          |> Repo.update()

          # ✅ Good
          existing_user
          |> User.changeset(Map.put(params, :name, name))
          |> Repo.update()

      This check considers a "changeset function" to be any function with `changeset` as a word in its name
      (like `changeset`, `registration_changeset`, or `changeset_for_registration`), plus
      `Ecto.Changeset.cast/4` and `Ecto.Changeset.change/2`. It flags a modified struct passed to one of
      these functions directly, through a pipe, through a helper function defined in the same file whose
      return value is a modified struct, or through a variable bound to a modified struct earlier in the
      same block.

      Building a new struct (`%User{account_id: account_id}` or `struct(User, attrs)`) is not flagged,
      since that's the conventional way to set trusted fields like foreign keys on insert. Neither is a
      modified value passed as the *only* argument to a changeset function (like
      `attrs |> Map.put(:account_id, account_id) |> User.changeset()`), since that function conventionally
      takes a plain map of attributes rather than a struct when creating a new record.
      """
    ]

  alias Credo.IssueMeta

  @map_modifiers [:put, :put_new, :put_new_lazy, :merge, :replace, :replace!, :update, :update!]
  @kernel_modifiers [:struct, :struct!, :put_in, :update_in]
  @ecto_changeset_functions [:cast, :change]

  # Nodes whose subtrees may rebind variables, so a variable bound to a modified
  # struct outside them can't be assumed to hold the same value inside them.
  @rebinding_scopes [:__block__, :->, :for, :with]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    # Convenience for the rest of the code in this module: rewrite every pipe as a plain call, so that
    # the AST of piped values' look just like normal function calls.
    ast = source_file |> Credo.SourceFile.ast() |> Macro.prewalk(&unpipe/1)
    local_modifiers = local_modifiers(ast)

    Credo.Code.prewalk(ast, &traverse(&1, &2, local_modifiers, issue_meta))
  end

  defp unpipe({:|>, _, [value, {fun, meta, args}]}) when is_list(args), do: {fun, meta, [value | args]}
  defp unpipe(ast), do: ast

  defp traverse({:__block__, _, statements} = ast, issues, local_modifiers, issue_meta) do
    {ast, issues ++ modified_variable_issues(statements, local_modifiers, issue_meta)}
  end

  defp traverse(ast, issues, local_modifiers, issue_meta) do
    with {:ok, trigger, struct, line_no} <- changeset_call(ast),
         true <- returns_modification?(struct, local_modifiers) do
      {ast, issues ++ [issue_for(issue_meta, trigger, line_no)]}
    else
      _ -> {ast, issues}
    end
  end

  # Walks a block's statements in order, tracking which variables are currently
  # bound to a modified struct, and flags those variables when they're passed
  # into a changeset function in a later statement.
  defp modified_variable_issues(statements, local_modifiers, issue_meta) do
    {_modified_vars, issues} =
      Enum.reduce(statements, {MapSet.new(), []}, fn statement, {modified_vars, issues} ->
        new_issues = changeset_calls_on_variables(statement, modified_vars, issue_meta)
        {track_bindings(statement, modified_vars, local_modifiers), issues ++ new_issues}
      end)

    issues
  end

  defp changeset_calls_on_variables(statement, modified_vars, issue_meta) do
    if Enum.empty?(modified_vars) do
      []
    else
      Credo.Code.prewalk(statement, fn
        {scope, _, _}, issues when scope in @rebinding_scopes ->
          {nil, issues}

        ast, issues ->
          case changeset_call(ast) do
            {:ok, trigger, {var, _, context}, line_no} when is_atom(var) and is_atom(context) ->
              if MapSet.member?(modified_vars, var) do
                {ast, issues ++ [issue_for(issue_meta, trigger, line_no)]}
              else
                {ast, issues}
              end

            _ ->
              {ast, issues}
          end
      end)
    end
  end

  defp track_bindings({:=, _, [pattern, value]}, modified_vars, local_modifiers) do
    modified_vars = MapSet.difference(modified_vars, bound_variables(pattern))

    case pattern do
      {var, _, context} when is_atom(var) and is_atom(context) ->
        if returns_modification?(value, local_modifiers) do
          MapSet.put(modified_vars, var)
        else
          modified_vars
        end

      _ ->
        modified_vars
    end
  end

  defp track_bindings(_statement, modified_vars, _local_modifiers), do: modified_vars

  defp bound_variables(pattern) do
    pattern
    |> Credo.Code.prewalk(fn
      {:^, _, _}, vars -> {nil, vars}
      {var, _, context} = ast, vars when is_atom(var) and is_atom(context) -> {ast, [var | vars]}
      ast, vars -> {ast, vars}
    end)
    |> MapSet.new()
  end

  # The `{name, arity}` of every function defined in the file that has at least
  # one clause returning a modified struct.
  defp local_modifiers(ast) do
    ast
    |> Credo.Code.prewalk(fn
      {def_type, _, [head, body]} = ast, modifiers when def_type in [:def, :defp] and is_list(body) ->
        with {name, args} <- function_head(head),
             true <- returns_modification?(Keyword.get(body, :do), MapSet.new()) do
          {ast, [{name, length(args)} | modifiers]}
        else
          _ -> {ast, modifiers}
        end

      ast, modifiers ->
        {ast, modifiers}
    end)
    |> MapSet.new()
  end

  defp function_head({:when, _, [head, _guard]}), do: function_head(head)
  defp function_head({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp function_head({name, _, context}) when is_atom(name) and is_atom(context), do: {name, []}
  defp function_head(_head), do: :error

  defp changeset_call({{:., _, [module, name]}, meta, [struct | _] = args}) when is_atom(name) do
    if changeset_function?(module, name, args) do
      {:ok, "#{Macro.to_string(module)}.#{name}", struct, meta[:line]}
    else
      :error
    end
  end

  defp changeset_call({name, meta, [struct | _] = args}) when is_atom(name) do
    if changeset_function?(nil, name, args) do
      {:ok, Atom.to_string(name), struct, meta[:line]}
    else
      :error
    end
  end

  defp changeset_call(_ast), do: :error

  # `Ecto.Changeset.cast`, an aliased `Changeset.cast`, or an imported `cast`
  defp changeset_function?({:__aliases__, _, aliases}, name, _args) when name in @ecto_changeset_functions do
    List.last(aliases) == :Changeset
  end

  defp changeset_function?(nil, name, _args) when name in @ecto_changeset_functions, do: true

  # A changeset function called with nothing but the value to change (`User.changeset(attrs)`)
  # conventionally builds a new struct from a plain map of attributes, so that value isn't a struct.
  defp changeset_function?(_module, _name, [_single_arg]), do: false

  # `changeset` as a whole word in the name: `changeset`, `registration_changeset`,
  # `changeset_for_registration`, `changeset!`, but not `changesets`
  defp changeset_function?(_module, name, _args) do
    name
    |> to_string()
    |> String.split(["_", "!", "?"])
    |> Enum.member?("changeset")
  end

  # Whether the value an expression evaluates to is a modified struct,
  # following the branches of conditionals and the last expression of blocks.
  defp returns_modification?({:__block__, _, [_ | _] = exprs}, local_modifiers) do
    returns_modification?(List.last(exprs), local_modifiers)
  end

  defp returns_modification?({conditional, _, [_condition, branches]}, local_modifiers)
       when conditional in [:if, :unless] and is_list(branches) do
    Enum.any?(branches, fn {_, branch} -> returns_modification?(branch, local_modifiers) end)
  end

  defp returns_modification?({:case, _, [_subject, [do: clauses]]}, local_modifiers) do
    any_clause_returns_modification?(clauses, local_modifiers)
  end

  defp returns_modification?({:cond, _, [[do: clauses]]}, local_modifiers) do
    any_clause_returns_modification?(clauses, local_modifiers)
  end

  defp returns_modification?(expr, local_modifiers), do: modification?(expr, local_modifiers)

  defp any_clause_returns_modification?(clauses, local_modifiers) when is_list(clauses) do
    Enum.any?(clauses, fn
      {:->, _, [_patterns, body]} -> returns_modification?(body, local_modifiers)
      _ -> false
    end)
  end

  defp any_clause_returns_modification?(_clauses, _local_modifiers), do: false

  # %{struct | field: value}
  defp modification?({:%{}, _, [{:|, _, _}]}, _local_modifiers), do: true
  # %Schema{struct | field: value}
  defp modification?({:%, _, [_module, {:%{}, _, [{:|, _, _}]}]}, _local_modifiers), do: true
  defp modification?({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, _args}, _) when fun in @map_modifiers, do: true

  defp modification?({{:., _, [{:__aliases__, _, [:Kernel]}, fun]}, meta, args}, local_modifiers)
       when fun in @kernel_modifiers do
    modification?({fun, meta, args}, local_modifiers)
  end

  # struct(existing_struct, attrs) modifies; struct(Module, attrs) builds a new struct
  defp modification?({fun, _, [struct, _attrs]}, _modifiers) when fun in [:struct, :struct!], do: not module?(struct)
  defp modification?({fun, _, args}, _modifiers) when fun in [:put_in, :update_in] and length(args) in 2..3, do: true

  defp modification?({fun, _, args}, local_modifiers) when is_atom(fun) and is_list(args) do
    MapSet.member?(local_modifiers, {fun, length(args)})
  end

  defp modification?(_expr, _local_modifiers), do: false

  defp module?({:__aliases__, _, _}), do: true
  defp module?({:__MODULE__, _, _}), do: true
  defp module?(atom), do: is_atom(atom)

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Struct is modified before being passed to `#{trigger}`, so the modified fields bypass changeset validation. " <>
          "Pass the values through the changeset instead (e.g., in the params or via `Ecto.Changeset.put_change/3`).",
      trigger: trigger,
      line_no: line_no
    )
  end
end
