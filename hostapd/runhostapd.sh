#!/bin/sh

wlanif=wlan0
wlanip=10.1.1.4
wlansubnet=10.1.1.0
wlanmask=24

# Waiting 10 seconds for wlan interface to come up / be transfered to container namespace

counter=0
until [ -e "/sys/class/net/$wlanif" ] || [ $counter -eq 10 ]; do
  sleep 1
  echo "Waiting for interface '$wlanif' to become available... $((counter++))"
done

if [ ! -e "/sys/class/net/$wlanif" ]; then
  echo "Giving up. Make sure interface has been set to namespace of container"
  exit 1
fi

cat > /etc/hostapd/hostapd.conf << '__EOF__'
bridge=br0
interface=wlan0
driver=nl80211
ssid=Deep Space One
hw_mode=g
channel=7
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=test1234
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
__EOF__

get_pid() {
	hostapdPid=$(ps auxw | grep /hostapd | grep -v grep | awk '{print $1}')
}

echo "Creating bridge br0"
brctl addbr br0

echo "Adding eth0 to bridge br0"
brctl addif br0 eth0

echo "Enabling spanning tree protocol"
brctl stp br0 on

echo "Adding ip to wlan interface"
ip addr add $wlanip/$wlanmask dev $wlanif

echo "Setting wlan interface to up"
ip link set dev $wlanif up

echo "Starting hostapd"
# Sending hostapd to background with & is not appropiate because we must not continue
# before hostapd has set up the wlan interface
/usr/sbin/hostapd -d -B /etc/hostapd/hostapd.conf

get_pid
echo "Pid of hostapd: $hostapdPid"

echo "Adding ip to bridge br0"
ip addr add 10.1.1.9/24 dev br0

echo "Setting br0 to up"
ip link set dev br0 up

echo "Flushing all routes"
ip route flush all

echo "Adding route for br0"
ip route add 10.1.1.0/24 dev br0

echo "Adding default route via 10.1.1.10"
ip route add default via 10.1.1.10

term_handler() { 
	echo "Got SIGTERM"
	kill -TERM $sleep_pid
}
trap term_handler SIGTERM

sleep 2147483647 &
sleep_pid=$!
wait $sleep_pid

echo "kill -SIGTERM $hostapdPid"
kill -SIGTERM $hostapdPid

while : ; do
	get_pid
        [[ ! -z $hostapdPid ]] || break
        echo "Waiting for hostapd to stop"
        sleep 1
done

brctl stp br0 off

echo "Removing eth0 from br0"
brctl delif br0 eth0

echo "Setting br0 to down"
ip link set dev br0 down

brctl show

echo "Removing br0"
brctl delbr br0
