#!/bin/bash

ant -DBASE_ISO_FILE=/home/triveni/docker-mount/ubuntu-24.04.03-desktop-amd64.iso \
    -DDRIVERS_DIR=/home/triveni/docker-mount/drivers_1.0.011_amd64.zip \
    -DSSMT_DEB_DIR=/home/triveni/docker-mount/mt \
    -DSSXM_DEB_DIR=/home/triveni/docker-mount/xm

