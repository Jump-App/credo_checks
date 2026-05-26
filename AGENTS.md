# Creating a new Credo check

## What you need first

Before you can begin, the user needs to at least briefly describe for you:

1. The condition they want the Credo check to warn about (for instance, "detect when someone passes assigns into async functions")
2. What we should suggest the developer do instead

It's helpful if they can also point you to a specific place in the codebase where the problem is currently happening, or provide a code sample.

## Guidelines

1. Credo modules should be named `Jump.CredoChecks.*`
2. They should live in `lib/jump/credo_checks/*.ex`
3. You should always write the tests first (at `test/jump/credo_checks/*_test.exs`); test-driven development is by far the superior way to work with this stuff.
4. Feel free to add temporary debugging output (`IO.inspect`, `dbg`, etc.) to the check and repeatedly rerun the tests to figure out what the AST looks like in the cases you care about.
5. When your tests are all passing, add the check to the list of custom configured checks in @.credo.exs and run the `mix credo` task. The command should produce no warnings; if it does, ask the user how to proceed.

# References

For an example of a simple check as well as its tests (both negative and positive), see @lib/jump/credo_checks/assert_element_selector_can_never_fail.ex and @test/jump/credo_checks/assert_element_selector_can_never_fail_test.exs.
