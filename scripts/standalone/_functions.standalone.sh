#!/bin/bash

function addUserStore() {
  echo "# Adding the user: store"
  sudo adduser --disabled-password --gecos "" store
  sudo -u store mkdir /home/store/app-data
}

function moveSignetData() {
  if [ -f /etc/systemd/system/signetd.service ];then
    sudo systemctl stop signetd
    sudo mv /home/joinmarket/.bitcoin /home/store/app-data/
    sudo ln -s /home/store/app-data/.bitcoin /home/bitcoin/
    sudo systemctl start signetd
  fi
}

function makeEncryptedFolder(){
  # make encrypted file

  # mount to /mnt/encrypted/
  
  # move all from app-data
  sudo mv /home/store/app-data /mnt/encrypted/
  # symlink
  sudo ln -s /mnt/encrypted/app-data /home/store/
}

function downloadSnapShot() {
  echo "# Paste the link to the latest shapshot from https://prunednode.today:"
  echo "# For example:"
  echo "https://prunednode.today/snapshot210224.zip"
  read downloadLink
  sudo -u joinmarket mkdir /home/joinmarket/download 2>/dev/null
  cd /home/joinmarket/download || exit 1 
  downloadFileName=$(echo $downloadLink | awk 'BEGIN{FS="/"} {print $NF}')
  noExt=$(echo $downloadLink | cut -d"." -f1-2)
  hashExt=".signed.txt"
  hashLink=$(echo $noExt$hashExt)
  hashFileName=$(echo $hashLink | awk 'BEGIN{FS="/"} {print $NF}')
  
  if [ ! -f $hashFileName ];then
    echo
    echo "# downloading the signed sha256sum from:"
    echo "# $hashLink"
    echo
    wget $hashLink || exit 1
  fi
  
  echo "# Import the PGP keys of Stepan Snigirev"
  curl https://stepansnigirev.com/ss-specter-release.asc | gpg --import || exit 1
  
  if [ ! -f $downloadFileName ];then
    echo
    echo "# Downloading $downloadLink ..."
    echo
    wget $downloadLink
  fi
  echo "# Verifying the signature of the hash ..."
  verifyResult=$(gpg --verify $hashFileName 2>&1)
  goodSignature=$(echo ${verifyResult} | grep -c 'Good signature')
  echo "# goodSignature (${goodSignature})"
  echo "# Verifying the hash (takes time) ..."
  verifyHash=$(sha256sum -c $hashFileName 2>&1)
  goodHash=$(echo ${verifyHash} | grep -c OK)
  echo "# verifyHash ($verifyHash)"
  if [ ${goodSignature} -lt 1 ] || [ ${goodHash} -lt 1 ]; then
    echo
    echo "# Download failed --> PGP Verify not OK / signature(${goodSignature})"
    echo "# Removing the downloaded files"
    rm -f $hashFileName
    rm -f $downloadFileName
    exit 1
  else
    echo
    echo "# The PGP signature and the hash of the downloaded snapshot is correct"
  fi
  echo "# Exract and copy to /home/store/app-data/.bitcoin"
  addUserStore
  sudo mkdir -p /home/store/app-data/.bitcoin
  if [ -f /home/bitcoin/.bitcoin/bitcoin.conf ];then
    echo "# Back up bitcoin.conf"
    sudo -u bitcoin mv /home/bitcoin/.bitcoin/bitcoin.conf \
    /home/bitcoin/.bitcoin/bitcoin.conf.backup
  fi
  sudo unzip -o $downloadFileName -d /home/store/app-data/.bitcoin
  if [ -f /home/bitcoin/.bitcoin/bitcoin.conf.backup ];then
    echo "# Restore bitcoin.conf"
    sudo -u bitcoin mv /home/bitcoin/.bitcoin/bitcoin.conf.backup \
    /home/bitcoin/.bitcoin/bitcoin.conf
  fi
  echo "# Making sure user: bitcoin exists"
  sudo adduser --disabled-password --gecos "" bitcoin
  sudo chown -R bitcoin:bitcoin /home/store/app-data/.bitcoin
}

