@echo off
REM This script is used to build the Docker image and run the container that will create the custom ISO as a convience on Windows.
REM It assumes you have Docker Desktop installed and running on your machine.
REM This will use the same Dockerfile as is used on Jenkins and mount in a similar way as the Jenkinsfile

REM Make sure to start Docker Desktop before running this script.

REM ==========================================
REM Define Variables
REM ==========================================
SET IMAGE_NAME=ss-noble-iso:latest

REM Host Paths
REM The HOST_MOUNT_DIR will be mounted to the container at /mnt/userContent.  It should contain the ISO, the .deb files and the repo.tgz 
REM file. The container can reference these files and are set in the Environment Variables below.
REM For example: D:\Triveni\iso\docker-mount\ubuntu-24.04-desktop-amd64.iso will map to /mnt/userContent/ubuntu-24.04-desktop-amd64.iso in the container and this is referenced by the CONT_BASE_ISO env variable below.
SET HOST_MOUNT_DIR=D:\Triveni\iso\docker-mount
SET HOST_WORKSPACE_DIR=%CD%


REM Container Environment Variables
SET CONT_BASE_ISO=/mnt/userContent/ubuntu-24.04-desktop-amd64.iso
SET CONT_DRIVERS_DIR=/mnt/userContent/triveni-drivers
SET CONT_SSMT_DIR=/mnt/userContent/mt
SET CONT_SSXM_DIR=/mnt/userContent/xm
REM ==========================================

REM Build from Dockerfile
docker build -f Dockerfile -t %IMAGE_NAME% .


REM Run with env variables passed to container and invoke ant
docker run --rm ^
  -v "%HOST_MOUNT_DIR%:/mnt/userContent" ^
  -v "%HOST_WORKSPACE_DIR%:/workspace" ^
  -e BASE_ISO_FILE=%CONT_BASE_ISO% ^
  -e DRIVERS_DIR=%CONT_DRIVERS_DIR% ^
  -e SSMT_DEB_DIR=%CONT_SSMT_DIR% ^
  -e SSXM_DEB_DIR=%CONT_SSXM_DIR% ^
  %IMAGE_NAME% ^
  sh -c "ant -DBASE_ISO_FILE=$BASE_ISO_FILE -DDRIVERS_DIR=$DRIVERS_DIR -DSSMT_DEB_DIR=$SSMT_DEB_DIR -DSSXM_DEB_DIR=$SSXM_DEB_DIR"

REM powershell.exe -ExecutionPolicy Bypass -File ".\test_iso_in_virtualbox.ps1"
