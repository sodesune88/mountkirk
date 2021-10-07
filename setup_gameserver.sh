#!/bin/sh
#
# Refs:
# https://cloud.google.com/game-servers/docs/quickstart
# https://cloud.google.com/architecture/deploying-xonotic-game-servers
# https://cloud.google.com/architecture/running-dedicated-game-servers-in-kubernetes-engine
# https://agones.dev/site/docs/getting-started/edit-first-gameserver-go/
#
# Note: Fleet <==> Deployment/ReplicaSet); GameServer <==> Pod
###########################################################################################

# Do NOT change the settings here - adjust in Makefile

ZONE=${ZONE-"asia-southeast1-a"}
REGION=${REGION-"asia-southeast1"}
TIMEZONE=${TIMEZONE-"Asia/Singapore"}
SOURCE_RANGES=${SOURCE_RANGES-"0.0.0.0/0"}

cat <<EOF
*************************************************
**
** Setting up Agones/ Google Game Server/ GKE ...
**
*************************************************
EOF

alias gcloud='gcloud --quiet'

gcloud config set compute/zone $ZONE


# Enable APIs
# https://developers.google.com/apis-explorer

gcloud services enable \
    compute.googleapis.com \
    container.googleapis.com \
    gameservices.googleapis.com


# Create firewall rule to open the UDP ports 7000‑8000 for the cluster

gcloud compute firewall-rules create gcgs-xonotic-firewall \
    --source-ranges $SOURCE_RANGES \
    --allow udp:7000-8000 \
    --target-tags game-server


# Create a cluster with two nodes

gcloud container clusters create gcgs-xonotic \
    --cluster-version=1.19 \
    --tags=game-server \
    --scopes=gke-default \
    --num-nodes=2 \
    --no-enable-autoupgrade \
    --machine-type=e2-standard-2 \
    --zone=$ZONE


# GKE credendtials, as usual

gcloud container clusters get-credentials gcgs-xonotic --zone=$ZONE


# Create namespace agones-system

kubectl create namespace agones-system


# Install agones on the cluster

kubectl apply -f https://raw.githubusercontent.com/googleforgames/agones/release-1.16.0/install/yaml/install.yaml


# Wait for Agones controller to be ready

while true; do
    echo Waiting for agones-controller to be ready...
    sleep 8
    if kubectl get pods --namespace agones-system | grep agones-controller -q; then
        break
    fi
done


# Create a realm in the same region as cluster.
# You may create a realm for each area of the world players are in.

gcloud game servers realms create realm-xonotic --time-zone $TIMEZONE --location $REGION
sleep 30s


# Register GKE cluster with Game Servers and attach it to the realm

gcloud game servers clusters create cluster-xonotic \
    --realm=realm-xonotic \
    --gke-cluster locations/$ZONE/clusters/gcgs-xonotic \
    --namespace=default \
    --location $REGION \
    --no-dry-run


# Create a Game Servers deployment to store server configurations

gcloud game servers deployments create deployment-xonotic


# Prepare server config files

mkdir -p .tmp
FLEET_CONF=.tmp/xonotic_fleet_configs.yaml
SCALING_CONF=.tmp/xonotic_scaling_configs.yaml

cat <<EOF >$FLEET_CONF
- name: fleet-spec-1
  fleetSpec:
    replicas: 2
    template:
      metadata:
        labels:
          xonotic-game-server-v1-label-key: xonotic-game-server-v1-label-1
      spec:
        ports:
        - name: default
          containerPort: 26000
        template:
          spec:
            containers:
            - name: xonotic
              image: gcr.io/agones-images/xonotic-example:0.8
EOF

cat <<EOF >$SCALING_CONF
  - fleetAutoscalerSpec:
      policy:
        type: Buffer
        buffer:
          bufferSize: 1
          maxReplicas: 4
    name:
      scaling-config-1
EOF


# Create the Game Servers configuration

gcloud game servers configs create config-1 \
    --deployment deployment-xonotic \
    --fleet-configs-file $FLEET_CONF \
    --scaling-configs-file $SCALING_CONF


# Update the rollout deployment

gcloud game servers deployments update-rollout deployment-xonotic \
    --default-config config-1 --no-dry-run


# Wait for gameserver to be ready

while true; do
    echo Waiting for gameserver to be ready...
    sleep 8
    IP=`kubectl get gameserver -o json | jq -r .items[0].status.address`
    [ "$IP" != "null" ] && break
done

PORT=`kubectl get gameserver -o json | jq -r .items[0].status.ports[0].port`
SERVER=$IP:$PORT
echo $SERVER > .info


echo
echo ">>> $0 done. Server avail @ $SERVER"
