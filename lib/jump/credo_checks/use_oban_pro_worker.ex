defmodule Jump.CredoChecks.UseObanProWorker do
  @moduledoc """
  Ensures that Oban worker modules use the Oban.Pro.Worker module instead of Oban.Worker,
  and that workers declaring an `args_schema` don't match on string keys in their args.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [supported_worker_modules: [Oban.Pro.Worker]],
    explanations: [
      check: """
      Ensures that Oban worker modules use the Oban.Pro.Worker module instead of Oban.Worker.

      If your project integrates Oban Pro at all, it's worth ensuring you always use the Pro
      worker so that you get all the Pro features.

          # ❌ Bad (misses Pro features)
          defmodule MyWorker do
            use Oban.Worker
          end

          # ✅ Good
          defmodule MyWorker do
            use Oban.Pro.Worker
          end

      Additionally, when a worker declares an `args_schema`, Oban Pro casts the job's args
      into a struct with atom keys before calling `process/1`. Matching on string keys in
      the args will therefore never succeed.

          # ❌ Bad (never matches; args have atom keys)
          defmodule MyWorker do
            use Oban.Pro.Worker

            args_schema do
              field :service, :string, required: true
            end

            def process(%Oban.Job{args: %{"service" => service}}), do: ...
          end

          # ✅ Good
          defmodule MyWorker do
            use Oban.Pro.Worker

            args_schema do
              field :service, :string, required: true
            end

            def process(%Oban.Job{args: %{service: service}}), do: ...
          end
      """,
      params: [
        supported_worker_modules: """
        Worker modules that are treated as equivalent to `Oban.Pro.Worker`.
        Defaults to `[Oban.Pro.Worker]`. Replace or extend the list if your
        project wraps Oban Pro in its own worker module(s).

        `use Oban.Worker` is always flagged. `use Oban.Pro.Worker` is flagged
        when `Oban.Pro.Worker` is not in this list. The check for use of string
        keys in `process/1` args applies to modules that `use` any entry in
        this list.

        Example (allow Oban Pro and a project wrapper):

            {Jump.CredoChecks.UseObanProWorker,
             supported_worker_modules: [Oban.Pro.Worker, MyApp.Workers.Base]}

        Example (only allow a project wrapper):

            {Jump.CredoChecks.UseObanProWorker,
             supported_worker_modules: [MyApp.Workers.Base]}
        """
      ]
    ]

  alias Credo.Check.Params
  alias Credo.IssueMeta

  @map_lookup_functions [:get, :get_lazy, :fetch, :fetch!, :has_key?, :pop, :pop!]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    supported_worker_modules =
      params
      |> Params.get(:supported_worker_modules, __MODULE__)
      |> List.wrap()
      |> Enum.map(fn atom_name ->
        if not is_atom(atom_name) do
          raise ArgumentError,
                ":supported_worker_modules must be a list of atoms like `[Oban.Pro.Worker, MyApp.WorkerModule]`; got: #{inspect(atom_name)}"
        end

        atom_name |> Module.split() |> Enum.map(&String.to_atom/1)
      end)

    if supported_worker_modules == [] do
      raise ArgumentError,
            ":supported_worker_modules must be a non-empty list; got: #{inspect(supported_worker_modules)}"
    end

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, supported_worker_modules))
  end

  defp traverse({:use, meta, [{:__aliases__, _, parts} | _opts]} = ast, issues, issue_meta, supported_modules) do
    if disallowed_oban_worker?(parts, supported_modules) do
      {ast, issues ++ [oban_worker_issue(issue_meta, Macro.to_string(ast), meta[:line], parts, supported_modules)]}
    else
      {ast, issues}
    end
  end

  defp traverse({:defmodule, _, [_name, [do: body]]} = ast, issues, issue_meta, supported_modules) do
    {ast, issues ++ string_key_issues(body, issue_meta, supported_modules)}
  end

  defp traverse(ast, issues, _issue_meta, _supported_modules), do: {ast, issues}

  defp disallowed_oban_worker?([:Oban, :Worker], _supported_modules), do: true
  defp disallowed_oban_worker?([:Oban, :Pro, :Worker] = parts, supported_modules), do: parts not in supported_modules
  defp disallowed_oban_worker?(_parts, _supported_modules), do: false

  # ---------------------------------------------------------------------------
  # String keys in args when args_schema is declared
  # ---------------------------------------------------------------------------

  defp string_key_issues(module_body, issue_meta, supported_modules) do
    {body_without_nested_modules, flags} =
      Macro.prewalk(module_body, %{declares_args_schema?: false, uses_supported_worker?: false}, fn
        {:defmodule, _, _}, acc ->
          {nil, acc}

        {:args_schema, _, [_ | _]} = node, acc ->
          {node, %{acc | declares_args_schema?: true}}

        {:use, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          if parts in supported_modules do
            {node, %{acc | uses_supported_worker?: true}}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if flags.declares_args_schema? and flags.uses_supported_worker? do
      body_without_nested_modules
      |> process_clauses()
      |> Enum.flat_map(&clause_issues(&1, issue_meta))
    else
      []
    end
  end

  # Finds the `process/1` callbacks in the module
  defp process_clauses(body) do
    {_ast, clauses} =
      Macro.prewalk(body, [], fn
        {:def, _, [head, clause_body]} = node, acc ->
          case validate_process_function_head(head) do
            {:ok, process_function_head} -> {node, [{process_function_head, clause_body} | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    # Reverse so that we report issues in the order they appear in the code
    Enum.reverse(clauses)
  end

  defp validate_process_function_head({:when, _, [head, _guard]}), do: validate_process_function_head(head)
  defp validate_process_function_head({:process, _, [arg]}), do: {:ok, arg}
  defp validate_process_function_head(_), do: :error

  defp clause_issues({arg, clause_body}, issue_meta) do
    {job_vars, args_vars, args_pattern} = destructure_job_arg(arg)

    head_issues =
      case string_keyed_map(args_pattern) do
        {:ok, map} -> [string_key_issue(issue_meta, map)]
        :error -> []
      end

    scope = %{job_vars: job_vars, args_vars: args_vars}
    do_block = clause_body |> List.wrap() |> Keyword.get(:do)
    head_issues ++ body_issues(do_block, scope, issue_meta)
  end

  # Returns `{job_vars, args_vars, args_pattern}` for the single argument of `process/1`.
  defp destructure_job_arg({:=, _, [left, right]}) do
    {lj, la, lp} = destructure_job_arg(left)
    {rj, ra, rp} = destructure_job_arg(right)
    {lj ++ rj, la ++ ra, lp || rp}
  end

  defp destructure_job_arg({name, _, context}) when is_atom(name) and is_atom(context) do
    {[name], [], nil}
  end

  defp destructure_job_arg({:%, _, [_struct, {:%{}, _, pairs}]}), do: destructure_job_arg({:%{}, [], pairs})

  defp destructure_job_arg({:%{}, _, pairs}) when is_list(pairs) do
    case List.keyfind(pairs, :args, 0) do
      {:args, pattern} -> {[], bound_vars(pattern), pattern}
      _ -> {[], [], nil}
    end
  end

  defp destructure_job_arg(_), do: {[], [], nil}

  # Variables bound by `=` at the top level of a pattern, e.g. `%{...} = args`.
  defp bound_vars({:=, _, [left, right]}), do: bound_vars(left) ++ bound_vars(right)
  defp bound_vars({name, _, context}) when is_atom(name) and is_atom(context), do: [name]
  defp bound_vars(_), do: []

  # Finds a map pattern with at least one string key, looking through `=` matches.
  defp string_keyed_map(nil), do: :error

  defp string_keyed_map({:=, _, [left, right]}) do
    case string_keyed_map(left) do
      :error -> string_keyed_map(right)
      result -> result
    end
  end

  defp string_keyed_map({:%{}, _, pairs} = map) when is_list(pairs) do
    if Enum.any?(pairs, fn {key, _} -> is_binary(key) end) do
      {:ok, map}
    else
      :error
    end
  end

  defp string_keyed_map(_), do: :error

  defp body_issues(nil, _scope, _issue_meta), do: []

  defp body_issues(body, scope, issue_meta) do
    {_ast, {_scope, issues}} = Macro.prewalk(body, {scope, []}, &walk_body(&1, &2, issue_meta))
    Enum.reverse(issues)
  end

  # `%{"key" => value} = args`
  defp walk_body({:=, _, [pattern, rhs]} = node, {scope, issues}, issue_meta) do
    scope = maybe_bind_args_var(scope, pattern, rhs)

    if args_expression?(rhs, scope) do
      {node, {scope, maybe_add_pattern_issue(issues, pattern, issue_meta)}}
    else
      {node, {scope, issues}}
    end
  end

  # `with %{"key" => value} <- args do`
  defp walk_body({:<-, _, [pattern, rhs]} = node, {scope, issues}, issue_meta) do
    if args_expression?(rhs, scope) do
      {node, {scope, maybe_add_pattern_issue(issues, pattern, issue_meta)}}
    else
      {node, {scope, issues}}
    end
  end

  # `case args do %{"key" => value} -> ... end`
  defp walk_body({:case, _, [subject, [do: clauses]]} = node, {scope, issues}, issue_meta) do
    if args_expression?(subject, scope) and is_list(clauses) do
      updated_issues =
        Enum.reduce(clauses, issues, fn
          {:->, _, [[pattern], _]}, acc -> maybe_add_pattern_issue(acc, pattern, issue_meta)
          _, acc -> acc
        end)

      {node, {scope, updated_issues}}
    else
      {node, {scope, issues}}
    end
  end

  # `args["key"]`
  defp walk_body({{:., _, [Access, :get]}, _, [subject, key]} = node, {scope, issues}, issue_meta)
       when is_binary(key) do
    if args_expression?(subject, scope) do
      {node, {scope, [string_key_issue(issue_meta, node) | issues]}}
    else
      {node, {scope, issues}}
    end
  end

  # `Map.get(args, "key")` and friends
  defp walk_body(
         {{:., _, [{:__aliases__, _, [:Map]}, function]}, _, [subject, key | _]} = node,
         {scope, issues},
         issue_meta
       )
       when function in @map_lookup_functions and is_binary(key) do
    if args_expression?(subject, scope) do
      {node, {scope, [string_key_issue(issue_meta, node) | issues]}}
    else
      {node, {scope, issues}}
    end
  end

  defp walk_body(node, acc, _issue_meta), do: {node, acc}

  # `args = job.args` makes `args` an args variable for the rest of the body.
  defp maybe_bind_args_var(scope, {name, _, context}, rhs) when is_atom(name) and is_atom(context) do
    if args_expression?(rhs, scope) do
      %{scope | args_vars: [name | scope.args_vars]}
    else
      scope
    end
  end

  defp maybe_bind_args_var(scope, _pattern, _rhs), do: scope

  defp maybe_add_pattern_issue(issues, pattern, issue_meta) do
    case string_keyed_map(pattern) do
      {:ok, map} -> [string_key_issue(issue_meta, map) | issues]
      :error -> issues
    end
  end

  # Is this expression the job's args? Either an args variable or `job.args`.
  defp args_expression?({name, _, context}, scope) when is_atom(name) and is_atom(context) do
    name in scope.args_vars
  end

  defp args_expression?({{:., _, [{name, _, context}, :args]}, _, []}, scope) when is_atom(name) and is_atom(context) do
    name in scope.job_vars
  end

  defp args_expression?(_, _scope), do: false

  # ---------------------------------------------------------------------------
  # Issues
  # ---------------------------------------------------------------------------

  defp oban_worker_issue(issue_meta, trigger, line_no, used_parts, supported_modules) do
    used = Enum.map_join(used_parts, ".", &Atom.to_string/1)

    format_issue(
      issue_meta,
      message: "Use #{format_supported_modules(supported_modules)} instead of #{used} for better safety and features.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp format_supported_modules([module]), do: inspect(module)

  defp format_supported_modules(modules) do
    {front, [last]} = Enum.split(modules, -1)
    Enum.map_join(front, ", ", &inspect/1) <> ", or " <> inspect(last)
  end

  defp string_key_issue(issue_meta, {_, meta, _} = node) do
    format_issue(
      issue_meta,
      message:
        "This worker declares an args_schema, so its args always have atom keys. " <>
          "Matching on string keys will never succeed; use atom keys instead (e.g., %{service: service}).",
      trigger: Macro.to_string(node),
      line_no: meta[:line]
    )
  end
end
