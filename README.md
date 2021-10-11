# Demo for Mountkirk Games

## tl;dr

Login to [GCP console](https://console.cloud.google.com), create a new project, launch cloud shell, then:

    git clone https://github.com/sodesune88/mountkirk
    cd mountkirk
    make

This setup [Google Cloud Game Servers](https://cloud.google.com/game-servers) using [Xonotic](https://xonotic.org/) as example.

It also setup telemetry: 
- GKE logs > cloud logging > pubsub > dataflow > bigquery

To simulate random headless xonotic clients connecting the gameserver:

    make simulation

To demo development (modify xonotic server.cfg in gcr.io):

    make dev

To clean up **(Caution: this also removes ALL storage resources, if exists earlier)**:

    make clean
    make veryclean (optional)

**Note: Many cloud shell commands used here will take a long time to complete. Please be patient!**

## Details

[Mountkirk Games](./assets/master_case_study_mountkirk_games.pdf) [as of Oct/2021] - One of case studies for Google PCA exam.

### GKE/ Agones/ GCGS

[Agones](https://agones.dev/site/) is an open source platform, for deploying, hosting, scaling, and orchestrating dedicated game servers for large scale multiplayer/ low-latency games. It is native to k8s. 

Specifically, it enables (see <https://www.fairwinds.com/blog/hands-on-with-agones-google-cloud-game-servers>):

- Management of gameservers (pods, in k8s parlance) life cycle - ensure they will not be drained/ killed (eg autoscale down) during game play.
- DynamicPort allocation - mitigates the possibility of ports exhaustion due to frequent start/ stop of gameservers (a typical mulitplayer game session lasts a few minutes up to hours).

[Google Cloud Game Servers](https://cloud.google.com/game-servers) fully manages Agones. It makes gameservers deployment in a **multi-clusters** environment a breeze. For eg, when new k8s cluster is added to a [realm](https://cloud.google.com/game-servers/docs/concepts/overview#realm), a new fleet (deployment, in k8s parlance) will be automatically deployed to the new cluster.

For overview of cloud game infrastructure, see [here](https://cloud.google.com/architecture/cloud-game-infrastructure).

```bash
make
```

This creates GCGS using Xonotic as example. See <https://cloud.google.com/architecture/deploying-xonotic-game-servers>

### Game analytics/ telemetry 

The above also setup gaming analytics telemetry as described [here](https://cloud.google.com/architecture/mobile-gaming-analysis-telemetry). Real-time events from xonotic server is captured by cloud logging (aka stackdriver logging), then > pubsub > dataflow > bigquery.

[stackdriverdataflowbigquery.py](./stackdriverdataflowbigquery.py) (adapted from: [here](https://github.com/GoogleCloudPlatform/dialogflow-log-parser-dataflow-bigquery/blob/master/stackdriverdataflowbigquery.py)) illustrates how dataflow job is used to filter + transform:

```python
def myfilter(d):
    try:
        return d['logName'].endswith('/logs/stdout') \
                and 'connected\u001b[m' in d['textPayload'] \
                and not d['textPayload'].startswith('[BOT]')
    except:
        pass
    return False

def mytransform(d):
    retval = {
        'insertId'      : None,
        'timestamp'     : None,
        'player'        : None, # cl_name
        'action'        : None, # connected/ disconnected
        'textPayload'   : None,
    }

    try:
        retval['insertId'] = d['insertId']
        retval['timestamp'] = d['timestamp']
        retval['textPayload'] = d['textPayload']

        player, text = d['textPayload'].split('\u001b', 1)
        retval['player'] = player
        retval['action'] = 'disconnected' if 'disconnected' in text else 'connected'
    except:
        pass

    return retval
```

### Testing w/ local xonotic client (optional)

```bash
make fw MY_CIDR=<my-public-ip-address>/32
```

This setup firewall rule to allow connection from your local xonotic client to gameserver.

```bash
make info
```

This shows the ip:port of gameserver. Then proceed to [download xonotic](https://xonotic.org/download/) client.

Linux (terminal):

```bash
cd path/to/xonotic
./xonotic-linux-sdl.sh +connect <server-ip:port> +_cl_name player123

```

Windows (command prompt - *untested*):
```bash
cd path\to\xonotic
xonotic.exe +connect <server-ip:port> +_cl_name player123
```

(Optional parameters: `+vid_fullscreen 0 +vid_width 1024 +vid_height 768 +mastervolume 0`)

### Simulation

```bash
make simulation
```

This generates 15 random *headless* xonotic clients connecting/ disconnecting to gameserver in 5 mins. Each client session lasts 20-30s randomly. Xvfb is used to enable headless execution in cloud shell.

Cloud shell currenly provides ~ 8 GB mem; each xonotic client requires ~1 GB mem.

[Accordingly](https://wenku.baidu.com/view/68f1853a580216fc700afd74.html), we expect:

- Ave concurrency (C) ~= 15*25/300 = 1.25
- Max concurrency (3 sigma CI) ~= C + 3 * sqrt(C) = 4.6

To play with different values:

```bash
make simulation NUM_PLAYERS=xx DURATION=yyy
```

The data takes *a few minutes* to show up in bigquery (only for initial run). Data studio can be further used to plot connection timeseries graph.

### Dev/ CD-CI

See [here](https://cloud.google.com/architecture/continuous-delivery-jenkins-kubernetes-engine) for k8s using Jenkins.

```bash
make dev
```

Here we just modify xonotic's [server.cfg](./dev/server.cfg). In [dev/build_image.sh](./dev/build_image.sh):

```bash
message="follow da Amit - `date +'%Y%m%d %H:%M:%S'`"
...
sed -i "s/^sv_motd.*/sv_motd \"$message\"/" server.cfg
gcloud builds submit --tag $image_tag .
```

[dev/Dockerfile](./dev/Dockerfile) (adapted from: [here](https://github.com/googleforgames/agones/blob/release-1.17.0/examples/xonotic/Dockerfile)):

```docker
FROM debian:stretch

RUN useradd -u 1000 -m xonotic
WORKDIR /home/xonotic

COPY Xonotic Xonotic
COPY wrapper wrapper
COPY server.cfg .xonotic/data/server.cfg

RUN rm -rf Xonotic/{xonotic-linux64-glx,xonotic-linux64-sdl,xonotic-linux-glx.sh,xonotic-linux-sdl.sh,.xonotic-*,data/xonotic-20170401-music.pk3}

RUN chown -R xonotic:xonotic .


USER 1000
ENTRYPOINT /home/xonotic/wrapper -i /home/xonotic/Xonotic/server_linux.sh
```

Upon completion, new **server ip:port** will be allocated. Launch your local xonotic client, and you should see something like:
<br>
<br>

![new image motd](./res/new-image-motd.png)

*(Note: for unknown reason/s related to xonotic, you may need to launch xonotic client a couple of times...)*

# Other discussions

## Load balancer

Unlike regular GKE, whereby **all** external traffic is routed thru LB, Agones exposes the gameservers/pods **directly**. To list gameservers in a cluster for their public ip:port, run `kubectl get gameserver`.

Agones provides [agones-allocator service](https://cloud.google.com/game-servers/docs/how-to/configuring-multicluster-allocation) that functions like a load balancer: 

1. client connects to it (https port);
2. the allocator replies with a gameserver (pod) ip:port that is **Ready** (within the same realm), using round robin manner;
3. the client then proceed to connect with the gameserver **directly** (in xonotic case, the client-server comm is actually udp).

A RESTful example is described [here](https://agones.dev/site/docs/advanced/allocator-service/#using-rest).

Agones/GCGS introduces [realm](https://cloud.google.com/game-servers/docs/concepts/overview#realm) for latency considerations. A realm represents a group of clusters (from regions/zones) whereby latency differencies are small - eg US, Japan, Europe. So players from within the same realm get connected to gameservers (of clusters) inside the same realm and play against one another.

## Availablility/ Failover/ Disaster recovery

GKEs and Cloud Spanner (for real-time global leaderboard) are inherently high-available. 

To improves availabilty, regional GKE ([SLA](https://cloud.google.com/kubernetes-engine/sla) 99.95%) can be used so that control planes are replicated across zones. 

A regional/ multi-regional Spanner has [SLA](https://cloud.google.com/spanner) of 99.999% with database replicated across zones/regions respectively.

Currently GCGS is in EAP/alpha/beta so no SLA (<https://cloud.google.com/game-servers/sla>).

The game analytics/ telemetry is not operationally critical so provision of FO/DR may not be neccessary ("cost management is the next most important challenge"). 

However, if desired it can be proposed that a "standby" telemetry pipeline be set up in blue-green deployment manner. At regular interval, say every 10s, a specially crafted "health-check" message is published via pubsub and we expect it to land in bigquery. And if that fails by certain threshold, the cloud logging sink is then switched over to the standby pubsub/ pipeline.

# Other refs

- <https://www.youtube.com/watch?v=pHE3rKku8jw>
- <https://www.youtube.com/watch?v=L_-1-8c3qrw>
- <https://www.youtube.com/watch?v=1w1olPjlPZY>

# License

Apache License, Version 2.0 (for respective module/s from Google, Inc.)
