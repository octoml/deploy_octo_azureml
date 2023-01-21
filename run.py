import argparse
import numpy as np
import os
from PIL import Image

import requests
import gevent.ssl
import tritonclient.http as tritonhttpclient
from numpy import asarray
from matplotlib import pyplot as plt
from scipy.special import softmax

BASE_PATH = os.path.dirname(os.path.abspath(__file__))
TEST_IMG = BASE_PATH + "/assets/cat.png"
LABELS_PATH = BASE_PATH  + "/assets/"
ENDPOINT_NAME="octoml-triton-endpoint"


# Downloads a list of imagenet labels
#labels_url = "https://s3.amazonaws.com/onnx-model-zoo/synset.txt"
#os.popen('echo Downloading labels from {}...'.format(labels_url))
#labeler = os.popen(f'cd assets && wget {labels_url}')

with open(LABELS_PATH+"synset.txt", "r") as f:
    labels = [l.rstrip() for l in f]
    
# Get Azure ML Endpoint Scoring URI and Key
scoring_uri_long = os.popen('az ml online-endpoint show -n octoml-triton-endpoint --query scoring_uri -o tsv').read()
scoring_uri_long = scoring_uri_long.strip('\n')
scoring_uri = scoring_uri_long[8:]

key = os.popen(f'az ml online-endpoint get-credentials -n {ENDPOINT_NAME} --query primaryKey -o tsv').read()
key = key.strip('\n')


triton_client = tritonhttpclient.InferenceServerClient(
    url=scoring_uri,
    ssl=True,
    ssl_context_factory=gevent.ssl._create_default_https_context,
)
headers = {}
token = key
headers["Authorization"] = f"Bearer {token}"

def preprocess(img_content=TEST_IMG):
    """Pre-process an image to meet the size, type and format
    requirements specified by the parameters.
    """
    c = 3
    h = 224
    w = 224

    img = Image.open(img_content)

    sample_img = img.convert("RGB")

    resized_img = sample_img.resize((w, h), Image.BILINEAR)
    resized = np.array(resized_img)
    if resized.ndim == 2:
        resized = resized[:, :, np.newaxis]

    typed = resized.astype(np.float32)

    # scale for INCEPTION
    scaled = (typed / 128) - 1

    # Swap to CHW
    ordered = np.transpose(scaled, (2, 0, 1))

    # Channels are in RGB order. Currently model configuration data
    # doesn't provide any information as to other channel orderings
    # (like BGR) so we just assume RGB.
    img_array = np.array(ordered, dtype=np.float32)[None, ...]

    return img_array

# Helper function to preprocess image
def predict_model_1(data):
    # Get model metadata to reflect the input and output scheme
    type_mape = {"FP32": np.float32, "INT32": np.int32, "INT64": np.int64}
    model_meta=triton_client.get_model_metadata(model_name, "1", headers)
    input_name_0 = model_meta['inputs'][0]['name']
    input_shape_0 = model_meta['inputs'][0]['shape']
    input_shape_0[0] = 1
    input_datatype_0 = model_meta['inputs'][0]['datatype']
    output_name_0 = model_meta['outputs'][0]['name']
    output_datatype_0 = model_meta['outputs'][0]['datatype']
    print(model_meta)
    # Populate inputs and outputs
    input = tritonhttpclient.InferInput(input_name_0, input_shape_0, input_datatype_0)
    input.set_data_from_numpy(data)
    inputs = [input]
    result = triton_client.infer(model_name, inputs, headers=headers)
    result = result.as_numpy(output_name_0)
    max_label = np.argmax(result)
    return(max_label,result)

def postprocess(predictions):
    scores = softmax(predictions)
    scores = np.squeeze(scores)
    ranks = np.argsort(scores)[::-1]
    for rank in ranks[0:5]:
            print("class='%s' with probability=%f" % (labels[rank], scores[rank]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--local", action='store_true', help="Check if local container is running and inference is possible.")
    parser.add_argument("--remote", action='store_true', help="Call remote Triton Inference Server on AZ hosted endpoint.")
    parser.add_argument("--scoring-uri", action='store_true', help="Endpoing scoring URL.")
    parser.add_argument("--key", action='store_true', help="Endpoint key.")
    parser.add_argument("-model-name", type=str, default="resnet50_v1_12", help="Model name.")
    args = parser.parse_args()
    
    if args.local:
        
        model_1  = requests.post("http://localhost:8000/v2/repository/index").json()[0]
        model_1_name = model_1['name']
        model_1_stats = requests.get(f"http://localhost:8000/v2/models/{model_1_name}/stats").json()
        
        print(model_1)
        print("Local container is running and ready for inference.")
        
    if args.scoring_uri:
        print(scoring_uri)
        
    if args.key:
        print(key)
        
    if args.remote:       
        #Check status of Triton Inferencing Server
        health_ctx = triton_client.is_server_ready(headers=headers)
        print("Is server ready - {}".format(health_ctx))
        
        # Check status of model
        model_name = args.model_name
        status_ctx = triton_client.is_model_ready(model_name, "1", headers)
        print("Is model ready - {}".format(status_ctx))
               
        # Preprocess image data
        img_data = preprocess(TEST_IMG) # outputs np.float32 array

        # Run inference
        rank_1, ranks = predict_model_1(img_data)

        # Postprocess results
        postprocess(ranks)
        