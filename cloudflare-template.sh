#!/bin/bash
## change to "bin/sh" when necessary

###########################################
## Configuration
###########################################
readonly AUTH_EMAIL=""                                    # The email used to login 'https://dash.cloudflare.com'
readonly AUTH_METHOD=""                                   # Set to "global" for Global API Key or "token" for Scoped API Token
readonly AUTH_KEY=""                                      # Your API Token or Global API Key
readonly ZONE_IDENTIFIER=""                               # Can be found in the "Overview" tab of your domain
readonly RECORD_NAME=""                                   # Which record you want to be synced
readonly TTL=3600                                         # Set the DNS TTL (seconds)
readonly PROXY="true"                                     # Set the proxy to true or false
readonly SITENAME=""                                      # Title of site "Example Site"
readonly SLACK_URI=""                                     # URI for Slack WebHook
readonly DISCORD_URI=""                                   # URI for Discord WebHook
readonly CHECK_INTERVAL=60                                # Seconds between IP checks when running as a service
readonly MAX_RETRIES=3                                    # Number of attempts before sending a failure alert
readonly RETRY_DELAY=30                                   # Seconds to wait between retry attempts
readonly DNS_SERVER="1.1.1.1"                            # DNS server for curl lookups (bypasses forced local DNS e.g. AdGuard Home). Leave empty to use system default.

readonly ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'

# Build optional DNS flag array (requires curl >= 7.86.0)
DNS_ARGS=()
[[ -n "$DNS_SERVER" ]] && DNS_ARGS=(--dns-servers "$DNS_SERVER")