function installBitcoinCoreStandalone() {
  source /home/joinmarket/_functions.bitcoincore.sh
  downloadBitcoinCore

  if [ -f /home/bitcoin/bitcoin/bitcoind ];then
    installedVersion=$(/home/bitcoin/bitcoin/bitcoind --version | grep version)
    echo "${installedVersion} is already installed"
  else
    echo "# Adding the user: bitcoin"
    sudo adduser --disabled-password --gecos "" bitcoin
    echo "# Installing Bitcoin Core v${bitcoinVersion}"
    sudo -u bitcoin tar -xvf ${binaryName}
    sudo -u bitcoin mkdir -p /home/bitcoin/bitcoin
    sudo install -m 0755 -o root -g root -t /home/bitcoin/bitcoin bitcoin-${bitcoinVersion}/bin/*  
  fi

  installed=$(/home/bitcoin/bitcoin/bitcoind --version | grep "${bitcoinVersion}" -c)
  if [ ${installed} -lt 1 ]; then
    echo
    echo "!!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
    exit 1
  fi

  # bitcoin.conf
  if [ -f /home/store/app-data/.bitcoin/bitcoin.conf ];then
    if [ $(grep -c rpcpassword < /home/store/app-data/.bitcoin/bitcoin.conf) -eq 0 ];then
      sudo rm /home/store/app-data/.bitcoin/bitcoin.conf
    fi
  fi
  # not a symlink, delete
  sudo rm -rf /home/bitcoin/.bitcoin
  #echo "# moving to /home/store/app-data/"
  #sudo mv /home/joinmarket/.bitcoin /home/store/app-data/
  echo "# symlink to /home/bitcoin/"
  sudo ln -s /home/store/app-data/.bitcoin /home/bitcoin/
  if [ ! -f /home/bitcoin/.bitcoin/bitcoin.conf ];then
    sudo -u bitcoin mkdir -p /home/bitcoin/.bitcoin
    randomRPCpass=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c20)
    cat > /home/joinmarket/bitcoin.conf <<EOF
# bitcoind configuration

# Connection settings
rpcuser=joininbox
rpcpassword=$randomRPCpass

prune=1000
server=1
fallbackfee=0.0002

onlynet=onion
proxy=127.0.0.1:9050
EOF
    sudo mv /home/joinmarket/bitcoin.conf /home/bitcoin/.bitcoin/bitcoin.conf 
  else
    echo "# /home/bitcoin/.bitcoin/bitcoin.conf is present"
  fi
  sudo chown -R bitcoin:bitcoin /home/store/app-data/.bitcoin
  sudo chown -R bitcoin:bitcoin /home/bitcoin/
}

function installMainnet() {
  source /home/joinmarket/_functions.bitcoincore.sh
  removeSignetdService
  sudo systemctl stop bitcoind
  # /etc/systemd/system/bitcoind.service
  echo "
[Unit]
Description=Bitcoin daemon on mainnet
[Service]
User=bitcoin
Group=bitcoin
Type=forking
PIDFile=/home/bitcoin/bitcoin/bitcoind.pid
ExecStart=/home/bitcoin/bitcoin/bitcoind -daemon \
-pid=/home/bitcoin/bitcoin/bitcoind.pid
KillMode=process
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/bitcoind.service
  sudo systemctl daemon-reload
  sudo systemctl enable bitcoind
  echo "# OK - the bitcoind.service is now enabled"

  # add aliases
  if [ $(alias | grep -c bitcoin) -eq 0 ];then 
    alias bitcoin-cli="sudo -u bitcoin /home/bitcoin/bitcoin/bitcoin-cli"
    alias bitcoind="sudo -u bitcoin /home/bitcoin/bitcoin/bitcoind"
    sudo bash -c "echo 'alias bitcoin-cli=\"sudo -u bitcoin /home/bitcoin/bitcoin/bitcoin-cli\"' >> /home/joinmarket/_commands.sh"
    sudo bash -c "echo 'alias bitcoind=\"sudo -u bitcoin /home/bitcoin/bitcoin/bitcoind\"' >> /home/joinmarket/_commands.sh"
  fi

  sudo systemctl start bitcoind
  echo
  echo "# Installed $(/home/bitcoin/bitcoin/bitcoind --version | grep version)"
  echo 
  echo "# Monitor the bitcoind with: sudo tail -f /home/bitcoin/.bitcoin/mainnet/debug.log"
  echo

  if [ ! -f /home/bitcoin/.bitcoin/mainnet/wallets/wallet.dat/wallet.dat ];then
    echo "# Create wallet.dat ..."
    sleep 10
    sudo -u bitcoin /home/bitcoin/bitcoin/bitcoin-cli createwallet wallet.dat
  fi
}
