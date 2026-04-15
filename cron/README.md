# Automaton

The cron + supervisor system that runs scheduled hardhat tasks for arm-oeth. A long-running container renders a crontab from a TypeScript registry, executes jobs via [supercronic](https://github.com/aptible/supercronic), exposes a small HTTP API for manual triggers and run inspection, and ships structured logs to Loki for Grafana.

A sibling Automaton with the same shape and log schema lives in the `origin-dollar` repo. Keep field names (`event`, `source`, `action`, `run_id`, `duration_ms`, `error_*`) in sync across both so a single Grafana dashboard can serve both.

## Components

| File | Purpose |
|---|---|
| `cron/cron-jobs.ts` | Job registry — `name`, `schedule` (5-field cron), `enabled`, `command`. Single source of truth. |
| `cron/render-crontab.ts` | Validates the registry (unique names, valid schedules) and writes the supercronic crontab file. |
| `cron/cron-supervisor.ts` | Boots supercronic + HTTP API server. Exposes `/api/v1/actions`, `/api/v1/actions/:name/runs`, `/api/v1/runs/:id`, `/healthz`. |
| `cron/api.ts` | HTTP server, auth, run tracking for on-demand action triggers. |
| `cron/cron-entrypoint.sh` | Container entrypoint — boots the supervisor under `ts-node`. |
| `src/js/tasks/lib/action.ts` | Wrapper used by every hardhat task. Generates a `run_id` (UUID), emits `action.start`, `action.success`, and `action.error` events to Loki. |
| `src/js/tasks/lib/logger.ts` | Winston + winston-loki. Promotes `action`, `event`, `source` to Loki labels. |

## Adding / enabling / disabling a job

1. Append (or edit) an entry in `cron/cron-jobs.ts`. Names must be unique; schedules must be valid 5-field cron expressions.
2. Make sure the underlying hardhat task is built on the `action(...)` wrapper from `src/js/tasks/lib/action.ts` — that's where the run-id correlation and error reporting come from.
3. Flip `enabled` to toggle without removing the entry.
4. Redeploy the container (the GitHub Action on the `automation` branch builds and pushes the image).

`render-crontab.ts` will fail loudly at boot if the registry is malformed — the container won't start with a broken config.

## Local dev

Required env vars:

- `PROVIDER_URL`, `SONIC_URL` — RPC endpoints (same as the rest of the repo)
- `LOKI_URL`, `LOKI_USER`, `LOKI_API_KEY` — optional; if unset, logs only go to stdout
- `ACTION_API_BEARER_TOKEN` — required to start the supervisor (auth for `/api/v1/*`)
Run a single action without the supervisor:
```
npx hardhat <actionName> --network mainnet
```

Run the full supervisor locally:
```
ACTION_API_BEARER_TOKEN=dev npx ts-node cron/cron-supervisor.ts
```

## Observability

Each action generates its own `run_id` (UUID) and emits structured events via the winston/Loki logger in `src/js/tasks/lib/action.ts`:

- `action.start` — emitted after resolving the signer and chain, before running the action
- `action.success` — emitted on successful completion, includes `duration_ms`
- `action.error` — emitted on failure, includes `duration_ms`, `error_name`, `error_message`, `error_stack`

All events for a single run share the same `run_id` for correlation in Grafana.

See [`docs/automaton-observability.md`](../docs/automaton-observability.md) for the field schema and LogQL cookbook.

## Future: Prometheus

For SLO-grade metrics — p99 latency panels, alert rules with cheap evaluation, "no successful run in N hours" alarms, long-retention dashboards — the right next step is a Prometheus endpoint on the supervisor exposing:

- `automaton_runs_total{action,status}` — counter
- `automaton_run_duration_seconds{action}` — histogram
- `automaton_last_success_timestamp_seconds{action}` — gauge

Out of scope for now; logs are sufficient until we want recording rules or sub-second-cost alerting.