###########################################
## Logging function
###########################################
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger -s "DDNS Updater: [$timestamp] [$level] [$RECORD_NAME] $message"
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

    [[ -z "$SLACK_URI" ]] && return

    local emoji=":white_check_mark:"
    [[ "$status" == "failure" ]] && emoji=":x:"

    # Format domain as a clickable link
    local domain_link="<https://${RECORD_NAME}|${RECORD_NAME}>"

    # Build the blocks JSON
    local blocks='[
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'"$emoji $SITENAME - $title"'",
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
    curl -s "${DNS_ARGS[@]}" -X POST "$SLACK_URI" \
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

    [[ -z "$DISCORD_URI" ]] && return

    local color=3066993  # Green
    [[ "$status" == "failure" ]] && color=15158332  # Red

    local fields='[
        {"name": "Domain", "value": "`'"$RECORD_NAME"'`", "inline": true},
        {"name": "Status", "value": "'"$status"'", "inline": true}
    ]'

    if [[ -n "$old_ip" ]] && [[ -n "$new_ip" ]]; then
        fields='[
            {"name": "Domain", "value": "`'"$RECORD_NAME"'`", "inline": true},
            {"name": "Status", "value": "'"$status"'", "inline": true},
            {"name": "Previous IP", "value": "`'"$old_ip"'`", "inline": true},
            {"name": "New IP", "value": "`'"$new_ip"'`", "inline": true}
        ]'
    fi

    curl -s "${DNS_ARGS[@]}" -H "Content-Type: application/json" -X POST \
        --data '{
            "embeds": [{
                "title": "'"$SITENAME - $title"'",
                "description": "'"$message"'",
                "color": '"$color"',
                "fields": '"$fields"',
                "footer": {"text": "Cloudflare DDNS Updater"},
                "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
            }]
        }' "$DISCORD_URI" > /dev/null 2>&1
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
## Public IP detection
## Tries cloudflare trace, then ipify, then icanhazip
###########################################
get_public_ip() {
    local ip

    ip=$(curl -s -4 "${DNS_ARGS[@]}" --max-time 10 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip')
    if [[ $? -eq 0 ]] && [[ -n "$ip" ]]; then
        echo "$ip" | sed -E "s/^ip=($ipv4_regex)$/\1/"
        return 0
    fi

    ip=$(curl -s "${DNS_ARGS[@]}" --max-time 10 https://api.ipify.org)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi

    curl -s "${DNS_ARGS[@]}" --max-time 10 https://ipv4.icanhazip.com
}

###########################################
## Single check cycle: detect IP, query
## Cloudflare, update record if changed.
## Retries each step up to MAX_RETRIES
## times before sending a failure alert.
###########################################
perform_check() {
    log "INFO" "Check initiated"

    # --- Public IP detection (with retries) ---
    local ip
    local attempt=1
    while true; do
        ip=$(get_public_ip)
        [[ $ip =~ ^$ipv4_regex$ ]] && break

        if (( attempt >= MAX_RETRIES )); then
            log "ERROR" "Failed to find a valid IP after $MAX_RETRIES attempts. Got: '$ip'"
            send_notification "failure" "IP Detection Failed" \
                "Could not determine public IP address after $MAX_RETRIES attempts"
            return 1
        fi
        log "WARN" "IP detection failed (attempt $attempt/$MAX_RETRIES), retrying in ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
        (( attempt++ ))
    done

    log "INFO" "Current public IP: $ip"

    # --- Auth header ---
    local auth_header
    if [[ "${AUTH_METHOD}" == "global" ]]; then
        auth_header="X-Auth-Key:"
    else
        auth_header="Authorization: Bearer"
    fi

    # --- DNS record lookup (with retries) ---
    local record
    attempt=1
    while true; do
        record=$(curl -s "${DNS_ARGS[@]}" --max-time 10 -X GET \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_IDENTIFIER/dns_records?type=A&name=$RECORD_NAME" \
            -H "X-Auth-Email: $AUTH_EMAIL" \
            -H "$auth_header $AUTH_KEY" \
            -H "Content-Type: application/json")

        # "count:0" is a permanent configuration error — do not retry
        if [[ $record == *"\"count\":0"* ]]; then
            log "ERROR" "Record does not exist. Create one first: $ip for $RECORD_NAME"
            send_notification "failure" "Record Not Found" \
                "No A record exists for this domain" "" "$ip"
            return 1
        fi

        # Success: response did not indicate failure
        [[ $record != *"\"success\":false"* ]] && break

        if (( attempt >= MAX_RETRIES )); then
            log "ERROR" "API query failed after $MAX_RETRIES attempts: $record"
            send_notification "failure" "API Error" \
                "Failed to query DNS records from Cloudflare after $MAX_RETRIES attempts"
            return 1
        fi
        log "WARN" "API query failed (attempt $attempt/$MAX_RETRIES), retrying in ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
        (( attempt++ ))
    done

    # --- Extract current values from response ---
    local old_ip
    local record_identifier
    old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
    record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

    if [[ ! $old_ip =~ ^$ipv4_regex$ ]]; then
        log "ERROR" "Failed to extract valid old IP. Got: '$old_ip'"
        log "ERROR" "API Response: $record"
        send_notification "failure" "Parse Error" \
            "Could not extract current IP from Cloudflare response"
        return 1
    fi

    if [[ -z "$record_identifier" ]] || [[ "$record_identifier" == "$record" ]]; then
        log "ERROR" "Failed to extract record identifier"
        log "ERROR" "API Response: $record"
        send_notification "failure" "Parse Error" \
            "Could not extract record ID from Cloudflare response"
        return 1
    fi

    log "INFO" "Cloudflare IP: $old_ip | Record ID: $record_identifier"

    # --- No change — exit silently ---
    if [[ $ip == $old_ip ]]; then
        return 0
    fi

    log "INFO" "IP change detected: $old_ip -> $ip"

    # --- DNS record update (with retries) ---
    local update
    attempt=1
    while true; do
        update=$(curl -s "${DNS_ARGS[@]}" --max-time 10 -X PATCH \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_IDENTIFIER/dns_records/$record_identifier" \
            -H "X-Auth-Email: $AUTH_EMAIL" \
            -H "$auth_header $AUTH_KEY" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$ip\",\"TTL\":$TTL,\"proxied\":${PROXY}}")

        [[ $update == *"\"success\":true"* ]] && break

        if (( attempt >= MAX_RETRIES )); then
            log "ERROR" "DNS update failed after $MAX_RETRIES attempts: $update"
            send_notification "failure" "Update Failed" \
                "Failed to update DNS record after $MAX_RETRIES attempts" "$old_ip" "$ip"
            return 1
        fi
        log "WARN" "DNS update failed (attempt $attempt/$MAX_RETRIES), retrying in ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
        (( attempt++ ))
    done

    log "SUCCESS" "DNS updated: $old_ip -> $ip"
    send_notification "success" "DNS Updated" \
        "IP address has been updated successfully" "$old_ip" "$ip"
}

###########################################
## Graceful shutdown handler
###########################################
cleanup() {
    log "INFO" "DDNS Updater service stopping"
    exit 0
}

trap cleanup SIGTERM SIGINT

###########################################
## Service loop
###########################################
log "INFO" "DDNS Updater service starting (interval: ${CHECK_INTERVAL}s, max retries: ${MAX_RETRIES}, retry delay: ${RETRY_DELAY}s)"

while true; do
    perform_check
    sleep "$CHECK_INTERVAL"
done
