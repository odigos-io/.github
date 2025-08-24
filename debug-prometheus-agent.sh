#!/bin/bash

echo "=== Prometheus Agent Debugging Script ==="
echo "This script will help diagnose why Grafana shows 'No data'"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# 1. Check if Prometheus Agent is running
print_section "Checking Prometheus Agent Status"
if kubectl get prometheusagent -n monitoring cluster-agent >/dev/null 2>&1; then
    print_success "Prometheus Agent exists"
    kubectl get prometheusagent -n monitoring cluster-agent -o wide
else
    print_error "Prometheus Agent not found"
    exit 1
fi

# Check pods
echo -e "\nPrometheus Agent Pods:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent

# 2. Check remote write endpoint connectivity
print_section "Testing Remote Write Endpoint"
REMOTE_URL="http://10.0.3.115:9090"

# Test basic connectivity
if curl -s --connect-timeout 5 "$REMOTE_URL/api/v1/query?query=up" >/dev/null; then
    print_success "Remote Prometheus endpoint is reachable"
    
    # Test if it has data
    UP_METRICS=$(curl -s "$REMOTE_URL/api/v1/query?query=up" | jq -r '.data.result | length' 2>/dev/null)
    if [ "$UP_METRICS" -gt 0 ]; then
        print_success "Remote Prometheus has $UP_METRICS 'up' metrics"
    else
        print_warning "Remote Prometheus is reachable but has no 'up' metrics"
    fi
else
    print_error "Cannot reach remote Prometheus at $REMOTE_URL"
    print_warning "This is likely the main issue - check network connectivity and firewall rules"
fi

# 3. Check ServiceMonitor targets
print_section "Checking ServiceMonitor Target Discovery"

echo "ServiceMonitors in monitoring namespace:"
kubectl get servicemonitor -n monitoring -o name

echo -e "\nChecking if target services exist:"

# Check kubelet service
if kubectl get svc -n kube-system -l k8s-app=kubelet >/dev/null 2>&1; then
    print_success "kubelet service found"
    kubectl get svc -n kube-system -l k8s-app=kubelet
else
    print_error "kubelet service with label 'k8s-app=kubelet' not found"
    echo "Available services in kube-system:"
    kubectl get svc -n kube-system
fi

# Check kube-state-metrics
if kubectl get svc -n kube-system -l app.kubernetes.io/name=kube-state-metrics >/dev/null 2>&1; then
    print_success "kube-state-metrics service found"
    kubectl get svc -n kube-system -l app.kubernetes.io/name=kube-state-metrics
else
    print_error "kube-state-metrics service not found in kube-system"
    # Check if it's in monitoring namespace
    if kubectl get svc -n monitoring -l app.kubernetes.io/name=kube-state-metrics >/dev/null 2>&1; then
        print_warning "kube-state-metrics found in monitoring namespace instead"
        kubectl get svc -n monitoring -l app.kubernetes.io/name=kube-state-metrics
    fi
fi

# Check API server
if kubectl get svc -n default kubernetes >/dev/null 2>&1; then
    print_success "API server service (kubernetes) found in default namespace"
    kubectl get svc -n default kubernetes
else
    print_error "API server service not found"
fi

# 4. Check node-exporter pods
print_section "Checking Node Exporter Pods"
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter >/dev/null 2>&1; then
    print_success "Node exporter pods found"
    kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter
else
    print_error "Node exporter pods not found with expected labels"
    echo "Checking for node exporter with different labels:"
    kubectl get pods -n monitoring | grep -i node
fi

# 5. Check Prometheus Agent logs
print_section "Checking Prometheus Agent Logs (last 20 lines)"
AGENT_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$AGENT_POD" ]; then
    echo "Logs from pod: $AGENT_POD"
    kubectl logs -n monitoring "$AGENT_POD" --tail=20
    
    # Check for specific error patterns
    echo -e "\nChecking for common error patterns:"
    if kubectl logs -n monitoring "$AGENT_POD" | grep -i "remote.*write.*error" >/dev/null; then
        print_error "Found remote write errors in logs"
    fi
    
    if kubectl logs -n monitoring "$AGENT_POD" | grep -i "failed.*scrape" >/dev/null; then
        print_error "Found scraping failures in logs"
    fi
    
    if kubectl logs -n monitoring "$AGENT_POD" | grep -i "no.*targets" >/dev/null; then
        print_error "Found 'no targets' messages in logs"
    fi
else
    print_error "No Prometheus Agent pod found"
fi

# 6. Test metric availability
print_section "Testing Metric Availability"
if command -v curl >/dev/null && kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent >/dev/null 2>&1; then
    echo "Port-forwarding to Prometheus Agent (this may take a moment)..."
    kubectl port-forward -n monitoring svc/prometheus-agent 9090:9090 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
    
    if curl -s http://localhost:9090/metrics | head -5 >/dev/null; then
        print_success "Prometheus Agent metrics endpoint is accessible"
        METRIC_COUNT=$(curl -s http://localhost:9090/metrics | wc -l)
        echo "Total metrics lines: $METRIC_COUNT"
    else
        print_error "Cannot access Prometheus Agent metrics"
    fi
    
    kill $PF_PID 2>/dev/null
fi

# 7. Summary and recommendations
print_section "Summary and Next Steps"
echo "Common causes of 'No data' in Grafana:"
echo "1. Remote write endpoint not accessible (most common)"
echo "2. ServiceMonitor selectors don't match actual services"
echo "3. Grafana data source pointing to wrong Prometheus instance"
echo "4. Time range issues in Grafana"
echo "5. Metric relabeling dropping all metrics"
echo
echo "Recommended immediate actions:"
echo "1. Verify remote write endpoint: curl $REMOTE_URL/api/v1/query?query=up"
echo "2. Check Grafana data source configuration"
echo "3. Verify time range in Grafana (try 'Last 5 minutes')"
echo "4. Check if any metrics exist: curl $REMOTE_URL/api/v1/label/__name__/values"
echo
print_warning "Run this script with: bash debug-prometheus-agent.sh"