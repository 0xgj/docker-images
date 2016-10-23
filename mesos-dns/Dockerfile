FROM scratch

ADD mesos-dns /usr/bin/mesos-dns
ADD mesos-dns.json /etc/mesos-dns/mesos-dns.json
ENTRYPOINT ["mesos-dns", "--config=/etc/mesos-dns/mesos-dns.json", "-logtostderr=true"]
