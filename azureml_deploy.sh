#!/bin/bash
set -e 

# Set parameters

BASE_PATH=$PWD

# User Azure Workspace parameters
RESOURCE_GRP=isawicki-rg
WORKSPACE_NAME=octoml-gtm

# Model parameters
MODEL_NAME=resnet50_v2_7_onnx
TARBALL_NAME=resnet50_v2_7_onnx.tar.gz

# Azure Container Registry parameters
ACR_NAME=octomlgtm

# Azure ML Managed Endpoint parameters
ENDPOINT_NAME=octoml-triton-endpoint
DEPLOYMENT_NAME=octoml-model-dep-1
INSTANCE_TYPE=Standard_DS4_v2


# Helper function to replace variables in yaml files
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

# Helper function to cleanup resources
cleanup () {
    az ml online-endpoint delete -y -n $ENDPOINT_NAME
}

##### Create AzureML Online Endpoint #####
echo "Creating Azure ML Managed Endpoint ${ENDPOINT_NAME}"
endpoint_status="$(az ml online-endpoint list --query "[?name == \`${ENDPOINT_NAME}\`] | [0].provisioning_state" -o tsv)"  
echo $endpoint_status
# Create AzureML Online Endpoint
if [[ $endpoint_status == "Succeeded" ]]
then
  echo "Endpoint created successfully"
else
  echo "Creating endpoint ${ENDPOINT_NAME}"
  change_vars $BASE_PATH/endpoint.yaml
  cat $BASE_PATH/endpoint_.yaml_
  az ml online-endpoint create -f endpoint.yaml_
fi


##### END Create AzureML Online Endpoint #####


##### Inflate OctoML Optimized Model Artifact #####
echo "Inflating OctoML Triton Container image."
BASE_PATH=$PWD
TAR_TMP=$(mktemp -d)
tar -xzvf $BASE_PATH/docker/tarballs/$TARBALL_NAME --directory $TAR_TMP
cd $TAR_TMP
echo "Contents of tarball:"
ls -l
# Copy contents of /model to working directory to stage for deployment
cp -r docker_build_context/octoml/models/ $BASE_PATH

# Build OctoML Model Container
echo "Creating OctoML model-container deployment on Azure ML Managed Endpoint "
bash build.sh tmp_octo_img_name:latest

# Tag OctoML Model Container
MODEL_NAME_=$(echo "${MODEL_NAME}" | sed -e 's/-/_/g')
INSTANCE_TYPE_=$(echo "${INSTANCE_TYPE}" | sed -e 's/Standard_//g')
ACR_IMG_NAME="$ACR_NAME.azurecr.io/${MODEL_NAME_}:latest"

# Rebuilds container to include CMD to start Triton server.
docker build -t $ACR_IMG_NAME -f $BASE_PATH/docker/Dockerfile.wrap .
##### END Inflate OctoML Optimized Model Artifact #####


##### Push OctoML Model Container to ACR #####
# Log into ACR
echo "Logging into ACR"
az acr login --name $ACR_NAME

# Grant endpoint pull permission on the registry
echo "Checking/granting pull permissions for registry"

ENDPOINT_ID=$(az ml online-endpoint show --name $ENDPOINT_NAME --query "identity.principal_id" -o tsv)
REG_ID=$(az acr show --resource-group $RESOURCE_GRP --name $ACR_NAME --query id --output tsv)
az role assignment create --assignee $ENDPOINT_ID --role acrpull --scope $REG_ID 

# Push OctoML Model Container to ACR

echo "Pushing model container ${ACR_IMG_NAME}."
docker push $ACR_IMG_NAME
##### END Push OctoML Model Container to ACR #####


##### Create AzureML Deployment - deploys OctoML Triton Container & Optimized Model #####
# Update deployment.yaml file MODEL_NAME, ACR_NAME, and IMAGE_NAME
change_vars $BASE_PATH/deployment.yaml 
cat $BASE_PATH/deployment.yaml 


deploy_status=`az ml online-deployment show --name $DEPLOYMENT_NAME --endpoint $ENDPOINT_NAME --query "provisioning_state" -o tsv`
if [[ $deploy_status == "Succeeded" ]]
then
  echo "Deployment completed successfully"
else
  echo "Creating deployment ${DEPLOYMENT_NAME}"
  az ml online-deployment create -f $BASE_PATH/deployment.yaml_ --all-traffic
fi
##### END Create AzureML Deployment - deploys OctoML Triton Container & Optimized Model #####

scoring_uri=$(az ml online-endpoint show -n $ENDPOINT_NAME --query scoring_uri -o tsv)
scoring_uri=${scoring_uri%/*}
#KEY=$(az ml online-endpoint get-credentials -n $ENDPOINT_NAME --query primaryKey -o tsv)

echo "Scoring URI: $scoring_uri"
echo "Endpoint Name: $ENDPOINT_NAME"
echo "Deployment Name: $DEPLOYMENT_NAME"


