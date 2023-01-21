#!/bin/bash
set -e 

# Set parameters

BASE_PATH=$PWD
ENDPOINT_NAME=octoml-triton-endpoint
MODEL_NAME=resnet50-v1-12
TARBALL_NAME=resnet50_v2_7_onnx.tar.gz
ACR_NAME=octomlgtm
RESOURCE_ID=isawicki-rg
#ACR_IMG_NAME="${ACR_NAME}.azurecr.io/${MODEL_NAME}:latest"
ACR_IMG_NAME="octomlgtm.azurecr.io/resnet50_d16_v5:latest"

change_vars() {
  for FILE in "$@"; do 
    TMP="${FILE}_"
    cp $FILE $TMP 
    readarray -t VARS < <(cat $TMP | grep -oP '{{.*?}}' | sed -e 's/[}{]//g'); 
    for VAR in "${VARS[@]}"; do
      sed -i "s#{{${VAR}}}#${!VAR}#g" $TMP
    done
  done
}

# Defines helper functions
cleanup () {
    az ml online-endpoint delete -y -n $ENDPOINT_NAME
}

# Install Python requirements
#pip3 install numpy
#pip3 install tritonclient[http,grpc]
#pip3 install pillow
#pip3 install gevent


##### Create AzureML Online Endpoint #####
echo "Creating Azure ML Managed Endpoint ${ENDPOINT_NAME}"
endpoint_status=`az ml online-endpoint show --name $ENDPOINT_NAME --query "provisioning_state" -o tsv`
echo $endpoint_status

# Create AzureML Online Endpoint
if [[ ${endpoint_status} == "Succeeded" ]]
then
  echo "Endpoint created successfully"
else
  echo "No endpoint exists. Creating now."
  az ml online-endpoint create --name $ENDPOINT_NAME -f endpoint.yaml
fi

##### END Create AzureML Online Endpoint #####


##### Inflate OctoML Optimized Model Artifact #####
echo "Inflating OctoML Triton Container image."
BASE_PATH=$PWD
TAR_TMP=$(mktemp -d)
tar -xzvf $BASE_PATH/tarballs/$TARBALL_NAME --directory $TAR_TMP
cd $TAR_TMP
echo "Contents of tarball:"
ls -l
# Copy contents of /model to working directory to stage for deployment
cp -r docker_build_context/octoml/models/ $BASE_PATH

# Build OctoML Model Container
echo "Creating OctoML model-container deployment on Azure ML Managed Endpoint "
bash build.sh tmp_octo_img_name:latest
# Rebuilds container to include CMD to start Triton server.
docker build -t $ACR_IMG_NAME -f $BASE_PATH/Dockerfile.wrap .
##### END Inflate OctoML Optimized Model Artifact #####


##### Push OctoML Model Container to ACR #####
# Log into ACR
echo "Logging into ACR"
az acr login --name $ACR_NAME

# Grant endpoint pull permission on the registry
echo "Checking/granting pull permissions for registry"

ENDPOINT_ID=$(az ml online-endpoint show --name $ENDPOINT_NAME --query "identity.principal_id" -o tsv)
REG_ID=$(az acr show --resource-group $RESOURCE_ID --name $ACR_NAME --query id --output tsv)
az role assignment create --assignee $ENDPOINT_ID --role acrpull --scope $REG_ID 

# Push OctoML Model Container to ACR
echo "Pushing model container ${ACR_IMG_NAME}."
docker push $ACR_IMG_NAME
##### END Push OctoML Model Container to ACR #####


##### Create AzureML Deployment - deploys OctoML Triton Container & Optimized Model #####
# Update deployment.yaml file MODEL_NAME, ACR_NAME, and IMAGE_NAME
change_vars $BASE_PATH/deployment.yaml 
cat $BASE_PATH/deployment.yaml 

az ml online-deployment create -f $BASE_PATH/deployment.yaml_ --all-traffic
deploy_status=`az ml online-deployment show --name octo-buildflagchg-1 --endpoint $ENDPOINT_NAME --query "provisioning_state" -o tsv`
echo $deploy_status
if [[ $deploy_status == "Succeeded" ]]
then
  echo "Deployment completed successfully"
else
  echo "Deployment failed"
  exit 1
fi
##### Create AzureML Deployment - deploys OctoML Triton Container & Optimized Model #####


scoring_uri=$(az ml online-endpoint show -n $ENDPOINT_NAME --query scoring_uri -o tsv)
scoring_uri=${scoring_uri%/*}
KEY=$(az ml online-endpoint get-credentials -n $ENDPOINT_NAME --query primaryKey -o tsv)




