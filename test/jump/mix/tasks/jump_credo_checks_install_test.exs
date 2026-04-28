defmodule Mix.Tasks.JumpCredoChecks.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @credo_config """
  %{
    configs: [
      %{
        name: "default",
        checks: %{
          enabled: [
            {Credo.Check.Consistency.ExceptionNames, []},
            {Credo.Check.Consistency.LineEndings, []}
          ],
          disabled: [
            {Credo.Check.Design.DuplicatedCode, []}
          ]
        }
      }
    ]
  }
  """

  @credo_config_with_jump """
  %{
    configs: [
      %{
        name: "default",
        checks: %{
          enabled: [
            {Credo.Check.Consistency.ExceptionNames, []},
            {Credo.Check.Consistency.LineEndings, []},
            {Jump.CredoChecks.AvoidFunctionLevelElse, []}
          ],
          disabled: [
            {Credo.Check.Design.DuplicatedCode, []}
          ]
        }
      }
    ]
  }
  """

  describe "igniter/1" do
    test "adds Jump checks to existing .credo.exs" do
      test_project(files: %{".credo.exs" => @credo_config})
      |> Igniter.compose_task("jump_credo_checks.install")
      |> assert_has_patch(".credo.exs", """
      + |{Jump.CredoChecks.AssertElementSelectorCanNeverFail, []},
      + |{Jump.CredoChecks.AvoidFunctionLevelElse, []},
      + |{Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
      + |{Jump.CredoChecks.AvoidSocketAssignsInTest, []},
      + |{Jump.CredoChecks.DoctestIExExamples, []},
      + |{Jump.CredoChecks.ForbiddenFunction, []},
      + |{Jump.CredoChecks.LiveViewFormCanBeRehydrated, []},
      + |{Jump.CredoChecks.PreferChangeOverUpDownMigrations, []},
      + |{Jump.CredoChecks.PreferTextColumns, []},
      + |{Jump.CredoChecks.TestHasNoAssertions, []},
      + |{Jump.CredoChecks.TooManyAssertions, []},
      + |{Jump.CredoChecks.TopLevelAliasImportRequire, []},
      + |{Jump.CredoChecks.UseObanProWorker, []},
      + |{Jump.CredoChecks.VacuousTest, []},
      + |{Jump.CredoChecks.WeakAssertion, []}
      """)
    end

    test "skips when Jump checks already present in .credo.exs" do
      test_project(files: %{".credo.exs" => @credo_config_with_jump})
      |> Igniter.compose_task("jump_credo_checks.install")
      |> assert_unchanged(".credo.exs")
    end

    test "warns when no .credo.exs exists" do
      test_project()
      |> Igniter.compose_task("jump_credo_checks.install")
      |> assert_has_warning(&String.contains?(&1, "No .credo.exs found"))
    end
  end
end
