defmodule Jump.CredoChecks.AssertReceiveTimeoutTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.AssertReceiveTimeout

  describe "without a configured min_assert_receive_timeout" do
    test "alerts on assert_receive with a literal timeout" do
      """
      defmodule MyTest do
        test "with timeout" do
          assert_receive :foo, 1_000
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> assert_issue()
    end

    test "alerts on assert_receive with a complex pattern and a timeout" do
      """
      defmodule MyTest do
        test "with timeout" do
          assert_receive {:jump_live_event,
                          %{
                            type: :nudge,
                            delivery: :zoom_app,
                            call_bot_id: ^call_bot_id,
                            bot_id: ^bot_id,
                            payload: ^nudge
                          }},
                          1_000
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> assert_issue()
    end

    test "alerts on assert_receive with a timeout and a failure message" do
      """
      defmodule MyTest do
        test "with timeout and message" do
          assert_receive :foo, 1_000, "nope"
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> assert_issue()
    end

    test "alerts on assert_receive with a variable timeout" do
      """
      defmodule MyTest do
        @timeout 1_000

        test "with variable timeout" do
          assert_receive :foo, @timeout
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> assert_issue()
    end

    test "does not alert when no timeout is specified" do
      """
      defmodule MyTest do
        test "without timeout" do
          assert_receive :foo
          assert_receive {:bar, _}
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> refute_issues()
    end

    test "does not alert on other assertions" do
      """
      defmodule MyTest do
        test "other assertions" do
          assert true
          assert 1 == 1
          assert_received :foo
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> refute_issues()
    end
  end

  describe "with a configured min_assert_receive_timeout" do
    test "alerts when literal timeout is less than the minimum" do
      """
      defmodule MyTest do
        test "short timeout" do
          assert_receive :foo, 500
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000)
      |> assert_issue()
    end

    test "does not alert when literal timeout equals the minimum" do
      """
      defmodule MyTest do
        test "exactly the minimum" do
          assert_receive :foo, 1_000
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000)
      |> refute_issues()
    end

    test "does not alert when literal timeout exceeds the minimum" do
      """
      defmodule MyTest do
        test "longer than minimum" do
          assert_receive :foo, 1001
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000)
      |> refute_issues()
    end

    test "does not alert when no timeout is specified" do
      """
      defmodule MyTest do
        test "no timeout falls back to default" do
          assert_receive :foo
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000)
      |> refute_issues()
    end

    test "alerts when timeout is a non-literal we cannot statically verify" do
      """
      defmodule MyTest do
        @timeout 500

        test "non-literal timeout cannot be verified" do
          assert_receive :foo, @timeout
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000)
      |> assert_issue()
    end
  end

  describe "without a configured max_refute_receive_timeout" do
    test "does not alert on refute_receive with a literal timeout" do
      """
      defmodule MyTest do
        test "refute with timeout" do
          refute_receive :foo, 5_000
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> refute_issues()
    end

    test "does not alert on refute_receive without a timeout" do
      """
      defmodule MyTest do
        test "refute without timeout" do
          refute_receive :foo
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout)
      |> refute_issues()
    end
  end

  describe "with a configured max_refute_receive_timeout" do
    test "alerts on refute_receive when literal timeout exceeds the maximum" do
      """
      defmodule MyTest do
        test "long refute timeout" do
          refute_receive :foo, 1_000
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)
      |> assert_issue()
    end

    test "alerts on refute_receive with a long timeout and a failure message" do
      """
      defmodule MyTest do
        test "long refute timeout with message" do
          refute_receive :foo, 1_000, "nope"
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)
      |> assert_issue()
    end

    test "does not alert when refute_receive timeout equals the maximum" do
      """
      defmodule MyTest do
        test "refute timeout at the max" do
          refute_receive :foo, 100
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)
      |> refute_issues()
    end

    test "does not alert when refute_receive timeout is below the maximum" do
      """
      defmodule MyTest do
        test "refute timeout below the max" do
          refute_receive :foo, 50
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)
      |> refute_issues()
    end

    test "alerts when no refute_receive timeout is specified" do
      """
      defmodule MyTest do
        test "refute without timeout" do
          refute_receive :foo
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)
      |> assert_issue()
    end

    test "alerts when refute_receive timeout is a non-literal we cannot statically verify" do
      """
      defmodule MyTest do
        @timeout 1_000

        test "non-literal refute timeout cannot be verified" do
          refute_receive :foo, @timeout
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)
      |> assert_issue()
    end

    test "error message references the minimum-bound nature of refute_receive" do
      [issue] =
        """
        defmodule MyTest do
          test "long refute timeout" do
            refute_receive :foo, 1_000
          end
        end
        """
        |> to_source_file()
        |> run_check(AssertReceiveTimeout, max_refute_receive_timeout: 100)

      assert issue.message =~ "refute_receive"
      assert issue.message =~ "minimum"
      assert issue.message =~ "slow"
    end
  end

  describe "with both min_assert_receive_timeout and max_refute_receive_timeout configured" do
    test "alerts on a short assert_receive and a long refute_receive together" do
      issues =
        """
        defmodule MyTest do
          test "mixed" do
            assert_receive :foo, 500
            refute_receive :bar, 1_000
          end
        end
        """
        |> to_source_file()
        |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000, max_refute_receive_timeout: 100)

      assert length(issues) == 2
    end

    test "does not alert when both timeouts are within their bounds" do
      """
      defmodule MyTest do
        test "ok" do
          assert_receive :foo, 1_000
          refute_receive :bar, 50
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertReceiveTimeout, min_assert_receive_timeout: 1_000, max_refute_receive_timeout: 100)
      |> refute_issues()
    end
  end
end
