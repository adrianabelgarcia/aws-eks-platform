# Runbook: sample-api SLO burn

| | |
|---|---|
| Severity | Per alert: `severity=page` pages on call, `severity=ticket` opens a ticket. |
| Alerts | `SampleApiAvailabilityBurnRateFast`, `SampleApiAvailabilityBurnRateSlow`, `SampleApiAvailabilityBurnRateTicket`, `SampleApiLatencyBurnRateFast`, `SampleApiLatencyBurnRateSlow` |
| Owner | Platform on-call, with the sample-api owners |
| Rules | `gitops/platform/monitoring/sample-api-slo-rules.yaml` |
| Objectives | [slo.md](../slo.md) |

## Symptoms

- A page for a burn-rate alert. The alert annotation shows the current error ratio.
- Users report errors or slow responses, or the synthetic check fails.

## Triage

Start with the blast radius, then the cause. Prometheus is reachable through the port-forward below.

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
# Error ratio now, per 5 minute window
curl -s 'http://localhost:9090/api/v1/query?query=sli:sample_api_http_errors:ratio_rate5m' | jq '.data.result'
# Which status codes?
curl -s 'http://localhost:9090/api/v1/query?query=sum by (code) (rate(http_requests_total{job="sample-api",code=~"5.."}[5m]))' | jq '.data.result'
# Latency: fraction over 300 ms
curl -s 'http://localhost:9090/api/v1/query?query=sli:sample_api_slow_requests:ratio_rate5m' | jq '.data.result'
```

Then check what changed and where the errors come from:

```bash
# Recent rollout?
kubectl -n sample-api rollout history deploy/sample-api
argocd app history sample-api | head -10
kubectl -n sample-api get pods -o wide && kubectl -n sample-api get events --sort-by=.lastTimestamp | tail -20

# Load balancer target health (ALB)
TG=$(aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName,'sample-api')].TargetGroupArn | [0]" --output text)
aws elbv2 describe-target-health --target-group-arn "$TG" --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output table

# Logs from the failing pods (JSON logs)
kubectl -n sample-api logs deploy/sample-api --since=15m | grep -i '"level":"error"' | tail -40
```

## Mitigation

Choose the smallest action that stops the burn.

1. **Recent release is the likely cause (most common).** Roll back through Argo CD so Git still matches the cluster:
   ```bash
   argocd app history sample-api
   argocd app rollback sample-api <previous-id>
   ```
   Then revert the commit on `main` so the next sync does not re-deploy the bad version.
2. **Overload** (latency and 5xx under load, CPU near the HPA target): raise `maxReplicas` in the overlay, or let the HPA scale.
   Check Karpenter capacity (see [karpenter-not-provisioning](karpenter-not-provisioning.md)).
3. **A dependency is failing**: confirm in the logs. Use the dependency's own runbook. Consider a feature flag to disable the call path.
4. **Unhealthy targets**: pods failing readiness. Check the probe endpoint and recent config changes.
5. **Ingress or DNS**: the ALB or ExternalDNS record is wrong. Check the Ingress annotations in Git, then `kubectl -n sample-api describe ingress sample-api`.

After mitigation, confirm the 5-minute error and latency ratios fall back under the thresholds. The burn alerts
resolve only after the long window recovers, which can take up to 6 hours. That lag is expected. Do not
delay the all-clear for it.

## Root cause (common)

- A release with a regression that tests did not catch.
- Connection pool or memory exhaustion under load, visible as 5xx or as p99 latency.
- A dependency outage that the service does not handle with a timeout or fallback.
- A node or zone problem reducing capacity (see [node-not-ready](node-not-ready.md)).

## Prevention

- Use progressive delivery for changes to the request path, starting with a canary of one replica.
- Keep the PodDisruptionBudget and topology spread in place. They limit the blast radius of node failures.
- Review error budget status at the monthly reliability review. Follow the error budget policy in [slo.md](../slo.md).
- After each page, write a short review: detection time, mitigation time, and one follow-up item.
