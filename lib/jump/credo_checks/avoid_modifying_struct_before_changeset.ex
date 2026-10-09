defmodule Jump.CredoChecks.AvoidModifyingStructBeforeChangeset do
  @moduledoc """
  Flags structs that are modified before being passed into a changeset function, silently bypassing validation.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Modifying a struct before passing it into a changeset function means the new value is never tracked as a change.

      This can occur via `%{struct | field: value}`, `Map.put/3`, `struct/2`, or a helper
      function that does the same.

      Changing the struct this way bakes the new value into the changeset's base data. Since changeset
      validation only looks at changes, this change bypasses validation entirely. What happens next
      depends on how you persist the changeset:

      - On insert, Ecto writes *every* field of the struct (with changes overlaid atop the base data),
        so the unvalidated value gets written to the database.
      - On update, Ecto writes *only* the changes, so the value is silently dropped, but the struct
        returned from `Repo.update/2` still contains it, so it *looks* like the value was saved.

      (Casting or putting that same field in the changeset doesn't help. If the new value differs from
      the one on the struct, it overwrites yours, so setting it on the struct was pointless. If it's the
      same, Ecto sees no change at all, with the consequences above.)

      Instead, route the value through the changeset, so that it's tracked as a change
      and validated.

          # ❌ Bad — Repo.update/2 never saves account_id, though the returned user has it
          %{existing_user | account_id: account_id}
          |> User.changeset(params)
          |> Repo.update()

          # ✅ Good
          existing_user
          |> User.changeset(params, account_id)
          |> Repo.update()

          # ❌ Bad — name is saved without validation (like length, uniqueness, etc.)
          %User{}
          |> Map.put(:name, name)
          |> User.changeset(params)
          |> Repo.insert()

          # ✅ Good
          %User{}
          |> User.changeset(Map.put(params, :name, name))
          |> Repo.insert()

      This check considers a "changeset function" to be any function with `changeset` as a word in its name
      (like `changeset`, `registration_changeset`, or `changeset_for_registration`), plus
      `Ecto.Changeset.cast/4` and `Ecto.Changeset.change/2`. It flags a modified struct passed to one of
      these functions directly, through a pipe, through a helper function defined in the same file whose
      return value is a modified struct, or through a variable bound to a modified struct earlier in the
      same scope.

      Cases this check does not flag:

      - Building a new struct (`%User{account_id: account_id}` or `struct(User, attrs)`),
        since that's the conventional way to set trusted fields like foreign keys on insert.
        This includes `struct/2` called on a variable with `module` in its name (like
        `struct(schema_module, attrs)`), since that variable presumably holds a module rather than a struct.
      - A modified value passed as the *only* argument to a changeset function (like
        `attrs |> Map.put(:account_id, account_id) |> User.changeset()`), since that function conventionally
        takes a plain map of attributes rather than a struct when creating a new record.
      - A modified value held in a variable named `map`, `attrs`, `attributes`, `params`, or `parameters`
        (like `attrs |> Map.put(:account_id, account_id) |> Rubric.changeset(opts)`), since by convention
        that's a plain map of attributes rather than a struct.
      - A struct modified *within* a changeset function (like filling in a default before calling `cast/4`).
        This is somewhat suspect, but we'll assume the changeset function author knows what they're doing.
      - A changeset passed only to `Phoenix.Component.to_form/2` or `Ecto.Changeset.apply_changes/1`.
        Since these are temporary values (not persisted), the modified struct here is less risky.
      """
    ]

  alias Credo.IssueMeta

  @map_modifiers [:put, :put_new, :put_new_lazy, :merge, :replace, :replace!, :update, :update!]
  @kernel_modifiers [:struct, :struct!, :put_in, :update_in]
  @ecto_changeset_functions [:cast, :change]

  # Functions that consume a changeset without ever persisting it: `to_form` only populates a form,
  # and `apply_changes` only builds the resulting struct in memory. A modified struct passed to either
  # one just sets initial or preview values.
  @non_persisting_functions [:to_form, :apply_changes]

  # Functions that persist a struct passed to them, either directly (`Repo.insert/2`, `Ecto.Multi.insert/4`)
  # or as part of a parent changeset (`put_embed/4`, `put_assoc/4`).
  @struct_persisting_functions [:insert, :insert!, :put_embed, :put_assoc]

  # Variables with these names conventionally hold a plain map of params rather than a struct,
  # so modifying them before a changeset function is fine.
  @params_names [:map, :attrs, :attributes, :params, :parameters]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    # Convenience for the rest of the code in this module: rewrite every pipe as a plain call, so that
    # the AST of piped values looks just like normal function calls.
    ast =
      source_file
      |> Credo.SourceFile.ast()
      |> Macro.prewalk(&(&1 |> unpipe() |> unwrap_persisted_apply_changes() |> drop_non_persisting_call()))
      |> Macro.postwalk(&drop_unused_changeset_bindings/1)

    local_modifiers = local_modifiers(ast)

    find_issues(ast, MapSet.new(), local_modifiers, issue_meta)
  end

  defp unpipe({:|>, _, [value, {fun, meta, args}]}) when is_list(args), do: {fun, meta, [value | args]}
  defp unpipe(ast), do: ast

  # `apply_changes` doesn't persist anything itself, but the struct it returns does get persisted when
  # passed straight to one of the @struct_persisting_functions, so unwrap it there to keep the changeset
  # inside it from being dropped.
  defp unwrap_persisted_apply_changes({fun, meta, args}) when fun in @struct_persisting_functions and is_list(args) do
    {fun, meta, Enum.map(args, &unwrap_apply_changes/1)}
  end

  defp unwrap_persisted_apply_changes({{:., _, [_module, fun]} = call, meta, args})
       when fun in @struct_persisting_functions and is_list(args) do
    {call, meta, Enum.map(args, &unwrap_apply_changes/1)}
  end

  defp unwrap_persisted_apply_changes(ast), do: ast

  defp unwrap_apply_changes(arg) do
    case unpipe(arg) do
      {:apply_changes, _, [changeset]} -> changeset
      {{:., _, [_module, :apply_changes]}, _, [changeset]} -> changeset
      _ -> arg
    end
  end

  defp drop_non_persisting_call({fun, _, args}) when fun in @non_persisting_functions and is_list(args), do: nil

  defp drop_non_persisting_call({{:., _, [_module, fun]}, _, args})
       when fun in @non_persisting_functions and is_list(args), do: nil

  defp drop_non_persisting_call(ast), do: ast

  # With non-persisting calls dropped, a changeset variable that was only passed to them is never
  # referenced again, so drop the binding that built it, along with any that tweak it afterward
  # (like `changeset = %{changeset | action: :validate}`). Walks the statements in reverse so each
  # binding is checked against the statements kept after it. The last statement is the block's
  # value, so it's always kept.
  defp drop_unused_changeset_bindings({:__block__, meta, [_ | _] = statements}) do
    [last | rest] = Enum.reverse(statements)

    {kept, _referenced} =
      Enum.reduce(rest, {[last], referenced_variables(last)}, fn statement, {kept, referenced} ->
        if unused_changeset_binding?(statement, referenced) do
          {kept, referenced}
        else
          {[statement | kept], MapSet.union(referenced, referenced_variables(statement))}
        end
      end)

    {:__block__, meta, kept}
  end

  defp drop_unused_changeset_bindings(ast), do: ast

  defp unused_changeset_binding?({:=, _, [{var, _, context}, value]}, referenced)
       when is_atom(var) and is_atom(context) do
    not MapSet.member?(referenced, var) and
      (match?({:ok, _, _, _}, changeset_call(value)) or modification?(value, MapSet.new()))
  end

  defp unused_changeset_binding?(_statement, _referenced), do: false

  defp referenced_variables(ast) do
    ast
    |> Credo.Code.prewalk(fn
      {var, _, context} = ast, vars when is_atom(var) and is_atom(context) -> {ast, [var | vars]}
      ast, vars -> {ast, vars}
    end)
    |> MapSet.new()
  end

  # Walks the AST, tracking which variables are currently bound to a modified struct, and flags each
  # changeset function called on a modified struct, whether inline or through one of those variables.
  defp find_issues(ast, modified_vars, local_modifiers, issue_meta) do
    Credo.Code.prewalk(ast, fn ast, issues ->
      case scoped_issues(ast, modified_vars, local_modifiers, issue_meta) do
        {:ok, scoped_issues} -> {nil, issues ++ scoped_issues}
        :error -> {ast, issues ++ changeset_call_issues(ast, modified_vars, local_modifiers, issue_meta)}
      end
    end)
  end

  # Nodes that change which variables are bound to a modified struct within them, so they walk
  # their own children (returning :error for any other node).
  # A changeset function is free to modify its own struct (e.g., to fill in a default),
  # so skip its body entirely.
  defp scoped_issues({def_type, _, [head | _]}, _modified_vars, _local_modifiers, _issue_meta)
       when def_type in [:def, :defp] do
    case function_head(head) do
      {name, _args} -> if changeset_name?(name), do: {:ok, []}, else: :error
      :error -> :error
    end
  end

  # Walks a block's statements in order, so a variable bound to a modified struct
  # is tracked through the statements (including nested blocks) that follow it.
  defp scoped_issues({:__block__, _, statements}, modified_vars, local_modifiers, issue_meta)
       when is_list(statements) do
    {_modified_vars, issues} =
      Enum.reduce(statements, {modified_vars, []}, fn statement, {modified_vars, issues} ->
        new_issues = find_issues(statement, modified_vars, local_modifiers, issue_meta)
        {track_bindings(statement, modified_vars, local_modifiers), issues ++ new_issues}
      end)

    {:ok, issues}
  end

  # The patterns of a `case`, `fn`, `receive`, etc. clause may shadow a modified variable...
  defp scoped_issues({:->, _, [patterns, body]}, modified_vars, local_modifiers, issue_meta) do
    {:ok, find_issues(body, MapSet.difference(modified_vars, bound_variables(patterns)), local_modifiers, issue_meta)}
  end

  # ...as may the generators of a `for` or the clauses of a `with`
  defp scoped_issues({form, _, args}, modified_vars, local_modifiers, issue_meta)
       when form in [:for, :with] and is_list(args) do
    bound_vars =
      Enum.reduce(args, MapSet.new(), fn
        {op, _, [pattern, _value]}, vars when op in [:<-, :=] -> MapSet.union(vars, bound_variables(pattern))
        _arg, vars -> vars
      end)

    {:ok, find_issues(args, MapSet.difference(modified_vars, bound_vars), local_modifiers, issue_meta)}
  end

  defp scoped_issues(_ast, _modified_vars, _local_modifiers, _issue_meta), do: :error

  defp changeset_call_issues(ast, modified_vars, local_modifiers, issue_meta) do
    with {:ok, trigger, struct, line_no} <- changeset_call(ast),
         true <- returns_modification?(struct, local_modifiers, modified_vars) do
      [issue_for(issue_meta, trigger, line_no)]
    else
      _ -> []
    end
  end

  defp track_bindings({:=, _, [pattern, value]}, modified_vars, local_modifiers) do
    # The value is evaluated before the pattern rebinds anything, so check it against the current bindings
    value_modified? = returns_modification?(value, local_modifiers, modified_vars)
    modified_vars = MapSet.difference(modified_vars, bound_variables(pattern))

    case pattern do
      {var, _, context} when is_atom(var) and is_atom(context) and var not in @params_names and value_modified? ->
        MapSet.put(modified_vars, var)

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
             true <- returns_modification?(Keyword.get(body, :do), MapSet.new(), MapSet.new()) do
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
  defp changeset_function?(_module, name, _args), do: changeset_name?(name)

  defp changeset_name?(name) do
    name
    |> to_string()
    |> String.split(["_", "!", "?"])
    |> Enum.member?("changeset")
  end

  # Whether the value an expression evaluates to is a modified struct, following the branches of
  # conditionals, the last expression of blocks, and variables bound to a modified struct.
  defp returns_modification?({:__block__, _, [_ | _] = exprs}, local_modifiers, modified_vars) do
    {statements, [last]} = Enum.split(exprs, -1)
    modified_vars = Enum.reduce(statements, modified_vars, &track_bindings(&1, &2, local_modifiers))
    returns_modification?(last, local_modifiers, modified_vars)
  end

  defp returns_modification?({conditional, _, [_condition, branches]}, local_modifiers, modified_vars)
       when conditional in [:if, :unless] and is_list(branches) do
    Enum.any?(branches, fn {_, branch} -> returns_modification?(branch, local_modifiers, modified_vars) end)
  end

  defp returns_modification?({:case, _, [_subject, [do: clauses]]}, local_modifiers, modified_vars) do
    any_clause_returns_modification?(clauses, local_modifiers, modified_vars)
  end

  defp returns_modification?({:cond, _, [[do: clauses]]}, local_modifiers, modified_vars) do
    any_clause_returns_modification?(clauses, local_modifiers, modified_vars)
  end

  defp returns_modification?({var, _, context}, _local_modifiers, modified_vars)
       when is_atom(var) and is_atom(context) do
    MapSet.member?(modified_vars, var)
  end

  defp returns_modification?(expr, local_modifiers, _modified_vars), do: modification?(expr, local_modifiers)

  defp any_clause_returns_modification?(clauses, local_modifiers, modified_vars) when is_list(clauses) do
    Enum.any?(clauses, fn
      {:->, _, [patterns, body]} ->
        returns_modification?(body, local_modifiers, MapSet.difference(modified_vars, bound_variables(patterns)))

      _ ->
        false
    end)
  end

  defp any_clause_returns_modification?(_clauses, _local_modifiers, _modified_vars), do: false

  # A modified map of params is fine; only a modified struct bypasses validation
  defp modification?(expr, local_modifiers) do
    case modified_value(expr, local_modifiers) do
      {:ok, value} -> not params?(value, local_modifiers)
      :error -> false
    end
  end

  # A variable conventionally named for a plain map of params, or a modification of one
  defp params?({var, _, context}, _local_modifiers) when is_atom(var) and is_atom(context), do: var in @params_names

  defp params?(expr, local_modifiers) do
    case modified_value(expr, local_modifiers) do
      {:ok, value} -> params?(value, local_modifiers)
      :error -> false
    end
  end

  # The value a modification changes (`user` in `%{user | name: name}` or `Map.put(user, :name, name)`),
  # or :error if the expression isn't a modification.
  # %{struct | field: value}
  defp modified_value({:%{}, _, [{:|, _, [struct, _fields]}]}, _local_modifiers), do: {:ok, struct}
  # %Schema{struct | field: value}
  defp modified_value({:%, _, [_module, {:%{}, _, [{:|, _, [struct, _fields]}]}]}, _local_modifiers), do: {:ok, struct}

  defp modified_value({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, [struct | _]}, _local_modifiers)
       when fun in @map_modifiers, do: {:ok, struct}

  defp modified_value({{:., _, [{:__aliases__, _, [:Kernel]}, fun]}, meta, args}, local_modifiers)
       when fun in @kernel_modifiers do
    modified_value({fun, meta, args}, local_modifiers)
  end

  # struct(existing_struct, attrs) modifies; struct(Module, attrs) or struct(module, attrs) builds a new struct
  defp modified_value({fun, _, [struct, _attrs]}, _local_modifiers) when fun in [:struct, :struct!] do
    if module?(struct), do: :error, else: {:ok, struct}
  end

  defp modified_value({fun, _, [path | _] = args}, _local_modifiers)
       when fun in [:put_in, :update_in] and length(args) in 2..3, do: {:ok, path_root(path)}

  defp modified_value({fun, _, args}, local_modifiers) when is_atom(fun) and is_list(args) do
    if MapSet.member?(local_modifiers, {fun, length(args)}), do: {:ok, List.first(args)}, else: :error
  end

  defp modified_value(_expr, _local_modifiers), do: :error

  # `user` in `put_in(user.account.name, name)` or `put_in(user[:account][:name], name)`
  defp path_root({{:., _, [Access, :get]}, _, [value, _key]}), do: path_root(value)
  defp path_root({{:., _, [value, field]}, _, []}) when is_atom(field), do: path_root(value)
  defp path_root(value), do: value

  defp module?({:__aliases__, _, _}), do: true
  defp module?({:__MODULE__, _, _}), do: true

  # A variable like `module` or `schema_module` presumably holds a module rather than a struct
  defp module?({var, _, context}) when is_atom(var) and is_atom(context) do
    var |> Atom.to_string() |> String.contains?("module")
  end

  defp module?(atom), do: is_atom(atom)

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Struct is modified before being passed to `#{trigger}`, so the modified fields aren't tracked as changes: " <>
          "they bypass validation, and an update won't save them. " <>
          "Pass the values through the changeset instead (e.g., in the params or via `Ecto.Changeset.put_change/3`).",
      trigger: trigger,
      line_no: line_no
    )
  end
end
