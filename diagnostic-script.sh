#!/bin/bash

echo "=== EKS Container Metrics Diagnostic Script ==="
echo "This script will help diagnose issues with container_cpu_usage_seconds_total labels"
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl is not installed or not in PATH"
        exit 1
    fi
    echo "✅ kubectl is available"
}

# Function to check cluster connectivity
check_cluster_connectivity() {
    echo ""
    echo "🔍 Checking cluster connectivity..."
    if kubectl cluster-info &> /dev/null; then
        echo "✅ Connected to cluster: $(kubectl config current-context)"
    else
        echo "❌ Cannot connect to cluster"
        exit 1
    fi
}

# Function to check if monitoring namespace exists
check_monitoring_namespace() {
    echo ""
    echo "🔍 Checking monitoring namespace..."
    if kubectl get namespace monitoring &> /dev/null; then
        echo "✅ Monitoring namespace exists"
    else
        echo "❌ Monitoring namespace does not exist"
        echo "Create it with: kubectl create namespace monitoring"
        exit 1
    fi
}

# Function to check kubelet service
check_kubelet_service() {
    echo ""
    echo "🔍 Checking kubelet service in kube-system..."
    if kubectl get service -n kube-system -l k8s-app=kubelet &> /dev/null; then
        echo "✅ Kubelet service found"
        kubectl get service -n kube-system -l k8s-app=kubelet
    else
        echo "⚠️  Kubelet service not found with label k8s-app=kubelet"
        echo "Available services in kube-system:"
        kubectl get services -n kube-system
    fi
}

# Function to check direct cAdvisor metrics from a node
check_cadvisor_direct() {
    echo ""
    echo "🔍 Checking cAdvisor metrics directly from kubelet..."
    
    # Get a node name
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$NODE_NAME" ]; then
        echo "❌ No nodes found in cluster"
        return 1
    fi
    
    echo "Testing on node: $NODE_NAME"
    
    # Try to get cAdvisor metrics
    echo "Fetching container_cpu_usage_seconds_total metrics..."
    METRICS=$(kubectl get --raw "/api/v1/nodes/$NODE_NAME/proxy/metrics/cadvisor" 2>/dev/null | grep "container_cpu_usage_seconds_total" | head -5)
    
    if [ -n "$METRICS" ]; then
        echo "✅ cAdvisor metrics are available. Sample metrics:"
        echo "$METRICS"
        
        # Check if labels are present
        if echo "$METRICS" | grep -q 'pod="[^"]*"' && echo "$METRICS" | grep -q 'namespace="[^"]*"'; then
            echo "✅ Pod and namespace labels are present in the raw metrics"
        else
            echo "⚠️  Pod or namespace labels might be missing in raw metrics"
        fi
    else
        echo "❌ No container_cpu_usage_seconds_total metrics found"
        echo "This might indicate a cAdvisor configuration issue"
    fi
}

