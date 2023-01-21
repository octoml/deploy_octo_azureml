#!/bin/bash
set -e 

# Set parameters

BASE_PATH=$PWD
ENDPOINT_NAME=octoml-triton-endpoint
MODEL_NAME=resnet50-v1-7
ACR_NAME=octomlgtm
RESOURCE_ID=isawicki-rg
ACR_IMG_NAME="${ACR_NAME}.azurecr.io/${MODEL_NAME}:latest"

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
pip3 install numpy
pip3 install tritonclient[http,grpc]
pip3 install pillow
pip3 install gevent


# Deploy container to Azure ML Managed Endpoint
echo "Creating Azure ML Managed Endpoint ${ENDPOINT_NAME}"
az ml online-endpoint create --name $ENDPOINT_NAME -f endpoint.yaml
endpoint_status=`az ml online-endpoint show --name $ENDPOINT_NAME --query "provisioning_state" -o tsv`
echo $endpoint_status

# Create AzureML Online Endpoint
if [[ ${endpoint_status} == "Succeeded" ]]
then
  echo "Endpoint created successfully"
else
  echo "Endpoint creation failed"
  exit 1
fi

##### Inflate OctoML Optimized Model Artifact #####
echo "Inflating OctoML Triton Container image."
tar -xzvf $BASE_PATH/resnet50-v1-7.tar.gz -

exit 

# Copy contents of /model to working directory to stage for deployment
OCTOML_OCTOMIZED_MODEL_PATH=$BASE_PATH/local_models/.octoml_cache/deploy/*/external/
echo "$OCTOML_OCTOMIZED_MODEL_PATH"

# Un-tar docker tarball delivered by CLI
tar -xzvf $OCTOML_OCTOMIZED_MODEL_PATH/docker.tar.gz
echo "Copying OctoML optimized model to /models"
cp -r $OCTOML_OCTOMIZED_MODEL_PATH/* $PWD/

echo "Creating OctoML model-container deployment on Azure ML Managed Endpoint "

# Push Local Image to ACR
echo "Logging into ACR"
az acr login --name $ACR_NAME

# Grant endpoint pull permission on the registry
echo "Checking/granting pull permissions for registry"

ENDPOINT_ID=$(az ml online-endpoint show --name $ENDPOINT_NAME --query "identity.principal_id" -o tsv)
REG_ID=$(az acr show --resource-group $RESOURCE_ID --name $ACR_NAME --query id --output tsv)
az role assignment create --assignee $ENDPOINT_ID --role acrpull --scope $REG_ID 

# Re-tag Local Image for Deploymentt Octoml Image
ACR_IMG_NAME="${ACR_NAME}.azurecr.io/${MODEL_NAME}:latest"

echo "Pushing model container ${ACR_IMG_NAME}."
echo $ACR_IMG_NAME
docker tag $MODEL_NAME-local $ACR_IMG_NAME
docker push $ACR_IMG_NAME

# Update deployment.yaml file MODEL_NAME, ACR_NAME, and IMAGE_NAME
change_vars $BASE_PATH/deployment.yaml 
cat $BASE_PATH/deployment.yaml 

# Create AzureML Deployment - deploys OctoML Triton Container & Optimized Model
az ml online-deployment create -f $BASE_PATH/deployment.yaml_ --all-traffic
deploy_status=`az ml online-deployment show --name $REPOLACE --endpoint $ENDPOINT_NAME --query "provisioning_state" -o tsv`
echo $deploy_status
if [[ $deploy_status == "Succeeded" ]]
then
  echo "Deployment completed successfully"
else
  echo "Deployment failed"
  exit 1
fi

scoring_uri=$(az ml online-endpoint show -n $ENDPOINT_NAME --query scoring_uri -o tsv)
scoring_uri=${scoring_uri%/*}
KEY=$(az ml online-endpoint get-credentials -n $ENDPOINT_NAME --query primaryKey -o tsv)




