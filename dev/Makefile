export image_tag := gcr.io/$(DEVSHELL_PROJECT_ID)/xonotic-demo

all:
	./build_image.sh

# check if hosted on Google Cloud Registry
check:
	gcloud container images describe $(image_tag)

# output the tag for this image
tag:
	@echo $(image_tag)

.PHONY: build check tag
