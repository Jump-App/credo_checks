# Changelog

## v0.3.0

* New check: Add `Jump.CredoChecks.UnusedLiveViewAssign`, compliments of first-time contributor @ftes ([PR](https://github.com/Jump-App/credo_checks/pull/9))
* Fix for `Jump.CredoChecks.LiveViewFormCanBeRehydrated`: Don't warn about missing `phx-change` on forms with `phx-auto-recover="ignore"` ([PR](https://github.com/Jump-App/credo_checks/pull/6))
* Dependency updates:
  * Bump ex_doc from 0.40.1 to 0.40.3 ([PR 1](https://github.com/Jump-App/credo_checks/pull/7), [PR 2](https://github.com/Jump-App/credo_checks/pull/11))
  * [Bump igniter from 0.7.9 to 0.8.0](https://github.com/Jump-App/credo_checks/pull/8)
  * [Bump quokka from 2.12.1 to 2.13.1](https://github.com/Jump-App/credo_checks/pull/10)

## v0.2.0

- Add Igniter task to support installing via `mix igniter.install jump_credo_checks`,
  courtesy of @britton-jb.
- Add new `Jump.CredoChecks.PreferChangeOverUpDownMigrations` check, which detects
  Ecto migrations that define separate `up`/`down` callbacks but could instead
  take advantage of Ecto's automatic reversibility by using `change/0`.

## v0.1.0

Initial release.
