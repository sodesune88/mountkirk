# Firewall source ranges for gameserver to allow connection from.
# GCE based resources (cloudshell, colab, gke etc) have ip ranges started with 34/35.
SOURCE_RANGES := 34.0.0.0/8,35.0.0.0/8

ifneq ($(MY_CIDR),)
SOURCE_RANGES := $(SOURCE_RANGES),$(MY_CIDR)
endif

export SOURCE_RANGES
export ZONE ?= asia-southeast1-a
export REGION ?= asia-southeast1
export TIMEZONE ?= Asia/Singapore

##################################################################

all: gameserver telemetry
.PHONY: log info clean simulation dev

# setup agones/gameserver/gke
gameserver:
	./setup_gameserver.sh
	@touch $@

# setup stackdriver-logging/pubsub/dataflow/bigquery
telemetry:
	./setup_telemetry.sh
	@touch $@

# simulation of random [headless] xonotic players/clients
# NUM_PLAYERS - total number of players (default 15)
# DURATION    - duration for the simulation (in seconds) (default 300)
# note: cloud shell provides ~8 gb memory; each headless client ~0.8 - 1 gb
NUM_PLAYERS = 15
DURATION = 300
simulation: gameserver telemetry dev/Xonotic
	(if ! which Xvfb >/dev/null; then sudo apt install -y xvfb >/dev/null 2>&1; fi; \
	 SERVER=`cat .info`; \
	 cd simulation && python3 run.py -s $$SERVER --headless)

# To demo development (modify gameserver config file in docker)
dev: gameserver dev/Xonotic
	$(MAKE) -C $@
	./update_rollout.sh

#----------------------------------

# To allow connection from your local xonotic client to gameserver, 
# make fw MY_CIDR=<ip-address>/32
fw:
	gcloud compute firewall-rules update gcgs-xonotic-firewall --quiet \
        --source-ranges $(SOURCE_RANGES)

# To stream server log in cloud shell
log:
	@(FLEET=`kubectl get pods -o json | jq -r .items[0].metadata.name`; \
	  kubectl logs $$FLEET xonotic -f | tee server.log)

# To show gamerserver's ip:port - kubectl get gameserver
info:
	kubectl get gameserver -o json | jq -r '.items[].status | select(.state == "Ready") | "\(.address):\(.ports[0].port)"'

xonotic-0.8.2.zip:
	@echo "Downloading xonotic files..."
	curl -LO https://dl.xonotic.org/$@

dev/Xonotic: xonotic-0.8.2.zip
	@(cd dev && \
		unzip -q ../$^ && \
		cd Xonotic && \
		rm -rf bin32 COPYING Docs gmqcc GPL-2 GPL-3 key_0.d0pk Makefile misc source Xonotic.app xonotic-dedicated.exe xonotic.exe xonotic-linux32-dedicated xonotic-linux32-glx xonotic-linux32-sdl xonotic-linux-dedicated.sh xonotic-osx-dedicated xonotic-wgl.exe xonotic-x86-dedicated.exe xonotic-x86.exe xonotic-x86-wgl.exe && \
		cp server/server_linux.sh .)

# purge all resources
clean:
	rm -rf gameserver telemetry dev/Xonotic/.xonotic*
	@./clean.sh

veryclean:
	rm -rf .tmp .info tempenv xonotic-*.zip
	sudo apt purge xvfb -y
	sudo apt autoremove -y
	gcloud services disable --quiet \
		gameservices.googleapis.com \
		container.googleapis.com \
		stackdriver.googleapis.com \
		cloudbuild.googleapis.com
	# following only removable after 30 days of inactivity...
	# gcloud services disable --quiet \
	#	dataflow.googleapis.com \
	#	compute.googleapis.com
