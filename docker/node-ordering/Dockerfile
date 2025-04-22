FROM  python:3.10.10-bullseye

COPY ./node_ordering.py /
COPY ./entrypoint.sh /

RUN pip3 install pssh parallel-ssh
RUN chmod +x /entrypoint.sh /node_ordering.py

RUN apt-get -qq update && apt-get install openssh-server dnsutils -y --allow-change-held-packages --no-install-recommends \
&& rm -rf /var/lib/apt/lists/*

RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd -p

ENTRYPOINT ["/entrypoint.sh"]