#!/bin/sh

message="follow da Amit - `date +'%Y%m%d %H:%M:%S'`"
image_tag=${image_tag-gcr.io/$DEVSHELL_PROJECT_ID/xonotic-demo}

cat <<EOF
*************************************************
**
** Updating gameserver's xonotic image ...
**
*************************************************
EOF

gcloud --quiet services enable cloudbuild.googleapis.com


# Enable cloudbuild to write to storage...

SA=`gcloud projects get-iam-policy $DEVSHELL_PROJECT_ID \
    | grep @cloudbuild \
    | head -1 \
    | cut -d: -f2`

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member serviceAccount:$SA \
    --role roles/viewer

sed -i "s/^sv_motd.*/sv_motd \"$message\"/" server.cfg

gcloud builds submit --tag $image_tag .
