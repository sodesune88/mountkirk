#!/bin/sh

PROJECT_ID=$DEVSHELL_PROJECT_ID
ZONE=${ZONE-"asia-southeast1-a"}
REGION=${REGION-"asia-southeast1"}

TOPIC_ID=xonotic-topic
DATASET=xonotic_ds

alias gcloud='gcloud --quiet'

function destroy_telemetry() {
    JOBS=`gcloud dataflow jobs list --region=$REGION --format='value(JOB_ID)'`
    gcloud dataflow jobs cancel $JOBS --region=$REGION

    bq rm -r -f $DATASET

    gcloud logging sinks delete gkepubsub-sink --quiet

    gcloud pubsub topics delete $TOPIC_ID
}


function destroy_gameserver() {
    gcloud compute firewall-rules delete gcgs-xonotic-firewall

    gcloud game servers deployments update-rollout deployment-xonotic \
        --clear-default-config --no-dry-run

    for i in `gcloud game servers configs list --format='value(name)'`; do
        gcloud game servers configs delete $i --deployment deployment-xonotic
    done

    gcloud game servers deployments delete deployment-xonotic

    gcloud game servers clusters delete cluster-xonotic \
        --realm=realm-xonotic --no-dry-run --location=$REGION

    gcloud game servers realms delete realm-xonotic --location=$REGION

    gcloud container clusters delete gcgs-xonotic --zone=$ZONE
}


function destroy_buckets() {
    for bucket in `gsutil ls`; do
        gsutil -m rm -r $bucket
    done
}

destroy_telemetry
destroy_gameserver
destroy_buckets

echo
echo done. all resources removed.
