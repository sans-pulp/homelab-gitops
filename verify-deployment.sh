#!/bin/bash
# Verification script for media stack deployment

set -e

echo "=========================================="
echo "Media Stack Deployment Verification"
echo "=========================================="
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_status() {
    local resource=$1
    local namespace=${2:-default}
    local expected_count=${3:-1}
    
    local count=$(kubectl get $resource -n $namespace 2>/dev/null | grep -v NAME | wc -l)
    if [ "$count" -ge "$expected_count" ]; then
        echo -e "${GREEN}✓${NC} $resource: $count found"
        return 0
    else
        echo -e "${RED}✗${NC} $resource: Expected at least $expected_count, found $count"
        return 1
    fi
}

echo "Step 1: Check Flux Kustomizations"
echo "-----------------------------------"
kubectl get kustomizations -n flux-system | grep -E "sonarr|radarr|prowlarr|qbittorrent|NAME"
echo

echo "Step 2: Check PersistentVolumeClaims"
echo "-------------------------------------"
kubectl get pvc -n default | grep -E "config|NAME"
echo

echo "Step 3: Check PersistentVolumes"
echo "--------------------------------"
kubectl get pv | grep -E "config|NAME"
echo

echo "Step 4: Check Deployments"
echo "-------------------------"
kubectl get deployments -n default | grep -E "sonarr|radarr|prowlarr|qbittorrent|NAME"
echo

echo "Step 5: Check Pods Status"
echo "--------------------------"
kubectl get pods -n default | grep -E "sonarr|radarr|prowlarr|qbittorrent|NAME"
echo

echo "Step 6: Check Services"
echo "----------------------"
kubectl get svc -n default | grep -E "sonarr|radarr|prowlarr|qbittorrent|NAME"
echo

echo "Step 7: Check Ingress"
echo "---------------------"
kubectl get ingress -n default | grep -E "sonarr|radarr|prowlarr|qbittorrent|NAME"
echo

echo "Step 8: Verify Pods are Running"
echo "---------------------------------"
for app in sonarr radarr prowlarr qbittorrent; do
    status=$(kubectl get pod -n default -l app=$app -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$status" == "Running" ]; then
        echo -e "${GREEN}✓${NC} $app: Running"
    else
        echo -e "${RED}✗${NC} $app: $status"
        echo "  Details:"
        kubectl get pod -n default -l app=$app -o wide 2>/dev/null || echo "    Pod not found"
    fi
done
echo

echo "Step 9: Check Pod Logs (last 5 lines)"
echo "--------------------------------------"
for app in sonarr radarr prowlarr qbittorrent; do
    echo "--- $app logs ---"
    kubectl logs -n default -l app=$app --tail=5 2>/dev/null || echo "  No logs available"
    echo
done

echo "Step 10: Verify Storage Mounts"
echo "-------------------------------"
for app in sonarr radarr prowlarr qbittorrent; do
    echo "--- $app volumes ---"
    kubectl get pod -n default -l app=$app -o jsonpath='{.items[0].spec.volumes[*].persistentVolumeClaim.claimName}' 2>/dev/null || echo "  Pod not found"
    echo
done

echo "Step 11: Test Service Connectivity"
echo "-----------------------------------"
for app in sonarr radarr prowlarr qbittorrent; do
    port=$(kubectl get svc -n default $app -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")
    if [ -n "$port" ]; then
        if kubectl run -it --rm test-$app --image=curlimages/curl --restart=Never --timeout=5s -- curl -s -o /dev/null -w "%{http_code}" http://$app.default.svc.cluster.local:$port 2>/dev/null | grep -q "200\|401\|302"; then
            echo -e "${GREEN}✓${NC} $app service responding on port $port"
        else
            echo -e "${YELLOW}⚠${NC} $app service may not be ready (port $port)"
        fi
        kubectl delete pod test-$app -n default 2>/dev/null || true
    else
        echo -e "${RED}✗${NC} $app service not found"
    fi
done
echo

echo "=========================================="
echo "Verification Complete"
echo "=========================================="

