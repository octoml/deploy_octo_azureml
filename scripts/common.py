def preprocess_a(img_file=TEST_IMG):
    img = Image.open(img_file).resize((224, 224))
    img_data = asarray(img)
    img_data = np.rollaxis(img_data,2,0)
    imagenet_mean = np.array([0.485, 0.456, 0.406])
    imagenet_stddev = np.array([0.229, 0.224, 0.225])
    norm_img_data = np.zeros(img_data.shape).astype("float32")
    for i in range(img_data.shape[0]):
      norm_img_data[i, :, :] = (img_data[i, :, :] / 255 - imagenet_mean[i]) / imagenet_stddev[i]
    x = np.expand_dims(img_data, axis=0)
    return(x)

def preprocess_b(img_file=TEST_IMG):
    img = Image.open(img_file).resize((224, 224))
    img_data = asarray(img)
    img_data = np.rollaxis(img_data,2,0)
    #imagenet_mean = np.array([0.485, 0.456, 0.406])
    #imagenet_stddev = np.array([0.229, 0.224, 0.225])
    #norm_img_data = np.zeros(img_data.shape).astype("float32")
    #for i in range(img_data.shape[0]):
    #  norm_img_data[i, :, :] = (img_data[i, :, :] / 255 - imagenet_mean[i]) / imagenet_stddev[i]
    x = np.expand_dims(img_data, axis=0)
    return(x)