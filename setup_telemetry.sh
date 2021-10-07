#!/bin/sh

PROJECT_ID=$DEVSHELL_PROJECT_ID
TOPIC_ID=xonotic-topic

BUCKET=$PROJECT_ID-gcgs-demo
DATASET=xonotic_ds
TABLE=xonotic_tbl

cat <<EOF
*******************************************************************
**
** Setting up Telemetry for GKE > Pub/Sub > Dataflow > BigQuery ...
**
*******************************************************************
EOF

alias gcloud='gcloud --quiet'

# Enable APIs
# https://developers.google.com/apis-explorer

gcloud services enable \
    stackdriver.googleapis.com \
    dataflow.googleapis.com


# Create pubsub topic

gcloud pubsub topics create $TOPIC_ID


# Create logging sink to pubsub (filter k8s container logs)

gcloud logging sinks create gkepubsub-sink \
    pubsub.googleapis.com/projects/$PROJECT_ID/topics/$TOPIC_ID \
    --log-filter='resource.type="k8s_container"'


# Add to the service account permissions to publish to pubsub.

SA_FULL_NAME=`gcloud logging sinks describe gkepubsub-sink --format='value(writerIdentity)'`

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member $SA_FULL_NAME \
    --role "roles/pubsub.publisher"


# Create gs temp storage & bq dataset

gsutil mb -l $REGION gs://$BUCKET
bq mk --location=$REGION --dataset $DATASET


# dataflow api takes a while to be effective ...
echo sleep 2m to stabilize ...
sleep 2m


# Setup dataflow

if [ ! -f tempenv/bin/activate ]; then  
    python3 -m virtualenv tempenv
    source tempenv/bin/activate
    pip install apache-beam[gcp] -q
else
    source tempenv/bin/activate
fi

python3 stackdriverdataflowbigquery.py --project=$PROJECT_ID \
    --input_topic=projects/$PROJECT_ID/topics/$TOPIC_ID \
    --runner=DataflowRunner --temp_location=gs://$BUCKET/tmp \
    --output_bigquery=$DATASET.$TABLE --region=$REGION

deactivate


echo
echo ">>> $0 done."
