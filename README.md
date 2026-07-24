# Jump.CredoChecks

[![Hex.pm](https://img.shields.io/hexpm/v/jump_credo_checks)](https://hex.pm/packages/jump_credo_checks) [![Build and Test](https://github.com/Jump-App/credo_checks/actions/workflows/elixir-build-and-test.yml/badge.svg)](https://github.com/Jump-App/credo_checks/actions/workflows/elixir-build-and-test.yml) [![Elixir Quality Checks](https://github.com/Jump-App/credo_checks/actions/workflows/elixir-quality-checks.yml/badge.svg)](https://github.com/Jump-App/credo_checks/actions/workflows/elixir-quality-checks.yml) [![Code coverage](https://codecov.io/gh/Jump-App/credo_checks/graph/badge.svg)](https://codecov.io/gh/Jump-App/credo_checks)

A collection of opinionated [Credo](https://github.com/rrrene/credo) checks aimed at improving code quality and catching common mistakes in Elixir, Oban, and LiveView.

These are checks used internally by [Jump](https://jump.ai/)'s engineering team, but which may not be suitable (or desired) for contribution upstream to mainline Credo.

## Available checks

See the individual modules for detailed descriptions of each check type.

- `Jump.CredoChecks.AssertElementSelectorCanNeverFail`: Prevents asserting on a `LiveViewTest.element/{2,3}` call, which can never fail since the function always returns a (possibly empty) list.
- `Jump.CredoChecks.AssertReceiveTimeout`: Flags `assert_receive` calls that specify explicit timeouts. These timeouts can seem like a fine idea in dev, but when your test later runs on a dog-slow CI machine, the tight timeouts can cause flakiness. (In CI, you might run with an absurdly long timeout to avoid flakiness.)
    - Supports an optional `min_assert_receive_timeout` parameter that allows literal `assert_receive` timeouts greater than or equal to the configured minimum
    - Also supports an optional `max_refute_receive_timeout` parameter that flags `refute_receive` calls whose timeout exceeds the configured maximum (because `refute_receive` always blocks for its full timeout, setting a lower bound on the test's runtime)
- `Jump.CredoChecks.AvoidFunctionLevelElse`: Prevents botched refactors or rebases from introducing `else` clauses at the top level of a function body.

    ```elixir
    # ❌ Bad — function-level else crashes if `something(bar)` does not return an error tuple
    def foo(bar) do
      something(bar)
    else
      {:error, reason} -> handle_error(reason)
    end

    # ✅ Good — use with/else or case instead
    def foo(bar) do
      with {:ok, result} <- something(bar) do
        result
      else
        {:error, reason} -> handle_error(reason)
      end
    end
    ```
- `Jump.CredoChecks.AvoidLoggerConfigureInTest`: Ensure your tests don't call `Logger.configure/1` and thereby affect log levels for other tests.
- `Jump.CredoChecks.AvoidSocketAssignsInTest`: Ensure that tests assert on expected user behavior rather than introspecting socket `assigns`.
- `Jump.CredoChecks.ConditionalAssertion`: Flags assertions that include an "or," like `assert foo == :bar or baz == :bop` or `assert foo > 0 || bop > 0`.
- `Jump.CredoChecks.DoctestIExExamples`: Ensures that modules with interactive Elixir examples in their docstrings have a corresponding test file that runs those doctests.
- `Jump.CredoChecks.ForbiddenFunction`: Alerts with a custom error message when particular functions are called.
- `Jump.CredoChecks.LiveViewFormCanBeRehydrated`: Ensures any form with a `phx-submit` attribute also includes an ID and `phx-change` handler. Without these, LiveView can't maintain frontend form state across deploys/reconnects, leading to the form being totally reset.
- `Jump.CredoChecks.NoManualContentDisposition`: Ensures you use `Phoenix.Controller.send_download/3` rather than of manually setting `content-disposition`. This provides a backstop against accidentally failing to properly sanitize filenames in response headers (a potential security vulnerability).
- `Jump.CredoChecks.UndeclaredExternalResource`: Ensures modules that read from the file system at compile time (e.g., `File.read!/1` in a module attribute) declare a corresponding `@external_resource` so that editing the file on disk triggers a recompile.

    ```elixir
    # ❌ Bad — editing prompt.md won't recompile this module
    defmodule MyApp.ReadsFromDisk do
      @prompt_path "priv/data/prompt.md"
      @prompt File.read!(@prompt_path)
    end

    # ✅ Good: changes made to prompt.md cause MyApp.ReadsFromDisk to recompile
    defmodule MyApp.ReadsFromDisk do
      @prompt_path "priv/data/prompt.md"
      @external_resource @prompt_path
      @prompt File.read!(@prompt_path)
    end
    ```
- `Jump.CredoChecks.PreferTextColumns`: Ensures your Ecto migrations use the `:text` column type, rather than `:string`, since there is no performance difference in modern versions of Postgres, and you almost always want to enforce maximum length at the application level instead.
- `Jump.CredoChecks.SafeBinaryToTerm`: Ensures `Plug.Crypto.non_executable_binary_to_term/2` is always called with the `:safe` option. Without it, decoding attacker-controlled input interns arbitrary atoms into the BEAM's fixed, never-garbage-collected atom table, which an attacker can exhaust to crash the node. Matches qualified, aliased, imported, and piped calls.
- `Jump.CredoChecks.TestHasNoAssertions`: Alerts on ExUnit `test` blocks that contain no assertions.
- `Jump.CredoChecks.TooManyAssertions`: Flags tests that make an excessive number of assertions, generally indicating a test that conflates multiple concerns. Defaults to 20 asserts at max.
- `Jump.CredoChecks.TopLevelAliasImportRequire`: Ensures `alias`, `import`, and `require` statements occur only at the top level of a module, rather than within a function.
- `Jump.CredoChecks.UseObanProWorker`: Ensures your Oban worker modules consistently `use Oban.Pro.Worker` rather than `use Oban.Worker` so that you get all the benefits of the Pro package.
- `Jump.CredoChecks.VacuousTest`: Ensures tests actually exercise your production code. Especially useful to detect poor-quality tests generated by LLMs.

    ```elixir
    # ❌ Vacuous — no application code is called
    test "example" do
      refute 3 in [1, 2, 5]
      assert byte_size("hello") > 0
      assert :ok == :ok
    end

    # ✅ Meaningful — exercises application code
    test "example" do
      result = MyApp.process("hello")
      assert result == "expected"
    end
    ```
- `Jump.CredoChecks.WeakAssertion`: Ensures tests don't use low-value assertions like `refute is_nil(val)`, instead preferring assertions that tell more about what the value *should* be.

    ```elixir
    # ❌ Weak
    assert is_list(result)
    assert is_map(result)
    assert is_binary(result)
    refute is_nil(result)

    # ✅ Strong
    assert [%Product{id: ^id}] = result
    assert %{name: "Tyler"} = result
    assert result == "expected string"
    assert is_nil(error)
    assert %Product{} = result
    ```
- `Jump.CredoChecks.PreferChangeOverUpDownMigrations`: Detects Ecto migrations which define separate `up`/`down`
  callbacks but could instead take advantage of Ecto's automatic reversibility by using `change/0`.
- `Jump.CredoChecks.UnusedLiveViewAssign`: Detects LiveView assigns that are written by a module but never read in that module's Elixir or HEEx source.


## Installation and configuration

**New in v0.2**: If you've already configured [Igniter](https://hexdocs.pm/igniter/) in your project,
you can use `mix igniter.install jump_credo_checks` to automate all the steps in this section.

The following instructions assume you already have Credo configured and working on your codebase.

1. Add `jump_credo_checks` to your `mix.exs` dependencies:

    ```elixir
    def deps do
      [
        {:jump_credo_checks, "~> 0.4", only: [:dev], runtime: false},
      ]
    end
    ```
2. Run `$ mix deps.get` to download the package
3. Add the desired Credo checks to your `.credo.exs`:

    ```elixir
    %{
      configs: [
        %{
          checks: %{
            enabled: [
              {Jump.CredoChecks.AssertElementSelectorCanNeverFail, []},
              # Default min_assert_receive_timeout and max_refute_receive_timeout are both nil
              # (any explicit assert_receive timeout is flagged; refute_receive timeouts are not checked).
              # - Set min_assert_receive_timeout to allow explicit assert_receive timeouts that are
              #   integer literals >= the configured value.
              # - Set max_refute_receive_timeout to flag refute_receive calls with timeouts longer than
              #   the configured value. Because refute_receive always blocks for its full timeout, a long
              #   refute_receive sets a lower bound on how long the entire test takes to run.
              {Jump.CredoChecks.AssertReceiveTimeout,
                min_assert_receive_timeout: 1_000,
                max_refute_receive_timeout: 100},
              {Jump.CredoChecks.AvoidFunctionLevelElse, []},
              {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
              # Default exclusion list is empty
              {Jump.CredoChecks.AvoidSocketAssignsInTest, excluded: ["test/app_web/plugs/"]},
              {Jump.CredoChecks.ConditionalAssertion, []},
              {Jump.CredoChecks.DoctestIExExamples, [
                # Tells Credo where to look for the `doctest` call.
                # If you colocate your test files with your implementation, this would just
                # be `&String.replace_trailing(&1, ".ex", "_test.exs")`
                derive_test_path: fn filename ->
                  filename
                  |> String.replace_leading("lib/", "test/")
                  |> String.replace_trailing(".ex", "_test.exs")
                end
              ]},
              {Jump.CredoChecks.ForbiddenFunction, 
               functions: [
                 {:erlang, :binary_to_term, "Use Plug.Crypto.non_executable_binary_to_term/2 instead."},
               ]},
              {Jump.CredoChecks.LiveViewFormCanBeRehydrated, excluded: ["lib/my_app/"]},
              {Jump.CredoChecks.NoManualContentDisposition, []},
              {Jump.CredoChecks.UndeclaredExternalResource, []},
              # Default start_after is "0"
              {Jump.CredoChecks.PreferChangeOverUpDownMigrations, start_after: "20240101000000"},
              {Jump.CredoChecks.PreferTextColumns, start_after: "20240101000000"},
              # Exclude files that intentionally decode fully-trusted (never attacker-controlled) input
              {Jump.CredoChecks.SafeBinaryToTerm, files: %{excluded: ["lib/my_app/trusted_decoder.ex"]}},
              {Jump.CredoChecks.TestHasNoAssertions, custom_assertion_functions: [:await_has, :await_with_timeout]},
              # Default max_assertions is 20
              {Jump.CredoChecks.TooManyAssertions, [max_assertions: 20]},
              {Jump.CredoChecks.TopLevelAliasImportRequire, []},
              {Jump.CredoChecks.UnusedLiveViewAssign,
               [
                 ignored_assigns: [:active_path],
                 # Optional helpers that write assigns like Phoenix.Component.assign/3
                 custom_assign_functions: [
                   {:assign_current_user, 3},
                   {MyApp.LiveHelpers, :assign_tenant, 3}
                 ]
               ]},
              {Jump.CredoChecks.UseObanProWorker, []},
              {Jump.CredoChecks.VacuousTest,
                [
                  # When true (default), tests that destructure setup context 
                  # (3-arity test blocks) are considered not vacuous. 
                  # Set to false to check them too.
                  ignore_setup_only_tests?: false,
                  # Additional library namespaces whose calls should not count
                  # as production code. Defaults to []
                  library_modules: [
                    Ecto,
                    Jason,
                    Oban,
                    Phoenix,
                    Plug
                  ]
                ]},
              {Jump.CredoChecks.WeakAssertion, []},
              # ...
            ]
          }
        }
      ]
    }
    ```

## Philosophy

We use Credo checks primarily as just-in-time education for encouraging best practices. While education like this is valuable, the developer experience is strictly worse than making such education entirely unnecessary; for instance, by:

- letting compiler warnings serve the educational function,
- designing our APIs in a way that makes the anti-patterns impossible, or
- automatically rewriting the code.

Thus, we don't use Credo in cases where we can instead use [Quokka](https://github.com/emkguts/quokka) (or Quokka [plugins](https://github.com/emkguts/quokka/pull/141)) to automatically rewrite code. For instance, there's no need to bug developers with a Credo check that asks them to rewrite `Enum.map(...) |> Enum.into(%{})` to instead use `Map.new/2`; we can rewrite that automatically and never need the education.

## A request for you, the user

If you use these checks, please give us feedback—which checks were valuable for you, and which weren't?

You're welcome to file an issue with your feedback, or contact Tyler Young, one of the maintainers, directly [via email](mailto:tyler@jumpapp.com), [on BlueSky](https://bsky.app/profile/tylerayoung.com), or [on Mastodon](https://fosstodon.org/@tylerayoung).

## Contribution guidelines

We welcome pull requests, but be aware that if the proposed checks/changes aren't something we'd want to use in the Jump codebase, we'll politely decline them. (Feel free to open an issue to discuss and get conceptual agreement before doing the work if you'd like.)
