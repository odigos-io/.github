#!/bin/bash

set -e

echo "🔍 PrometheusAgent Debug Script"
echo "=============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Get the pod name
POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent --no-headers -o custom-columns=":metadata.name" | head -1)

if [ -z "$POD_NAME" ]; then
    print_error "No PrometheusAgent pod found"
    exit 1
fi

print_status "Found PrometheusAgent pod: $POD_NAME"

# Check pod status
print_status "Pod status:"
kubectl get pod $POD_NAME -n monitoring -o wide

echo ""
print_status "Pod events:"
kubectl describe pod $POD_NAME -n monitoring | grep -A 20 "Events:"

echo ""
print_status "Container statuses:"
kubectl get pod $POD_NAME -n monitoring -o jsonpath='{.status.containerStatuses[*].name}' | tr ' ' '\n' | while read container; do
    echo "Container: $container"
    kubectl get pod $POD_NAME -n monitoring -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state}"
    echo ""
done

echo ""
print_status "Init container statuses:"
kubectl get pod $POD_NAME -n monitoring -o jsonpath='{.status.initContainerStatuses[*].name}' | tr ' ' '\n' | while read container; do
    echo "Init Container: $container"
    kubectl get pod $POD_NAME -n monitoring -o jsonpath="{.status.initContainerStatuses[?(@.name=='$container')].state}"
    echo ""
done

echo ""
print_status "Checking prometheus container logs..."
if kubectl logs $POD_NAME -n monitoring -c prometheus --tail=50 2>/dev/null; then
    print_success "Prometheus container logs retrieved"
else
    print_warning "Could not retrieve prometheus container logs (container may not be running yet)"
fi

echo ""
print_status "Checking config-reloader container logs..."
if kubectl logs $POD_NAME -n monitoring -c config-reloader --tail=50 2>/dev/null; then
    print_success "Config-reloader container logs retrieved"
else
    print_warning "Could not retrieve config-reloader container logs"
fi

echo ""
print_status "Checking init-config-reloader logs..."
if kubectl logs $POD_NAME -n monitoring -c init-config-reloader --tail=50 2>/dev/null; then
    print_success "Init-config-reloader logs retrieved"
else
    print_warning "Could not retrieve init-config-reloader logs"
fi

echo ""
print_status "Checking generated prometheus configuration..."
if kubectl exec $POD_NAME -n monitoring -c init-config-reloader -- cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null; then
    print_success "Generated prometheus configuration retrieved"
else
    print_warning "Could not retrieve generated prometheus configuration"
fi

echo ""
print_status "Checking PrometheusAgent resource status..."
kubectl describe prometheusagent cluster-agent -n monitoring

echo ""
print_status "Checking ServiceMonitors..."
kubectl get servicemonitors -n monitoring -o wide

echo ""
print_status "Checking PodMonitors..."
kubectl get podmonitors -n monitoring -o wide

echo ""
print_status "Debug complete!"