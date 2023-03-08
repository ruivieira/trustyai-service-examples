# Basic k8s deployment

## Using KinD

Install [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation).

Create a directory for the persisten volumes (can be called anything, but if changing this, please make a notes of the value and change it too on `kind/config.yaml`):

```shell
$ mkdir /tmp/pv
```

Start a test cluster with:

```shell
$ kind create cluster --image=kindest/node:v1.22.15 --config ./kind/config.yaml
$ kubectl cluster-info --context kind-kind
```

Create a namespace:

```shell
$ kubectl create namespace modelmesh-serving
```

## Install modelmesh

### From the payload processing PR

Start by cloning ModelMesh:

```shell
$ cd /tmp
$ git clone git@github.com:kserve/modelmesh.git
$ cd modelmesh
$ git fetch origin pull/84/head:84
$ git checkout 84
```

Change the payload processor endpoint. In `src/src/main/java/com/ibm/watson/modelmesh/ModelMesh.java`, Change `payloadProcessorsDefinitions` to:

```java
 private PayloadProcessor initPayloadProcessor() {
    // Start change
        String payloadProcessorsDefinitions = "http://trustyai-service.modelmesh-serving/consumer/kserve/v2";
    // End change
        if (payloadProcessorsDefinitions != null && payloadProcessorsDefinitions.length() > 0) {
            List<PayloadProcessor> payloadProcessors = new ArrayList<>();
```

Now we can build the ModelMesh image (use whatever tag you want, but make it consistent since you'll need it later):

```shell
$ mvn clean install -DskipTests
$ docker build . -t $YOUR_QUAY_REPO/modelmesh:0.1.0
$ export TAG_LATEST=f"quay.io/$YOUR_QUAY_REPO/modelmesh:0.1.0"
$ docker tag ruimvieira/modelmesh:0.1.0 $TAG_LATEST
$ docker push $TAG_LATEST
```

Now we need ModelMesh serving:

```shell
$ cd /tmp
$ git clone git@github.com:kserve/modelmesh-serving.git
```

We need ModelMesh serving to point at the image you just built.
Edit `/tmp/modelmesh-serving/config/default/config-defaults.yaml` to change to the following:

```yaml
podsPerRuntime: 2
headlessService: true
modelMeshImage:
  name: quay.io/$YOUR_QUAY_REPO/modelmesh
  tag: 0.1.0
```

You can now deploy ModelMesh:

```shell
$ cd /tmp/modelmesh-serving
$ ./scripts/install.sh --namespace-scope-mode --namespace modelmesh-serving --quickstart
```

Once ModelMesh is deployed, you can deploy a test model (note that the paths are now relative to this project):

```shell
$ kubectl apply -f ./k8s/model.yaml
```

### Service

You _don't_ need to wait for the models to deploy and can now start the service deployment:

```shell
$ export NAMESPACE="modelmesh-serving"
$ kubectl apply -f k8s/storage.yaml -n $NAMESPACE
$ kubectl apply -f k8s/trustyai-configmap.yaml -n $NAMESPACE
$ kubectl apply -f k8s/trustyai-deployment.yaml -n $NAMESPACE
```

### Requests

When the service and models are deployed (check with `kubectl get pods -A`), forward the ports so you can access them:

```shell
$ kubectl port-forward --address 0.0.0.0 service/modelmesh-serving 8008 -n $NAMESPACE &
$ kubectl port-forward --address 0.0.0.0 service/modelmesh-serving 8033 -n $NAMESPACE &

```

You can now try some HTTP requests:

```shell
$ curl -X POST -k http://localhost:8008/v2/models/example-sklearn-isvc/infer -H "Content-Type: application/json" -d @./data/payload.json
```

You should now see the ModelMesh logs sending the payloads and the service receiving them.