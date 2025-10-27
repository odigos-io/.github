# Grafana "No Data" Troubleshooting Checklist

## Immediate Actions (Do These First) 🚨

### 1. Test Remote Write Endpoint
```bash
# Test if your remote Prometheus is reachable
curl -v "http://10.0.3.115:9090/api/v1/query?query=up"

# Expected: Should return JSON with data
# If this fails, your remote Prometheus is not accessible
```

### 2. Check Grafana Data Source
- Go to Grafana → Configuration → Data Sources
- Verify URL points to: `http://10.0.3.115:9090`
- Test connection with "Save & Test" button
- If it fails, this is your main issue

### 3. Check Time Range in Grafana
- Try "Last 5 minutes" instead of longer ranges
- Prometheus Agent might have just started collecting data

## Kubernetes Diagnostics 🔍

### 4. Verify Prometheus Agent is Running
```bash
kubectl get pods -n monitoring | grep prometheus-agent
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-agent --tail=50
```

### 5. Check ServiceMonitor Discovery
```bash
# See what services your ServiceMonitors are trying to find
kubectl get svc -n kube-system -l k8s-app=kubelet
kubectl get svc -n kube-system -l app.kubernetes.io/name=kube-state-metrics
kubectl get svc -n default kubernetes

# If any of these return "No resources found", that's your issue
```

### 6. Test Basic Connectivity from Pod
```bash
# Get into the Prometheus Agent pod
kubectl exec -it -n monitoring deployment/prometheus-agent -- /bin/sh

# Test remote write endpoint from inside the cluster
wget -qO- --timeout=5 "http://10.0.3.115:9090/api/v1/query?query=up"
```

## Most Common Root Causes 🎯

1. **Remote Prometheus not accessible** (80% of cases)
   - Network connectivity issues
   - Firewall blocking port 9090
   - Remote Prometheus not running

2. **ServiceMonitor selectors don't match** (15% of cases)
   - Services have different labels than expected
   - Services are in different namespaces

3. **Grafana pointing to wrong Prometheus** (3% of cases)
   - Data source URL incorrect
   - Authentication issues

4. **Time range issues** (2% of cases)
   - Looking at wrong time period
   - Prometheus Agent just started

## Quick Fixes to Try 🔧

### Fix 1: Simplify Remote Write Config
```yaml
remoteWrite:
- url: "http://10.0.3.115:9090/api/v1/write"
  # Remove all writeRelabelConfigs temporarily
```

### Fix 2: Add Debug ServiceMonitor
Apply the debug ServiceMonitor from `prometheus-agent-fixed.yaml` to test basic functionality.

### Fix 3: Check Alternative Service Labels
```bash
# Sometimes kubelet service has different labels
kubectl get svc -n kube-system --show-labels | grep kubelet
```

## Verification Steps ✅

Once you think it's fixed:

1. **Wait 2-3 minutes** for metrics to be scraped and written
2. **Check remote Prometheus**: `curl "http://10.0.3.115:9090/api/v1/query?query=up"`
3. **Refresh Grafana** and try "Last 5 minutes" time range
4. **Look for any data**: Try simple queries like `up` or `prometheus_build_info`

## Emergency Bypass 🚑

If nothing works, create a simple test:

1. Deploy the debug metrics pod from `prometheus-agent-fixed.yaml`
2. This creates a simple metrics endpoint that should definitely work
3. If even this doesn't show data, the problem is definitely with remote write or Grafana config

## Run the Debug Script

```bash
chmod +x debug-prometheus-agent.sh
./debug-prometheus-agent.sh
```

This will systematically check all common issues and provide specific guidance.