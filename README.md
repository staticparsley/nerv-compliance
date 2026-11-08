# NERV Compliance

A Rails application for monitoring Kubernetes security compliance.

## Local Ruby setup

Use Ruby 4.0.9 from `.ruby-version` and Bundler 4.0.20 from `Gemfile.lock`.
The project `mise.toml` enables mise to read `.ruby-version`, overriding a
global Ruby selection such as `latest`.

From this directory:

```sh
mise trust
mise install
mise exec -- ruby -v
mise exec -- bundle -v
mise exec -- bundle install
mise exec -- bin/rails db:migrate
mise exec -- bin/rails server
```

PostgreSQL must be running with the connection settings in `config/database.yml`.

For plain `ruby`, `bundle`, and `bin/rails` commands in zsh, put
`eval "$(mise activate zsh)"` after other PATH changes in `~/.zshrc`.
For an already-open terminal, run:

```sh
eval "$(mise activate zsh)"
cd .
mise exec -- ruby -v
```

If the shell still selects macOS Ruby 2.6, use the explicit `mise exec --`
commands above. Keep the Gemfile's Windows/JRuby platform declarations intact;
run Bundler through the intended Ruby rather than macOS's system Bundler.

## Checks

```sh
mise exec -- bin/rails db:test:prepare test
mise exec -- bin/rubocop
```

Evaluator and scan lifecycle tests use synthetic pods and require no live
Kubernetes connection.
