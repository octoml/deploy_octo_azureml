#!/bin/bash


# Optional OctoML Download script
temp=$(mktemp -d) cd $temp

curl -k https://downloads.octoml.ai/octoml_macOS_v0.6.1.zip --output octoml_macOS_v0.6.1.zip
unzip octoml_macOS_v0.6.1.zip

cp octoml ~/.local/bin
octoml -V

# Download the Resnet50 Model
mkdir models && cd models
RESNET=https://github.com/onnx/models/raw/main/vision/classification/resnet/model/resnet50-v1-7.onnx
wget $RENSET 

# Alternative model, mnist
#MNIST=https://github.com/onnx/models/raw/main/vision/classification/mnist/model/mnist-8.onnx
#wget $MNIST


# Download conda & install Conda - optional
wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O ~/miniforge3.sh 
bash ~/miniforge3.sh
# Add conda to path
echo "export PATH=$PATH:$HOME/miniforge3/bin" >> $HOME/.bash_profile





