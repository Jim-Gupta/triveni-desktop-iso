if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root."
  exit 1
fi

mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.tmp!!
apt update -y
apt install -y python3-packaging python3-psutil xbase-clients xserver-xorg-video-dummy xvfb
wget -O /tmp/chrome-remote-desktop_current_amd64.deb https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
dpkg -i /tmp/chrome-remote-desktop_current_amd64.deb || apt -f install -y
#rm /tmp/chrome-remote-desktop_current_amd64.deb
mv /etc/apt/sources.list.d/ubuntu.tmp!! /etc/apt/sources.list.d/ubuntu.sources

