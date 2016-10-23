# How-To-Use

## Build Static mesos-dns

``` shell
mkdir -p ${GOPATH}/src/github.com/mesosphere 
cd ${GOPATH}/src/github.com/mesosphere
git clone https://github.com/mesosphere/mesos-dns
docker run --rm -v ${GOPATH}:/golang -e CGO_ENABLED=0 -e GOOS=linux -e GOPATH=/golang -w ${PWD:17} golang go build
```

## Containerizd mesos-dns

```shell
cat <<EOF > mesos-dns.json
{
  "zk": "zk://127.0.0.1:2181/mesos",
  "refreshSeconds": 30,
  "ttl": 60,
  "domain": "mesos",
  "port": 61053,
  "resolvers": ["8.8.8.8", "8.8.4.4"],
  "timeout": 5,
  "listener": "0.0.0.0",
  "email": "root.mesos-dns.mesos",
  "IPSources": ["host", "netinfo"]
}
EOF

```

```Dockerfile
FROM scratch

ADD mesos-dns /usr/bin/mesos-dns
ADD mesos-dns.json /etc/mesos-dns/mesos-dns.json
ENTRYPOINT ["mesos-dns", "--config=/etc/mesos-dns/mesos-dns.json", "-logtostderr=true"]
```
docker build . -t mesos-dns:latest

## Run

docker run --rm mesos-dns:latest cat /etc/mesos-dns/mesos-dns.json > /dcos/mesos-dns/mesos-dns.json
Modify mesos-dns/mesos-dns.json
docker run -d --restart=always -v /dcos/mesos-dns/mesos-dns.json:/etc/mesos-dns/mesos-dns.json
