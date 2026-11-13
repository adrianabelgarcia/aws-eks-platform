# Service Level Objectives: sample-api

This document defines what "reliable enough" means for `sample-api`, how it is measured, and what the
team does when it is not. The alerts that enforce these objectives are in
`gitops/platform/monitoring/sample-api-slo-rules.yaml`.

## 1. Service

`sample-api` is a stateless HTTP API behind an internet-facing ALB, running as a Deployment in the
`sample-api` namespace with 2 to 10 replicas in staging and 3 to 20 in prod. Traffic is spread across three
availability zones.

## 2. Service Level Indicators (SLIs)

| SLI | Definition | Source |
|---|---|---|
| Availability | Fraction of HTTP requests that do not return a 5xx status, measured at the service | `http_requests_total{job="sample-api"}` by `code` |
| Latency | Fraction of HTTP requests answered in under 300 ms | `http_request_duration_seconds` histogram, `le="0.3"` bucket |

Both SLIs are request-based (not time-based), so a quiet hour with few requests counts proportionally.
Client-side errors (4xx) are good responses for this service and do not count against availability.

The SLIs are measured at the service, not at the ALB. ALB-level 5xx responses from target health checks
during a deploy would overstate failure, and service-level measurement keeps the numbers attributable to the
application. The ALB access logs remain the source of truth for user-visible errors if the two disagree.

## 3. Service Level Objectives (SLOs)

| Objective | Target | Window | Error budget |
|---|---|---|---|
| Availability | 99.9% of requests are non-5xx | rolling 30 days | 0.1% of requests (about 43 minutes of full outage per 30 days) |
| Latency | 99% of requests complete in under 300 ms | rolling 30 days | 1% of requests |

The targets are set below the platform's own capability (multi-AZ capacity, PDB, zone spread) so that the
budget absorbs planned events such as node rotations and EKS upgrades without a page.

## 4. Error budget policy

The error budget is the allowed unreliability: 0.1% of requests for availability, 1% for latency.

| Budget remaining (30-day window) | Action |
|---|---|
| more than 50% | Normal delivery. Ship features and experiments. |
| 25% to 50% | Review recent incidents. Feature work continues, with one reliability item per sprint. |
| 0% to 25% | Feature releases to sample-api pause until the budget recovers. Reliability work takes priority. |
| exhausted (below 0%) | Freeze non-urgent changes to sample-api. A review of the top three causes is required before the freeze ends. Escalate to the engineering lead. |

Exceptions require a written decision from the engineering lead, recorded in the incident or ticket.
Security fixes and rollbacks are never blocked by the policy.

## 5. Burn-rate alerts

A burn rate is how fast the budget is being consumed relative to the rate that would exhaust it exactly
at the end of the window. A burn rate of 1 uses the budget at the sustainable pace. Each alert requires a
long window (the budget is really being spent) and a short window (it is still being spent now). The alert
then clears quickly once the problem stops.

| Alert | SLI | Long window | Short window | Burn rate | Budget spent if sustained | Severity |
|---|---|---|---|---|---|---|
| `SampleApiAvailabilityBurnRateFast` | availability | 1h | 5m | 14.4 | 2% in 1 hour, budget gone in about 2 days | page |
| `SampleApiAvailabilityBurnRateSlow` | availability | 6h | 30m | 6 | 5% in 6 hours, budget gone in about 5 days | page |
| `SampleApiAvailabilityBurnRateTicket` | availability | 1d | 2h | 3 | 10% in a day, budget gone in about 10 days | ticket |
| `SampleApiLatencyBurnRateFast` | latency | 1h | 5m | 14.4 | 14.4% of requests slow in the hour | page |
| `SampleApiLatencyBurnRateSlow` | latency | 6h | 30m | 6 | 6% of requests slow in the window | ticket |

The thresholds follow the multi-window, multi-burn-rate method in the Google SRE Workbook (chapter 5). The
1-day availability and 6-hour latency alerts are tickets, not pages, because they are slower and do not need
an immediate response.

Every alert links to [runbooks/sample-api-slo-burn.md](runbooks/sample-api-slo-burn.md).

## 6. Dashboards and measurement

- Recording rules `sli:sample_api_http_errors:ratio_rate*` and `sli:sample_api_slow_requests:ratio_rate*` are the
  single source for both alerts and dashboards. Dashboards must not recompute the SLI differently.
- The sample-api service must expose `http_requests_total` (labels `job`, `code`) and
  `http_request_duration_seconds` (histogram with a bucket at 0.3 seconds). Without the 0.3 bucket the latency
  SLI cannot be computed, so changing the threshold requires changing the rule and this document together.

## 7. Review

- The SLO is reviewed each quarter. Targets change only with an ADR or a documented decision.
- Each page produces a short review (see the runbook's Prevention section).
- The monthly reliability review reads the budget status for each SLO and applies the policy above.
