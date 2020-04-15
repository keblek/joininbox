#!/bin/bash

sudo rm -rf /home/joinmarket/joininbox
sudo -u joinmarket git clone https://github.com/openoms/joininbox.git

sudo -u joinmarket cp ./joininbox/scripts/* /home/joinmarket/
sudo -u joinmarket cp ./joininbox/scripts/.* /home/joinmarket/ 2>/dev/null
sudo -u joinmarket chmod +x /home/joinmarket/*.sh

# bash autostart for joinmarket
echo "
# shortcut commands
source /home/joinmarket/_commands.sh
# automatically start main menu for joinmarket unless
# when running in a tmux session
if [ -f "/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate" ] ; then
 . /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate &&\
  cd /home/joinmarket/joinmarket-clientserver/scripts/
fi
if [ -z \"\$TMUX\" ]; then
  /home/joinmarket/menu.sh
fi
" | tee -a /home/joinmarket/.bashrc

# tor config
# add default value to joinin config if needed
checkTorEntry=$(cat /home/joinmarket/joinin.conf | grep -c "runBehindTor")
if [ ${checkTorEntry} -eq 0 ]; then
  echo "runBehindTor=off" >> /home/joinmarket/joinin.conf
fi
echo "
AllowOutboundLocalhost 1" | sudo tee -a /etc/tor/torsocks.conf
# setting value in joinin config
sed -i "s/^runBehindTor=.*/runBehindTor=on/g" /home/joinmarket/joinin.conf