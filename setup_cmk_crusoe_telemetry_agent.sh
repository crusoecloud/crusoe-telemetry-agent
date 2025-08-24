#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

JOB_NAME="crusoe-monitoring-token-job"
NAMESPACE="crusoe-system"
SECRET_NAME="crusoe-secrets"
GPU_CLUSTER="false"

echo "---[ 0. Validating pre-requisites ]---"

# Check if the namespace exists
if ! kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1; then
  echo "❌ Error: Namespace '${NAMESPACE}' does not exist. Please create it before running this script."
  exit 1
fi

# Check if the secret exists in the specified namespace
if ! kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" > /dev/null 2>&1; then
  echo "❌ Error: Secret '${SECRET_NAME}' does not exist in namespace '${NAMESPACE}'. Please create it before running this script."
  exit 1
fi

echo "✅ Namespace '${NAMESPACE}' and Secret '${SECRET_NAME}' validated successfully."

# --- Validate required components if its a GPU cluster ---
echo "---[ 1. Validating GPU cluster components ]---"

if kubectl get namespace nvidia-gpu-operator >/dev/null 2>&1; then
  echo "🔍 Namespace 'nvidia-gpu-operator' found."
  # Check if the nvidia-dcgm-exporter application exists (via pod label)
  if kubectl get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter -o name | grep -q .; then
    echo "✅ 'nvidia-dcgm-exporter' application found. Applying its service manifest."
    GPU_CLUSTER="true"
    # Create configmap for dcgm-exporter metrics config
    kubectl create configmap dcgm-exporter-config \
      --from-literal=dcp-metrics-included.csv="$(curl -sL https://raw.githubusercontent.com/crusoecloud/crusoe-telemetry-agent/refs/heads/main/config/dcp-metrics-included.csv)" \
      -n nvidia-gpu-operator

    # Patch dcgm-exporter daemonset to use custom dcgm-exporter metrics file
    kubectl patch daemonset nvidia-dcgm-exporter \
      -n nvidia-gpu-operator \
      --type='strategic' \
      -p '{
        "spec": {
          "template": {
            "spec": {
              "volumes": [
                {
                  "name": "dcgm-exporter-config",
                  "configMap": {
                    "name": "dcgm-exporter-config",
    				"items": [
    					{
    						"key": "dcp-metrics-included.csv",
    						"path": "dcp-metrics-custom.csv"
    					}
    				]
                  }
                }
              ],
              "containers": [
                {
                  "name": "nvidia-dcgm-exporter",
                  "volumeMounts": [
                    {
                      "name": "dcgm-exporter-config",
                      "mountPath": "/etc/dcgm-exporter/dcp-metrics-custom.csv",
                      "subPath": "dcp-metrics-custom.csv"
                    }
                  ]
                }
              ]
            }
          }
        }
      }'

    kubectl patch daemonset nvidia-dcgm-exporter \
      -n nvidia-gpu-operator \
      --type='strategic' \
      -p '{
        "spec": {
          "template": {
            "spec": {
              "containers": [
                {
                  "name": "nvidia-dcgm-exporter",
                  "env": [
                    {
                      "name": "DCGM_EXPORTER_COLLECTORS",
                      "value": "/etc/dcgm-exporter/dcp-metrics-custom.csv"
                    }
                  ]
                }
              ]
            }
          }
        }
      }'

    # Create the Kubernetes Service manifest using a Here Document
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nvidia-dcgm-exporter
  name: nvidia-dcgm-exporter-np
  namespace: nvidia-gpu-operator
spec:
  internalTrafficPolicy: Local
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - name: gpu-metrics
    port: 9401
    protocol: TCP
    targetPort: 9400
  selector:
    app: nvidia-dcgm-exporter
  sessionAffinity: None
  type: NodePort
status:
  loadBalancer: {}
EOF

    echo "Waiting 5 seconds to validate service status..."
    sleep 5
    if kubectl get service nvidia-dcgm-exporter-np -n nvidia-gpu-operator >/dev/null 2>&1; then
      echo "✅ Service 'nvidia-dcgm-exporter-np' is running."
    else
      echo "❌ Service 'nvidia-dcgm-exporter-np' failed to start."
      exit 1
    fi
  else
    echo "⚠️ Namespace 'nvidia-gpu-operator' found, but 'nvidia-dcgm-exporter' application was not. Skipping service manifest."
  fi
else
  echo "⚠️ Namespace 'nvidia-gpu-operator' not found. Skipping optional service manifest."
fi

echo "---[ 2. Creating Crusoe monitoring job ]---"

