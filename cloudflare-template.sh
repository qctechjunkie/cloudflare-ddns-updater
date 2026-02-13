#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                 # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
record_name=""                                      # Which record you want to be synced
ttl=3600                                            # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"

###########################################
## Logging function
###########################################
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger -s "DDNS Updater: [$timestamp] [$level] [$record_name] $message"
}

###########################################
## Slack notification function (Block Kit)
###########################################
send_slack_notification() {
    local status="$1"    # "success" or "failure"
    local title="$2"
    local message="$3"
    local old_ip="$4"
    local new_ip="$5"
    
    [[ -z "$slackuri" ]] && return
    
    local emoji=":white_check_mark:"
    [[ "$status" == "failure" ]] && emoji=":x:"
    
    # Format domain as a clickable link
    local domain_link="<https://${record_name}|${record_name}>"
    
    # Build the blocks JSON
    local blocks='[
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'"$emoji $sitename - $title"'",
                "emoji": true
            }
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Domain:*\n'"$domain_link"'"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Status:*\n'"$status"'"
                }
            ]
        }'
    
    # Add IP information if provided
    if [[ -n "$old_ip" ]] && [[ -n "$new_ip" ]]; then
        blocks="$blocks"',
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Previous IP:*\n`'"$old_ip"'`"
                },
                {
                    "type": "mrkdwn",
                    "text": "*New IP:*\n`'"$new_ip"'`"
                }
            ]
        }'
    elif [[ -n "$new_ip" ]]; then
        blocks="$blocks"',
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*IP Address:*\n`'"$new_ip"'`"
                }
            ]
        }'
    fi
    
    # Add message if provided
    if [[ -n "$message" ]]; then
        blocks="$blocks"',
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "'"$message"'"
            }
        }'
    fi
    
    # Add context footer
    blocks="$blocks"',
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "Cloudflare DDNS Updater | '"$(date '+%Y-%m-%d %H:%M:%S %Z')"'"
                }
            ]
        }
    ]'
    
    # Send to Slack
    curl -s -X POST "$slackuri" \
        -H "Content-Type: application/json" \
        --data "{\"blocks\": $blocks}" > /dev/null 2>&1
}

###########################################
## Discord notification function
###########################################
send_discord_notification() {
    local status="$1"
    local title="$2"
    local message="$3"
    local old_ip="$4"
    local new_ip="$5"
    
    [[ -z "$discorduri" ]] && return
    
    local color=3066993  # Green
    [[ "$status" == "failure" ]] && color=15158332  # Red
    
    local fields='[
        {"name": "Domain", "value": "`'"$record_name"'`", "inline": true},
        {"name": "Status", "value": "'"$status"'", "inline": true}
    ]'
    
    if [[ -n "$old_ip" ]] && [[ -n "$new_ip" ]]; then
        fields='[
            {"name": "Domain", "value": "`'"$record_name"'`", "inline": true},
            {"name": "Status", "value": "'"$status"'", "inline": true},
            {"name": "Previous IP", "value": "`'"$old_ip"'`", "inline": true},
            {"name": "New IP", "value": "`'"$new_ip"'`", "inline": true}
        ]'
    fi
    
    curl -s -H "Content-Type: application/json" -X POST \
        --data '{
            "embeds": [{
                "title": "'"$sitename - $title"'",
                "description": "'"$message"'",
                "color": '"$color"',
                "fields": '"$fields"',
                "footer": {"text": "Cloudflare DDNS Updater"},
                "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
            }]
        }' "$discorduri" > /dev/null 2>&1
}

###########################################
## Combined notification function
###########################################
send_notification() {
    local status="$1"
    local title="$2"
    local message="$3"
    local old_ip="${4:-}"
    local new_ip="${5:-}"
    
    send_slack_notification "$status" "$title" "$message" "$old_ip" "$new_ip"
    send_discord_notification "$status" "$title" "$message" "$old_ip" "$new_ip"
}

###########################################
## Check if we have a public IP
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'

log "INFO" "Check initiated"

ip=$(curl -s -4 --max-time 10 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]] || [[ -z "$ip" ]]; then
    log "WARN" "Cloudflare IP lookup failed, trying fallbacks"
    ip=$(curl -s --max-time 10 https://api.ipify.org)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --max-time 10 https://ipv4.icanhazip.com)
    fi
else
    ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
fi

if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
    log "ERROR" "Failed to find a valid IP. Got: '$ip'"
    send_notification "failure" "IP Detection Failed" "Could not determine public IP address"
    exit 2
fi

log "INFO" "Current public IP: $ip"

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
else
    auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################
record=$(curl -s --max-time 10 -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

###########################################
## Validate API response
###########################################
if [[ $record == *"\"success\":false"* ]]; then
    log "ERROR" "API query failed: $record"
    send_notification "failure" "API Error" "Failed to query DNS records from Cloudflare"
    exit 1
fi

if [[ $record == *"\"count\":0"* ]]; then
    log "ERROR" "Record does not exist. Create one first: $ip for $record_name"
    send_notification "failure" "Record Not Found" "No A record exists for this domain" "" "$ip"
    exit 1
fi

###########################################
## Extract old IP and record identifier
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

# Validate extracted values
if [[ ! $old_ip =~ ^$ipv4_regex$ ]]; then
    log "ERROR" "Failed to extract valid old IP. Got: '$old_ip'"
    log "ERROR" "API Response: $record"
    send_notification "failure" "Parse Error" "Could not extract current IP from Cloudflare response"
    exit 1
fi

if [[ -z "$record_identifier" ]] || [[ "$record_identifier" == "$record" ]]; then
    log "ERROR" "Failed to extract record identifier"
    log "ERROR" "API Response: $record"
    send_notification "failure" "Parse Error" "Could not extract record ID from Cloudflare response"
    exit 1
fi

log "INFO" "Cloudflare IP: $old_ip | Record ID: $record_identifier"

###########################################
## Compare IPs
###########################################
if [[ $ip == $old_ip ]]; then
    # No logging for routine checks - exit silently
    exit 0
fi

# Only log from this point forward (when changes occur)
log "INFO" "IP change detected: $old_ip -> $ip"

###########################################
## Update the DNS record
###########################################
update=$(curl -s --max-time 10 -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":${proxy}}")

###########################################
## Report the status
###########################################
if [[ $update == *"\"success\":true"* ]]; then
    log "SUCCESS" "DNS updated: $old_ip -> $ip"
    send_notification "success" "DNS Updated" "IP address has been updated successfully" "$old_ip" "$ip"
    exit 0
else
    log "ERROR" "DNS update failed: $update"
    send_notification "failure" "Update Failed" "Failed to update DNS record" "$old_ip" "$ip"
    exit 1
fi