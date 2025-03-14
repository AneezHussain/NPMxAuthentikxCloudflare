#!/bin/bash

# ===========================
#        AUTHENTIK SETUP
# ===========================

# Authentik API details
AUTHENTIK_INSTANCE="https://auth.company.com"
AUTHENTIK_API_TOKEN="YOUR_AUTHENTIK_API_TOKEN"

# Ask for the application name
read -p "Enter the application name: " APP_NAME

# ===========================
#        CLOUDFLARE SETUP
# ===========================

# Cloudflare API details
ACCOUNT_ID="YOUR_ACCOUNT_ID"
TUNNEL_ID="YOUR_TUNNEL_ID"
CLOUDFLARE_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN"
CLOUDFLARE_API="https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations"

# Ask for required inputs
read -p "Enter Domain Name(s) (comma-separated if multiple): " DOMAIN_NAMES

# Extract the first subdomain as slug
SLUG=$(echo "$DOMAIN_NAMES" | awk -F. '{print $1}')
echo "Using slug: $SLUG"

# Use the domain as the external host for Authentik
EXTERNAL_HOST="https://$DOMAIN_NAMES"

# Default Forward Host IP
DEFAULT_FORWARD_HOST="192.168.1.75"
read -p "Enter Forward Host (IP or domain, default: $DEFAULT_FORWARD_HOST): " FORWARD_HOST
FORWARD_HOST=${FORWARD_HOST:-$DEFAULT_FORWARD_HOST}

read -p "Enter Forward Port: " FORWARD_PORT

# Validate that port is provided
if [[ -z "$FORWARD_PORT" ]]; then
    echo "❌ Error: Forward Port is required."
    exit 1
fi

# Ask for Forward Scheme (default: http)
read -p "Enter Forward Scheme (http/https, default: http): " INPUT_SCHEME
FORWARD_SCHEME=${INPUT_SCHEME:-"http"}

# Set default values
CACHING_ENABLED="true"
BLOCK_EXPLOITS="true"
ALLOW_WEBSOCKET_UPGRADE="true"
HTTP2_SUPPORT="true"
SSL_FORCED="true"

# Debugging message before execution
echo "Executing proxy setup with:"
echo "  - Domain: $DOMAIN_NAMES"
echo "  - Forward Host: $FORWARD_HOST"
echo "  - Forward Port: $FORWARD_PORT"
echo "  - Forward Scheme: $FORWARD_SCHEME"

