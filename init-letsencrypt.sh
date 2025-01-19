#!/bin/bash

# Stop execution if a command fails
set -e

domains=(reachero.com www.reachero.com)
rsa_key_size=4096
data_path="./certbot"
email="zacharyrcherney@gmail.com"

echo "### Stopping any running containers ..."
docker-compose down -v

echo "### Removing old certificates and directories ..."
sudo rm -rf "$data_path"

echo "### Creating directory structure ..."
mkdir -p "$data_path/www"
mkdir -p "$data_path/conf"

echo "### Downloading recommended TLS parameters ..."
curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"

echo "### Creating temporary self-signed certificate ..."
mkdir -p "$data_path/conf/live/reachero.com"
openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
  -keyout "$data_path/conf/live/reachero.com/privkey.pem" \
  -out "$data_path/conf/live/reachero.com/fullchain.pem" \
  -subj '/CN=localhost' 2>/dev/null

echo "### Starting nginx ..."
docker-compose up -d nginx
echo "### Waiting for nginx to start ..."
sleep 10

echo "### Deleting temporary certificate ..."
rm -rf "$data_path/conf/live"
mkdir -p "$data_path/conf/live"

echo "### Requesting Let's Encrypt certificate for ${domains[*]} ..."
docker-compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --email $email \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d reachero.com -d www.reachero.com" certbot

echo "### Reloading nginx ..."
docker-compose restart nginx

echo "### Done! Certificate should now be installed and nginx reloaded." 