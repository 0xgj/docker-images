#/bin/bash 

set -x
docker run --rm -it --net=host -v $PWD/dcos:/dcos \
-e RESOLVER=10.132.46.83 \
-e MESOS=leader.mesos:5050 \
-e MARATHON=master.mesos:8080 \
-e DCOS_HISTORY_SERVICE=10.132.46.83:15055 \
-e MESOS_DNS=master.mesos:8123 \
-e EXHIBITOR=10.132.46.83:8181 \
-e COSMOS=10.132.46.83:7070 \
-e AUTH=10.132.46.83:8101 \
-e DDDT=10.132.46.83:1050 \
-e KEYSTONE=master.mesos:35357 \
-e REGISTRY=10.132.46.86:9090 \
-e TASC=10.132.46.83:9092 \
-e LOGS=10.132.46.84:9200 \
-e ALERT=10.132.46.80:9093 \
-e MONITOR=10.132.46.80:9090 \
dcos/adminrouter
