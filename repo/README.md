## 
**Notes**
- repo.tgz : this is a tar zipped file that contains all the debians and packge manifest for latest security updates for a XM, MT or Combo system
- create_repo.sh : creates the repo.tgz.  This script will update sources.list (to ubuntu repository) and dist-upgrade on the system
- install_repo.sh : installs repo.tgz.  This script will update sources.list (to local repository) and dist-upgrade on the system
##

**Creating repo.tgz**
- use XM, MT or COMBO ISO from Jenkins and install it on some VM.  This is the REPO system
- This system must be connected to the internet
- upload create_repo.sh to the REPO system
    - scp create_repos.sh triveni@host_ip:/home/triveni/Downloads
- ssh to that system and run create_repo.sh as root
    - sudo create_repo.sh
- create_repo.sh will create a file called repo.tgz.  
- download repo.tgz
    - scp triveni@host_ip:/home/triveni/Downloads/repo.tgz
##

**Installing repo.tgz**
- upload repo.tgz to the system to upgrade debians
    - scp repo.tgz triveni@host_ip:/home/triveni/Downloads
- upload install_repo.sh to the system to upgrade
    - scp install_repo.sh triveni@host_ip:/home/triveni/Downloads
- make sure install_repo.sh & repo.tgz are in the same directory
- ssh to that system execute the install_repo.sh as root (sudo ./install.repo.sh)
##