# --- Create the Kubernetes Manifest YAML using a Here Document ---
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secret-manager-sa
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secret-creator-reader-global
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]
  verbs: ["create", "get"]
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["create", "get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: secret-manager-sa-global-binding
subjects:
- kind: ServiceAccount
  name: secret-manager-sa
  namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: secret-creator-reader-global
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      serviceAccountName: secret-manager-sa
      restartPolicy: Never
      containers:
      - name: ubuntu-worker
        image: ubuntu:22.04
        envFrom:
        - secretRef:
            name: ${SECRET_NAME}
        command:
        - /bin/bash
        - -c
        - |
          set -e
          set -x

          echo "---[ 1. Installing dependencies ]---"
          apt-get update
          apt-get install -y curl ca-certificates

          echo "---[ 2. Installing kubectl ]---"
          KUBE_LATEST=\$(curl -L -s https://dl.k8s.io/release/stable.txt)
          curl -LO "https://dl.k8s.io/release/\${KUBE_LATEST}/bin/linux/amd64/kubectl"
          install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
          kubectl version --client

          echo "---[ 3. Installing Crusoe CLI ]---"
          # NOTE: Please verify this is the correct URL for the desired Crusoe CLI version.
          echo "deb [trusted=yes] https://apt.fury.io/crusoe/ * *" > /etc/apt/sources.list.d/fury.list
          apt update
          apt install crusoe
          export CRUSOE_ACCESS_KEY_ID="\${CRUSOE_ACCESS_KEY}"
          crusoe whoami
          
          echo "---[ 4. Create crusoe monitoring token ]---"
          export CRUSOE_MONITORING_TOKEN=\`crusoe monitoring tokens create |  grep "monitor token:" | awk '{print \$3}'\`

          # Create the 'crusoe-monitoring' secret in the '${NAMESPACE}' namespace. Using apply for idempotency.
          kubectl create secret generic crusoe-monitoring --from-literal=CRUSOE_MONITORING_TOKEN="\${CRUSOE_MONITORING_TOKEN}" -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
          
          echo "---[ 5. Verifying secret creation ]---"
          kubectl get secret crusoe-monitoring -n ${NAMESPACE} -o yaml
          
          echo "---[ Job finished successfully ]---"
EOF

echo "✅ Successfully applied Kubernetes manifests."
echo "---[ Waiting for job to complete or fail ]---"

## Wait for job completion in the background
#kubectl wait --for=condition=complete job/${JOB_NAME} -n ${NAMESPACE} --timeout=300s &
#completion_pid=$!
#
## Wait for job failure in the background
#kubectl wait --for=condition=failed job/${JOB_NAME} -n ${NAMESPACE} --timeout=300s &
#failure_pid=$!
#
## Wait for either of the background jobs to finish by polling their process status
#while kill -0 $completion_pid >/dev/null 2>&1 && kill -0 $failure_pid >/dev/null 2>&1; do
#  sleep 2
#done
#
## Check the final status of the job and echo a message
#if kubectl get job ${JOB_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="SuccessCriteriaMet")].status}' | grep -q "True"; then
#  echo "✅ Job '${JOB_NAME}' completed successfully."
#else
#  echo "❌ Job '${JOB_NAME}' failed. Check logs for details. Prompting user to create token manually."
#  echo "Use 'crusoe monitoring tokens create' command to generate a new monitoringn token"
#  echo "Enter the crusoe monitoring token:"
#  read -s CRUSOE_MONITORING_TOKEN # -s for silent input (no echo)
#  echo "" # Add a newline after the silent input for better readability
#  # if required verify length of the token
#
#  # Create the 'crusoe-monitoring' secret in the '${NAMESPACE}' namespace. Using apply for idempotency.
#  kubectl create secret generic crusoe-monitoring --from-literal=CRUSOE_MONITORING_TOKEN="${CRUSOE_MONITORING_TOKEN}" -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
#fi
#
#echo "Cleaning up crusoe-monitoring-token-job."
#kubectl -n crusoe-system delete job/crusoe-monitoring-token-job

echo ""
echo "--------------------------------------------------------"
echo "---[ 3. Installing Crusoe Telemetry Agent (vector.dev) ]---"
echo "--------------------------------------------------------"

# Check for Helm installation
if ! command -v helm &> /dev/null; then
  echo "helm not found! Trying to install helm"
  echo "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  if ! command -v helm &> /dev/null; then
    echo "❌ Error: Unable to install 'helm'. Please install Helm before running this script."
    exit 1
  fi
fi
echo "✅ Helm is installed."

# Add and update the Vector Helm repository
echo "Adding and updating Vector Helm repository..."
helm repo add vector https://helm.vector.dev
helm repo update

# Conditional installation based on GPU_CLUSTER variable
if [ "${GPU_CLUSTER}" = "true" ]; then
  echo "Installing GPU telemetry agent..."
  helm install vector vector/vector \
    --namespace ${NAMESPACE} \
    --values https://raw.githubusercontent.com/crusoecloud/crusoe-telemetry-agent/refs/heads/main/kubernetes/cmk-gpu-telemetry-agent-values.yaml
else
  echo "Installing CPU telemetry agent..."
  helm install vector vector/vector \
    --namespace ${NAMESPACE} \
    --values https://raw.githubusercontent.com/crusoecloud/crusoe-telemetry-agent/refs/heads/main/kubernetes/cmk-cpu-telemetry-agent-values.yaml
fi

# Validate if the telemetry agent is running
echo "---[ 4. Validating telemetry agent installation ]---"
echo "Waiting for 'crusoe-telemetry-agent' pod to be ready in namespace '${NAMESPACE}'..."

# Use a timeout of 5 minutes (300 seconds) for the pods to become ready
if kubectl wait --for=condition=Ready pod --selector=app.kubernetes.io/instance=vector -n ${NAMESPACE} --timeout=600s > /dev/null; then
  echo "✅ Crusoe telemetry agent installed and running successfully."
else
  echo "❌ Crusoe telemetry agent failed to start. Check logs for details."
  exit 1
fi

echo "---[ Script finished successfully ]---"