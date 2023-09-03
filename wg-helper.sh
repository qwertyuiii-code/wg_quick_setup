#!/bin/sh

OUT_CONFIG="wg0.conf"
BASE_CONFIG="wg0.conf.base"
CLIENT_IPS="client-addresses.txt"
EXE=`basename "$0"`
DEFAULT_IP='172.32.0.0/24'

show_help()
{
  echo "Usage: $EXE <COMMAND> [...]"
  echo ""
  echo "Available Commands:"
  echo "  gen-config        Generates the $OUT_CONFIG file"
  echo "  gen-server        Generates server key"
  echo "  add-client <NAME> Generates client key; It will be used on next gen-config"
  echo "  del-client <NAME> Removes client key"
  echo "  gen-client <NAME> Generates client config file"
}

if [ '(' "$1" == "-h" ')' -o '(' "$1" == '' ')' ]
then
  show_help
  exit
fi

#Some sanity checks

#If client-addresses.txt does not exist, create an empty one
if [ ! -f "$CLIENT_IPS" ]
then
  touch "$CLIENT_IPS"
fi

#If base config does not exist, exit
if [ ! -f "$BASE_CONFIG" ]
then
  echo "Error: Base configuration file '$BASE_CONFIG' does not exist"
  exit 1
fi

#Generate $OUT_CONFIG from client keys and $BASE_CONFIG
if [ "$1" == "gen-config" ]
then
  echo "Generating $OUT_CONFIG"

  #Add server private key
  PRIVATE_KEY=`cat server/server.key`
  cat "$BASE_CONFIG" | sed "s|##PRIVATE_KEY##|$PRIVATE_KEY|g" > "$OUT_CONFIG"
  echo "" >> "$OUT_CONFIG"

  #Add each client pub key and config
  for CLIENT_FILE in `find ./clients -iname '*.pub'`
  do
    CLIENT=`basename "$CLIENT_FILE" ".pub"`
    echo -ne "  - Adding client $CLIENT"
    CLIENT_PUBKEY=`cat "$CLIENT_FILE"`
    echo "#$CLIENT"                   >> "$OUT_CONFIG"
    echo "[peer]"                     >> "$OUT_CONFIG"
    echo "PublicKey = $CLIENT_PUBKEY" >> "$OUT_CONFIG"
    #If client is inside the $CLIENT_IPS file, add the allowedIps line
    CLIENT_ADDRESS=`grep -F "$CLIENT" -- "$CLIENT_IPS"`
    if [ "$CLIENT_ADDRESS" != "" ]
    then
      CLIENT_ADDRESS=`echo "$CLIENT_ADDRESS" | sed "s|:$CLIENT||"`
      echo -ne " (with address $CLIENT_ADDRESS)"
      echo "AllowedIPs = $CLIENT_ADDRESS" >> "$OUT_CONFIG"
    else
      echo "AllowedIPs = $DEFAULT_IP" >> "$OUT_CONFIG"
    fi
    echo "" >> "$OUT_CONFIG"
    echo ""
  done
  exit
fi

#Generate server keypair
if [ "$1" == "gen-server" ]
then
  #Make sure server keys don't exist already
  if [ -f 'server/server.key' ]
  then
    echo "server/server.key already exists, exitting!"
    echo "If you *really* want to overwrite the server key, delete it first."
    exit 1
  fi

  #Generate server.key and server.pub
  mkdir -p server
  wg genkey | tee server/server.key | wg pubkey > server/server.pub
  exit
fi

#Delete client keys
if [ "$1" == "del-client" ]
then
  CLIENT="$2"
  #There has to be a client argument
  if [ "$CLIENT" == "" ]
  then
    show_help
    echo "Error: Argument required"
    exit 1
  fi

  #Check client key exists
  if [ -f "clients/$CLIENT.key" ]
  then
    rm "clients/$CLIENT.key"
    rm "clients/$CLIENT.pub"
  else
    echo "Warning: client '$CLIENT' has no keys."
  fi
  exit
fi

#Generate a client key
if [ "$1" == "add-client" ]
then
  CLIENT="$2"
  #There has to be a client argument
  if [ "$CLIENT" == "" ]
  then
    show_help
    echo "Error: Argument required"
    exit 1
  fi

  #Make sure client key doesn't exist already
  if [ -f "clients/$CLIENT.key" ]
  then
    echo "client '$CLIENT' already has keys. To overwrite, delete client first with:"
    echo "    $EXE del-client '$CLIENT'"
    exit 1
  fi

  mkdir -p clients
  wg genkey | tee "clients/$CLIENT.key" | wg pubkey > "clients/$CLIENT.pub"
  exit
fi

#Generate a client config file
if [ "$1" == "gen-client" ]
then
  CLIENT="$2"
  #There has to be a client argument
  if [ "$CLIENT" == "" ]
  then
    show_help
    echo "Error: Argument required"
    exit 1
  fi

  #Check client key exists
  if [ -f "clients/$CLIENT.key" ]
  then
    CLIENT_KEY=`cat "clients/$CLIENT.key"`
  else
    echo "Warning: client '$CLIENT' has no keys."
  fi

  CLIENT_ADDRESS=`grep -F "$CLIENT" -- "$CLIENT_IPS"`
  if [ "$CLIENT_ADDRESS" != "" ]
  then
    CLIENT_ADDRESS=`echo "$CLIENT_ADDRESS" | sed "s|:$CLIENT||"`
  else
    echo "Warning: client '$CLIENT' has no set address."
  fi

  cat wg0-client.conf | sed "s|CLIENTPRIVATEKEY|$CLIENT_KEY|g" | sed "s|CLIENTADDRESS|$CLIENT_ADDRESS|" > "wg0-client-$CLIENT.conf"
  echo "Generated wg0-client-$CLIENT.conf"
  exit
fi