# Execute the CLI script and capture output
OUTPUT=$(./nginx_proxy_manager_cli.sh -d "$DOMAIN_NAMES" -i "$FORWARD_HOST" -p "$FORWARD_PORT" -f "$FORWARD_SCHEME" -c "$CACHING_ENABLED" -b "$BLOCK_EXPLOITS" -w "$ALLOW_WEBSOCKET_UPGRADE" -a "# Increase buffer size for large headers
# This is needed only if you get 'upstream sent too big header while reading response
# header from upstream' error when trying to access an application protected by goauthentik
proxy_buffers 8 16k;
proxy_buffer_size 32k;

location / {
    # Put your proxy_pass to your application here
    proxy_pass          $forward_scheme://$server:$port;

    # authentik-specific config
    auth_request        /outpost.goauthentik.io/auth/nginx;
    error_page          401 = @goauthentik_proxy_signin;
    auth_request_set $auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $auth_cookie;

    # translate headers from the outposts back to the actual upstream
    auth_request_set $authentik_username $upstream_http_x_authentik_username;
    auth_request_set $authentik_groups $upstream_http_x_authentik_groups;
    auth_request_set $authentik_email $upstream_http_x_authentik_email;
    auth_request_set $authentik_name $upstream_http_x_authentik_name;
    auth_request_set $authentik_uid $upstream_http_x_authentik_uid;

    proxy_set_header X-authentik-username $authentik_username;
    proxy_set_header X-authentik-groups $authentik_groups;
    proxy_set_header X-authentik-email $authentik_email;
    proxy_set_header X-authentik-name $authentik_name;
    proxy_set_header X-authentik-uid $authentik_uid;
}

# all requests to /outpost.goauthentik.io must be accessible without authentication
location /outpost.goauthentik.io {
    proxy_pass          http://192.168.1.75:7000/outpost.goauthentik.io;
    # ensure the host of this vserver matches your external URL you've configured
    # in authentik
    proxy_set_header    Host $host;
    proxy_set_header    X-Original-URL $scheme://$http_host$request_uri;
    add_header          Set-Cookie $auth_cookie;
    auth_request_set    $auth_cookie $upstream_http_set_cookie;

    # required for POST requests to work
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
}

# Special location for when the /auth endpoint returns a 401,
# redirect to the /start URL which initiates SSO
location @goauthentik_proxy_signin {
    internal;
    add_header Set-Cookie $auth_cookie;
    return 302 /outpost.goauthentik.io/start?rd=$request_uri;
    # For domain level, use the below error_page to redirect to your authentik server with the full redirect path
    # return 302 https://authentik.company/outpost.goauthentik.io/start?rd=$scheme://$http_host$request_uri;
}")

# Debug: Print output for checking
echo "Command Output:"
echo "$OUTPUT"

# Extract the ID of the created proxy
STRIPPED=$(echo "$OUTPUT" | sed 's/\x1B\[[0-9;]*[mK]//g')
HOST_ID=$(echo "$STRIPPED" | grep -oP 'ID: \K\d+')

# Check if a valid HOST_ID was found and is numeric
if [[ "$HOST_ID" =~ ^[0-9]+$ ]]; then
    echo "Enabling SSL for Host ID: $HOST_ID..."
    ./nginx_proxy_manager_cli.sh --host-ssl-enable "$HOST_ID" -y
    
    echo "✅ Proxy host setup complete with SSL enabled!"

    # Cloudflare Tunnel Part
    echo "Updating Cloudflare Tunnel..."

    # Fetch current config
    CURRENT_CONFIG=$(curl -s -X GET "$CLOUDFLARE_API" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result.config')

    # Ensure valid config
    if [[ "$CURRENT_CONFIG" == "null" || -z "$CURRENT_CONFIG" ]]; then
        CURRENT_CONFIG="{\"ingress\": [], \"warp-routing\": {\"enabled\": false}}"
    fi

    # Remove empty hostname rules
    CURRENT_CONFIG=$(echo "$CURRENT_CONFIG" | jq 'del(.ingress[] | select(.hostname == ""))')

    # Create Cloudflare Hostname
    NEW_INGRESS=$(echo '[
        {
            "hostname": "'"$DOMAIN_NAMES"'",
            "service": "https://192.168.1.75",
            "originRequest": {
                "originServerName": "'"$DOMAIN_NAMES"'"
            }
        }
    ]')

    # Merge old and new hostnames
    UPDATED_INGRESS=$(echo "$CURRENT_CONFIG" | jq --argjson new "$NEW_INGRESS" '.ingress += $new')
    UPDATED_INGRESS=$(echo "$UPDATED_INGRESS" | jq 'del(.ingress[] | select(.service == "http_status:404"))')
    UPDATED_INGRESS=$(echo "$UPDATED_INGRESS" | jq '.ingress += [{"service": "http_status:404"}]')

    # Update Tunnel Configuration
    RESPONSE=$(curl -s -X PUT "$CLOUDFLARE_API" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        --data "{
            \"account_id\": \"$ACCOUNT_ID\",
            \"config\": $UPDATED_INGRESS
        }")

    echo "$RESPONSE" | jq

    if echo "$RESPONSE" | jq -e '.success' | grep -q true; then
        echo "✅ Updated in Cloudflare!"
    else
        echo "❌ Failed to update Cloudflare Tunnel."
    fi
else
    echo "❌ Error: Could not extract a valid numeric Host ID. Please check the output above."
    exit 1
fi

# ===========================
#        AUTHENTIK SETUP
# ===========================

# Create a new proxy provider in Authentik
RESPONSE=$(curl -s -L "$AUTHENTIK_INSTANCE/api/v3/providers/proxy/" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -d "{
      \"name\": \"$APP_NAME\",
      \"authorization_flow\": \"57aa8bfd-86e7-4373-bf59-51277b6278c2\",
      \"invalidation_flow\": \"217e7961-cc54-41a8-b9cc-a2b42575d47b\",
      \"external_host\": \"$EXTERNAL_HOST\",
      \"mode\": \"forward_single\",
      \"access_token_validity\": \"hours=24\",
      \"refresh_token_validity\": \"hours=24\"
    }")

# Extract provider pk
PROVIDER_PK=$(echo "$RESPONSE" | jq -r '.pk')

# Validate provider creation
if [[ "$PROVIDER_PK" == "null" || -z "$PROVIDER_PK" ]]; then
    echo "❌ Error: Failed to retrieve provider number (pk)"
    exit 1
fi

echo "Provider created with pk: $PROVIDER_PK"

# Create an application using the extracted provider number
curl -L "$AUTHENTIK_INSTANCE/api/v3/core/applications/" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" \
    -d "{
      \"name\": \"$APP_NAME\",
      \"slug\": \"$SLUG\",
      \"provider\": $PROVIDER_PK
    }"

echo "✅ Application created successfully in Authentik!"
