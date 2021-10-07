#!/bin/sh
# https://cloud.google.com/game-servers/docs/how-to/updating-rollout

# Prepare server config files

mkdir -p .tmp
FLEET_CONF=.tmp/xonotic_fleet_configs.yaml
SCALING_CONF=.tmp/xonotic_scaling_configs.yaml

DATE=`date +"%Y%m%d%H%M%S"`

cat <<EOF >$FLEET_CONF
- name: fleet-spec-$DATE
  fleetSpec:
    replicas: 2
    template:
      metadata:
        labels:
          xonotic-game-server-v1-label-key: xonotic-game-server-v1-label-$DATE
      spec:
        ports:
        - name: default
          containerPort: 26000
        template:
          spec:
            containers:
            - name: xonotic
              image: gcr.io/$DEVSHELL_PROJECT_ID/xonotic-demo
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

gcloud game servers configs create config-$DATE \
    --deployment deployment-xonotic \
    --fleet-configs-file $FLEET_CONF \
    --scaling-configs-file $SCALING_CONF


# Update the rollout deployment

gcloud game servers deployments update-rollout deployment-xonotic \
    --default-config config-$DATE --no-dry-run


# Wait for rollout. This will take a long time - due to drain + cordon

echo Waiting for rollout. This will take a long time ...
sleep 10s

while ! kubectl get gameserver | grep Ready; do
    echo "Waiting for gameserver to be ready (cordon + drain) ... Be patient."
    sleep 10
done

SERVER=`kubectl get gameserver | grep Ready | tr -s ' ' | cut -d' ' -f3-4 | tr ' ' ':'`
echo $SERVER > .info

echo
echo ">>> $0 done. Server avail @ $SERVER"
