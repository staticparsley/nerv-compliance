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

## Scan operations

`/scans` lists executions in pages of 20; `/scans/:id` shows their checks and
expandable evidence. The dashboard links to both scan history and individual
assessments, including historical checks with no scan. Times are displayed in UTC.

Execution states are `queued`, `running`, `completed`, and `error` (displayed as
FAILED). A completed execution can contain failing controls: compliance failures
are red; execution errors are orange and indicate unknown compliance.

### Manual assessments and operator access

Manual POSTs are disabled by default. Configure these in the web process's
private environment to enable the Run Assessment button:

- `NERV_SCAN_OPERATOR_USERNAME`: the authorized scan operator's username.
- `NERV_SCAN_OPERATOR_PASSWORD`: a strong, unique operator password.

The browser prompts for HTTP Basic credentials when submitting the form. The
credentials authorize scan submission and risk acceptance; this is a single operator gate,
not a user/role management system. Rails CSRF checks remain enabled. Production
submissions require HTTPS. Terminate TLS at a trusted proxy and configure Rails'
SSL/proxy settings appropriately; do not expose Basic authentication over public
HTTP. Development HTTP is intended for local use. Scan/history reads retain the
existing dashboard's access policy; protect the whole application at your access
proxy if assessment evidence must be private. No credentials belong in source
control, URLs, job arguments, or Rails runner commands.

### Persistent workers and recurring scans

Solid Queue is already included in the bundle. Its tables now use normal additive
migrations in the application PostgreSQL database. The old separate queue schema
and unused production queue connection were replaced by this setup; no database
or historical assessment is dropped. Sharing the primary connection lets scan
reservation and job enqueue commit or roll back together.

After pulling changes, run migrations before starting workers:

```sh
mise exec -- bin/rails db:migrate
mise exec -- bin/jobs check
```

In development, run the web server and worker supervisor in separate terminals:

```sh
mise exec -- bin/rails server
# In another terminal, with the worker environment configured:
mise exec -- bin/jobs start
```

In production, use the same release and database configuration for both processes:

```sh
RAILS_ENV=production mise exec -- bin/rails db:migrate
RAILS_ENV=production mise exec -- bin/jobs check
RAILS_ENV=production mise exec -- bin/jobs start
```

Run the production supervisor under your process manager with restart-on-failure.
The existing `SOLID_QUEUE_IN_PUMA` option is an alternative to a separate worker;
choose one operational setup. Starting the Rails web process alone does not run
workers unless that option is enabled.

Workers need the existing `K8S_API_SERVER`, `K8S_TOKEN`, and `K8S_CA_FILE` in their
private environment. They reuse the existing verified-HTTPS, read-only pod client.
Web requests only reserve a scan and enqueue its ID; Kubernetes access occurs in
the worker. No Kubernetes resource writes are introduced.

`bin/jobs start` also starts the Solid Queue scheduler. Recurring assessments
are enabled in development and production, defaulting to **every six hours**.
Configure the worker/scheduler environment with:

- `NERV_SCAN_SCHEDULE`: a Solid Queue/Fugit expression, e.g. `every 6 hours` or
  `0 */6 * * *` (UTC with the application's default time zone).
- `NERV_SCHEDULED_SCANS_ENABLED=false`: removes recurring assessments from the
  scheduler configuration; manual queued work still runs.
- `SOLID_QUEUE_SKIP_RECURRING=true`: disables all recurring scheduling in a
  supervisor, including queue maintenance.

Restart supervisors after changing schedules and validate with `bin/jobs check`.
Do not start workers against a real cluster until you intend to allow scans.
An already queued scheduled job remains queued when scheduling is disabled.

Manual, scheduled, and direct runner invocations use the same reservation guard.
A PostgreSQL advisory lock serializes reservations, and a partial unique index
permits at most one queued/running scan for this single-cluster integration.
A second request returns the active scan. Workers atomically claim queued scans,
so duplicate delivery does not repeat evaluations. Recurring tasks also use Solid
Queue's built-in per-task/per-time deduplication. No automatic scan retries run
after partial results; a subsequent assessment creates a separate execution.

### Failure recovery

If queue insertion fails, neither a new scan nor its job is committed. API and
evaluation errors finalize the scan as failed and preserve successful checks.
Raw exception messages and service-account tokens are not stored as scan errors.

A queued scan stays queued if workers are stopped. Restart `bin/jobs` to consume
it. A hard-killed worker can leave a scan marked running. This intentionally
blocks new scans rather than guessing that an execution has stopped. Stop or
confirm termination of the affected worker before recovery. Then, in a Rails
console connected to the correct environment, inspect the specific scan and
mark it failed (replace the ID; do not change a live running scan):

```ruby
scan = Scan.find(123)
scan.update!(status: "error", started_at: scan.started_at || Time.current,
             completed_at: Time.current, error_message: "Operator confirmed worker termination")
```

Preserve its checks/evidence, restart workers, and request a new assessment. Any
delayed delivery for the finalized scan will be ignored. There is no automatic
stale-scan timeout because releasing the reservation while a worker is still
running could allow overlap. The UI refreshes status when the page is reloaded.

## Finding management

`/findings` defaults to **open** violations, with filters for status, control,
and exact namespace. It lists 20 findings per page. Each detail page includes
first/last observed times, resource identity, the latest 50 observation links and
original payloads, and the complete risk acceptance audit trail. The dashboard
counts open findings and accepted risks separately from raw check failures.

### Identity and observation lifecycle

Each violation is identified by integration, control key, namespace, pod name,
pod UID (when supplied by Kubernetes), and container name. A SHA-256 fingerprint
has a database unique index. Changing violation details (for example, adding a
CPU limit while still missing a memory limit) updates the same finding and adds
a link to that scan's new evidence. It never rewrites an earlier payload.
Kubernetes container names are unique within a pod, including init and ephemeral
containers; no workload/controller aggregation is performed.

- **Open**: observed in a successful control evaluation and not covered by a
  currently effective acceptance.
- **Accepted risk**: still an active violation, with an unexpired operator
  acceptance. The raw control continues to fail.
- **Resolved**: absent from the next successful evaluation of that same control
  and integration. A pod disappearing also resolves its findings; this does not
  prove that the underlying workload has been remediated.

An API error or failed control evaluation never resolves that control's findings
or advances their last-observed time. Successful controls in a partially failed
scan can still update their own findings. A pod response with a continuation
token is rejected as incomplete, rather than treating unseen resources as fixed.

A resolved finding reopens if the same identity is observed again. Its first
observation and prior evidence are retained. Resolution ends the current risk
acceptance: recurrence requires a new decision. Replacing a pod with a new UID
creates a separate finding and does not inherit the old pod's acceptance. If
UIDs are unavailable in synthetic/source data, identity falls back to the
namespace/pod/container names. Namespace is never a reason to suppress a finding;
`kube-system` and other system namespaces follow the same rules.

### Documented risk acceptance

The existing `NERV_SCAN_OPERATOR_USERNAME` / `NERV_SCAN_OPERATOR_PASSWORD`
operator gate now authorizes both scan submission and risk acceptance. These
remain private environment values, not database or form fields. Both mutations
are disabled without configured credentials, require CSRF tokens, and require
HTTPS in production. Finding/history reads retain the dashboard's existing
access policy. Protect those reads with your access proxy if needed.

To accept an unresolved finding, open its details and submit a reason (including
compensating measures) and a future expiration date. The authenticated operator
identity and acceptance time are recorded by the server. Renewing an acceptance
adds a new immutable decision; earlier reasons, dates, and actors remain visible.
The newest acceptance alone controls suppression, so an older, longer exception
cannot resume after a newer one expires.

An acceptance expires at **00:00 UTC at the beginning of its expiration date**.
Open/accepted status and query counts are computed using that date on each read.
No expiration worker, recurring job, or new Kubernetes scan is required. Reload
an already-open page to see the current status. Expiration does not imply the
cluster was checked again; the last observed timestamp remains visible.

### Historical integrity and limits

Finding reconciliation and its check/evidence inserts share a transaction.
If tracking cannot be persisted, that control records an error and does not
partially change findings. Original Check and Evidence records are now read-only
through normal Active Record update/destroy operations. Observation links and
risk decisions are also append-only. Risk acceptance never changes past check
statuses, pod counts, findings counts, or evidence. Direct SQL and bulk database
operations remain privileged administrative paths; this is application-level
immutability, not a tamper-proof database ledger.

Historical scans/checks/evidence are preserved and are **not backfilled** into
findings. Tracking starts with the next real assessment. A zero finding count
before that assessment does not establish compliance. There is no acceptance
revocation UI in this milestone; acceptances expire, can be superseded by a new
documented decision, or end on finding resolution. Operator attribution uses the
existing single configured account, not individual user accounts.

After updating the application, apply the additive finding migration and restart
web/worker processes:

```sh
mise exec -- bin/rails db:migrate
mise exec -- bin/rails test
mise exec -- bin/rubocop
mise exec -- bin/brakeman --no-pager
mise exec -- bin/bundler-audit check --update
```

Tests use synthetic pod snapshots and HTTP responses. macOS defaults to a single
test process because its native pg/libpq stack crashed during forked worker
startup when the suite grew beyond Rails' parallelization threshold. Linux CI
retains process parallelism; `PARALLEL_WORKERS=1` also forces serial execution
explicitly. No Ruby or gem versions were changed for this workaround.
