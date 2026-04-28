# Changelog

## v0.2.0

- Add Igniter task to support installing via `mix igniter.install jump_credo_checks`,
  courtesy of @britton-jb.
- Add new `Jump.CredoChecks.PreferChangeOverUpDownMigrations` check, which detects
  Ecto migrations that define separate `up`/`down` callbacks but could instead
  take advantage of Ecto's automatic reversibility by using `change/0`.

## v0.1.0

Initial release.
