#!/bin/bash

set -e

echo "🔍 PrometheusAgent Troubleshooting Script"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Step 1: Check current PrometheusAgent status
print_status "Checking current PrometheusAgent status..."
kubectl get prometheusagent -n monitoring || print_error "No PrometheusAgent found"

# Step 2: Check if pod is stuck
print_status "Checking PrometheusAgent pods..."
PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent --no-headers | wc -l)
if [ "$PODS" -gt 0 ]; then
    kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent
    
    # Check if any pods are in Terminating state
    TERMINATING=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent --field-selector=status.phase=Terminating --no-headers | wc -l)
    if [ "$TERMINATING" -gt 0 ]; then
        print_warning "Found pods in Terminating state. Attempting to force delete..."
        kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent --field-selector=status.phase=Terminating --no-headers | awk '{print $1}' | xargs -I {} kubectl delete pod {} -n monitoring --force --grace-period=0
    fi
else
    print_status "No PrometheusAgent pods found"
fi

# Step 3: Delete existing PrometheusAgent
print_status "Deleting existing PrometheusAgent..."
kubectl delete prometheusagent cluster-agent -n monitoring --ignore-not-found=true

# Step 4: Wait for cleanup
print_status "Waiting for cleanup..."
sleep 10

# Step 5: Check for ServiceMonitor CRD
print_status "Checking ServiceMonitor CRD..."
if kubectl get crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1; then
    print_success "ServiceMonitor CRD exists"
    
    # Check if metricRelabelConfigs field is available
    if kubectl get crd servicemonitors.monitoring.coreos.com -o yaml | grep -q metricRelabelConfigs; then
        print_success "metricRelabelConfigs field is available in ServiceMonitor CRD"
    else
        print_warning "metricRelabelConfigs field not found in ServiceMonitor CRD"
        print_status "Updating ServiceMonitor CRD..."
        kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.84.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
    fi
else
    print_error "ServiceMonitor CRD not found. Installing..."
    kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.84.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
fi

# Step 6: Check for PodMonitor CRD
print_status "Checking PodMonitor CRD..."
if kubectl get crd podmonitors.monitoring.coreos.com > /dev/null 2>&1; then
    print_success "PodMonitor CRD exists"
else
    print_error "PodMonitor CRD not found. Installing..."
    kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.84.1/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
fi

# Step 7: Check for PrometheusAgent CRD
print_status "Checking PrometheusAgent CRD..."
if kubectl get crd prometheusagents.monitoring.coreos.com > /dev/null 2>&1; then
    print_success "PrometheusAgent CRD exists"
else
    print_error "PrometheusAgent CRD not found. Installing..."
    kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.84.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheusagents.yaml
fi

# Step 8: Check namespace
print_status "Checking monitoring namespace..."
if kubectl get namespace monitoring > /dev/null 2>&1; then
    print_success "Monitoring namespace exists"
else
    print_status "Creating monitoring namespace..."
    kubectl create namespace monitoring
fi

# Step 9: Check if prometheus-operator is running
print_status "Checking prometheus-operator deployment..."
if kubectl get deployment prometheus-operator -n monitoring > /dev/null 2>&1; then
    READY=$(kubectl get deployment prometheus-operator -n monitoring -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment prometheus-operator -n monitoring -o jsonpath='{.spec.replicas}')
    if [ "$READY" = "$DESIRED" ]; then
        print_success "Prometheus operator is running ($READY/$DESIRED replicas ready)"
    else
        print_warning "Prometheus operator is not fully ready ($READY/$DESIRED replicas ready)"
    fi
else
    print_error "Prometheus operator not found in monitoring namespace"
    print_status "You may need to install the prometheus-operator first"
fi

# Step 10: Validate remote write endpoint
print_status "Testing remote write endpoint connectivity..."
if timeout 5 curl -s http://10.0.3.115:9090/api/v1/write > /dev/null 2>&1; then
    print_success "Remote write endpoint is reachable"
else
    print_warning "Remote write endpoint (http://10.0.3.115:9090/api/v1/write) may not be reachable"
fi

# Step 11: Check for required services
print_status "Checking for required services..."

# Check kubelet service
if kubectl get service kubelet -n kube-system > /dev/null 2>&1; then
    print_success "Kubelet service found"
else
    print_warning "Kubelet service not found - kubelet metrics may not work"
fi

# Check kube-state-metrics
if kubectl get deployment kube-state-metrics -n kube-system > /dev/null 2>&1; then
    print_success "kube-state-metrics deployment found"
elif kubectl get deployment kube-state-metrics -n monitoring > /dev/null 2>&1; then
    print_success "kube-state-metrics deployment found in monitoring namespace"
else
    print_warning "kube-state-metrics deployment not found"
fi

# Check node-exporter
if kubectl get daemonset prometheus-node-exporter -n monitoring > /dev/null 2>&1; then
    print_success "node-exporter daemonset found"
else
    print_warning "node-exporter daemonset not found"
fi

echo ""
print_status "Troubleshooting complete!"
print_status "Next steps:"
echo "1. Apply the fixed configuration: kubectl apply -f prometheus-agent-fixed.yaml"
echo "2. Monitor the pod startup: kubectl logs -f -n monitoring -l app.kubernetes.io/name=prometheus-agent"
echo "3. Check PrometheusAgent status: kubectl describe prometheusagent cluster-agent -n monitoring"