# Function to check Prometheus Agent status
check_prometheus_agent() {
    echo ""
    echo "🔍 Checking Prometheus Agent status..."
    
    if kubectl get prometheusagent -n monitoring cluster-agent &> /dev/null; then
        echo "✅ Prometheus Agent 'cluster-agent' found"
        
        # Check if it's ready
        STATUS=$(kubectl get prometheusagent -n monitoring cluster-agent -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$STATUS" = "True" ]; then
            echo "✅ Prometheus Agent is ready"
        else
            echo "⚠️  Prometheus Agent might not be ready"
            echo "Status:"
            kubectl get prometheusagent -n monitoring cluster-agent -o yaml | grep -A 10 "status:"
        fi
    else
        echo "❌ Prometheus Agent 'cluster-agent' not found"
    fi
}

# Function to check ServiceMonitors
check_service_monitors() {
    echo ""
    echo "🔍 Checking ServiceMonitors..."
    
    SM_COUNT=$(kubectl get servicemonitor -n monitoring --selector=release=prometheus-agent --no-headers 2>/dev/null | wc -l)
    if [ "$SM_COUNT" -gt 0 ]; then
        echo "✅ Found $SM_COUNT ServiceMonitors with release=prometheus-agent"
        kubectl get servicemonitor -n monitoring --selector=release=prometheus-agent
        
        # Check kubelet-metrics specifically
        if kubectl get servicemonitor -n monitoring kubelet-metrics &> /dev/null; then
            echo "✅ kubelet-metrics ServiceMonitor found"
        else
            echo "⚠️  kubelet-metrics ServiceMonitor not found"
        fi
    else
        echo "❌ No ServiceMonitors found with release=prometheus-agent"
    fi
}

# Function to check pod resource definitions
check_pod_resources() {
    echo ""
    echo "🔍 Checking if pods have resource requests/limits defined..."
    
    # Get a sample of pods and check their resource definitions
    PODS_WITHOUT_RESOURCES=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[].resources.requests.cpu == null or .spec.containers[].resources.requests.memory == null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -5)
    
    if [ -n "$PODS_WITHOUT_RESOURCES" ]; then
        echo "⚠️  Found pods without resource requests (this can affect metric labels):"
        echo "$PODS_WITHOUT_RESOURCES"
        echo ""
        echo "Consider adding resource requests to your pod specifications:"
        echo "resources:"
        echo "  requests:"
        echo "    cpu: 100m"
        echo "    memory: 100Mi"
    else
        echo "✅ Most pods have resource requests defined"
    fi
}

# Function to test metric query
test_metric_query() {
    echo ""
    echo "🔍 Testing metric availability..."
    
    # Check if we can port-forward to prometheus agent
    echo "Attempting to check Prometheus Agent metrics endpoint..."
    
    # Get prometheus agent pod
    PROM_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$PROM_POD" ]; then
        echo "Found Prometheus Agent pod: $PROM_POD"
        
        # Test if we can access the metrics endpoint
        echo "Testing metrics endpoint access..."
        timeout 10s kubectl port-forward -n monitoring pod/$PROM_POD 9090:9090 &
        PF_PID=$!
        sleep 3
        
        # Try to query metrics
        if curl -s http://localhost:9090/metrics | grep -q "prometheus_agent"; then
            echo "✅ Prometheus Agent metrics endpoint is accessible"
        else
            echo "⚠️  Cannot access Prometheus Agent metrics endpoint"
        fi
        
        # Clean up port-forward
        kill $PF_PID 2>/dev/null
    else
        echo "❌ Prometheus Agent pod not found"
    fi
}

# Function to provide recommendations
provide_recommendations() {
    echo ""
    echo "📋 RECOMMENDATIONS:"
    echo ""
    echo "1. Apply the fixed configuration:"
    echo "   kubectl apply -f prometheus-config-fixed.yaml"
    echo ""
    echo "2. Ensure all your application pods have resource requests/limits:"
    echo "   resources:"
    echo "     requests:"
    echo "       cpu: 100m"
    echo "       memory: 100Mi"
    echo "     limits:"
    echo "       cpu: 500m"
    echo "       memory: 500Mi"
    echo ""
    echo "3. Wait 2-3 minutes after applying changes, then verify metrics:"
    echo "   kubectl get --raw \"/api/v1/nodes/\$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')/proxy/metrics/cadvisor\" | grep container_cpu_usage_seconds_total | head -3"
    echo ""
    echo "4. Check Prometheus Agent logs if issues persist:"
    echo "   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-agent"
    echo ""
    echo "5. Verify your EKS cluster version supports the required metrics:"
    echo "   kubectl version --short"
}

# Main execution
main() {
    check_kubectl
    check_cluster_connectivity
    check_monitoring_namespace
    check_kubelet_service
    check_cadvisor_direct
    check_prometheus_agent
    check_service_monitors
    check_pod_resources
    test_metric_query
    provide_recommendations
}

# Run the diagnostic
main