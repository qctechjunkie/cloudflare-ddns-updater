# Cloudflare DDNS Updater

A bash script that runs as a **systemd service** to automatically update Cloudflare DNS records when your public IP address changes. Ideal for home servers, self-hosted services, and dynamic IP environments.

> **Note:** This is a fork of [K0p1-Git/cloudflare-ddns-updater](https://github.com/K0p1-Git/cloudflare-ddns-updater) with improvements to logging, notifications, retry logic, and service-based operation.

## Features

- Automatically detects public IP changes
- Updates Cloudflare DNS A records via API
- Runs as a persistent systemd service (no cron needed)
- Slack notifications (Block Kit format)
- Discord webhook notifications
- Generic webhook notifications (e.g. Home Assistant)
- Retry logic with configurable attempts and delay
- Structured logging via systemd journal
- Bypasses local DNS servers (e.g. AdGuard Home) for DNS lookups

## What's New in This Fork

| Improvement | Description |
|-------------|-------------|
| **Systemd service** | Runs as a long-lived service instead of a cron job; supports multiple instances via `cloudflare-ddns@.service` |
| **Retry logic** | Configurable `MAX_RETRIES` and `RETRY_DELAY` for transient failures |
| **DNS server override** | `DNS_SERVER` bypasses forced local DNS (e.g. AdGuard Home) so routine checks don't pollute your query logs |
| **Better error detection** | Validates API responses and extracted values before proceeding |
| **Minimal logging** | Only logs IP changes and errors, not routine no-change checks |
| **Slack Block Kit** | Modern notification format per current Slack API guidelines |
| **Generic webhook** | Sends a JSON POST to any webhook URL (e.g. Home Assistant automations) |
| **Curl timeouts** | `--max-time` on every request prevents the script from hanging |

## Requirements

- `bash`
- `curl` >= 7.86.0 (required for `--dns-servers` support)
- Cloudflare account with API token

## Setup

### 1. Create a Cloudflare API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Use the **Edit zone DNS** template or create a custom token with:
   - **Permissions:** Zone > DNS > Edit
   - **Zone Resources:** Include > Specific zone > Your domain
4. Copy the token

> **Important:** Your API token must have **Zone.DNS Edit** permission. Without this, you will get a "PATCH method not allowed for the api_token authentication scheme" error.

### 2. Configure the Script

Copy the template and fill in your values:

```bash
cp cloudflare-template.sh cloudflare-yourdomain.sh
chmod +x cloudflare-yourdomain.sh
nano cloudflare-yourdomain.sh
```

Update the configuration block at the top:

```bash
AUTH_EMAIL="your-email@example.com"       # Cloudflare login email
AUTH_METHOD="token"                        # "token" for API token, "global" for Global API Key
AUTH_KEY="your-api-token"                 # Your API token or Global API Key
ZONE_IDENTIFIER="your-zone-id"            # Found in domain Overview tab (see step 3)
RECORD_NAME="subdomain.example.com"       # DNS A record to keep updated
TTL=3600                                  # DNS TTL in seconds
PROXY="false"                             # Cloudflare proxy (true/false)
SITENAME="My Site"                        # Used in notification titles
SLACK_URI=""                              # Slack webhook URL (optional)
DISCORD_URI=""                            # Discord webhook URL (optional)
WEBHOOK_URI=""                            # Generic webhook URL (optional, e.g. Home Assistant)
CHECK_INTERVAL=60                         # Seconds between IP checks
MAX_RETRIES=3                             # Attempts before sending a failure alert
RETRY_DELAY=30                            # Seconds between retry attempts
DNS_SERVER="1.1.1.1"                      # DNS server for lookups (see DNS Server Override below)
```

### 3. Find Your Zone Identifier

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. Scroll down on the **Overview** tab
4. Copy the **Zone ID** from the right sidebar

### 4. Install the Systemd Service

Copy your configured script and the service unit to their target locations:

```bash
# Create the script directory
sudo mkdir -p /opt/cloudflare-ddns

# Copy your configured script (repeat for each domain)
sudo cp cloudflare-yourdomain.sh /opt/cloudflare-ddns/cloudflare-yourdomain.sh
sudo chmod +x /opt/cloudflare-ddns/cloudflare-yourdomain.sh

# Install the service template
sudo cp cloudflare-ddns@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

The service file is a **systemd template** (`@`). The part after `@` in the instance name maps directly to a script in `/opt/cloudflare-ddns/`:

```
cloudflare-ddns@yourdomain.service  →  /opt/cloudflare-ddns/cloudflare-yourdomain.sh
```

### 5. Enable and Start the Service

```bash
# Enable to start on boot, and start immediately
sudo systemctl enable --now cloudflare-ddns@yourdomain.service
```

Check it is running:

```bash
sudo systemctl status cloudflare-ddns@yourdomain.service
```

## Multiple Domains

Create a separate configured script for each domain and enable a separate service instance for each:

```bash
sudo cp cloudflare-template.sh /opt/cloudflare-ddns/cloudflare-domain1.sh
sudo cp cloudflare-template.sh /opt/cloudflare-ddns/cloudflare-domain2.sh
# edit each script with the correct credentials and RECORD_NAME

sudo systemctl enable --now cloudflare-ddns@domain1.service
sudo systemctl enable --now cloudflare-ddns@domain2.service
```

Each instance runs independently and is identifiable by name in the journal.

## DNS Server Override

By default, every `curl` request resolves hostnames using your system's configured DNS server. If you run a local DNS filter like AdGuard Home that intercepts all DNS queries, every 60-second IP check will show up in its query log.

Set `DNS_SERVER` to any upstream resolver to bypass it:

```bash
DNS_SERVER="1.1.1.1"    # Cloudflare (default)
DNS_SERVER="8.8.8.8"    # Google
DNS_SERVER=""           # Leave empty to use system default
```

This applies to all outbound requests — IP detection, Cloudflare API calls, and webhook notifications.

> **Requires curl >= 7.86.0.** Check with `curl --version`. Raspberry Pi OS Bookworm (Debian 12) ships a compatible version; Bullseye may need a curl upgrade.

## Notifications

### Slack

1. Create an [Incoming Webhook](https://api.slack.com/messaging/webhooks) in your Slack workspace
2. Set `SLACK_URI` to the webhook URL

Notifications use Slack's Block Kit format with clickable domain links.

### Discord

1. In your Discord channel, go to **Settings > Integrations > Webhooks**
2. Create a webhook and copy the URL
3. Set `DISCORD_URI` to the webhook URL

### Generic Webhook (Home Assistant)

Set `WEBHOOK_URI` to any HTTP endpoint that accepts a JSON POST. Leave it empty to disable.

```bash
WEBHOOK_URI="http://homeassistant.local:8123/api/webhook/ddns-update"
```

The payload sent on every notification event:

```json
{
  "status": "success",
  "title": "DNS Updated",
  "message": "IP address has been updated successfully",
  "site": "My Site",
  "domain": "example.com",
  "old_ip": "1.2.3.4",
  "new_ip": "5.6.7.8",
  "timestamp": "2026-03-12T10:00:00Z"
}
```

**Home Assistant setup:**

1. In HA, go to **Settings > Automations > Create Automation > When: Webhook**
2. Copy the generated webhook ID and set `WEBHOOK_URI` to `http://<ha-ip>:8123/api/webhook/<id>`
3. Use `{{ trigger.json.status }}`, `{{ trigger.json.new_ip }}`, `{{ trigger.json.domain }}`, etc. in your automation actions

Notifications are only sent on IP change (success) or repeated failure — not on routine no-change checks.

## Logging

The script logs via `logger` which routes to the systemd journal. Only significant events are logged:

- Service start/stop
- IP change detected and applied
- Retry attempts and failures

To follow logs for a specific instance:

```bash
journalctl -u cloudflare-ddns@yourdomain.service -f
```

To view recent logs:

```bash
journalctl -u cloudflare-ddns@yourdomain.service -n 50
```

To search all DDNS logs across instances:

```bash
journalctl -g "DDNS Updater"
```

## Managing the Service

```bash
# Start / stop / restart
sudo systemctl start cloudflare-ddns@yourdomain.service
sudo systemctl stop cloudflare-ddns@yourdomain.service
sudo systemctl restart cloudflare-ddns@yourdomain.service

# Disable autostart
sudo systemctl disable cloudflare-ddns@yourdomain.service

# Check status
sudo systemctl status cloudflare-ddns@yourdomain.service
```

## How It Works

Each service instance runs a continuous loop:

1. **IP Detection** — Fetches your public IP from Cloudflare's trace endpoint, with fallbacks to `ipify.org` and `icanhazip.com`
2. **Record Lookup** — Queries Cloudflare API for the current A record value
3. **Comparison** — If the IPs match, the loop sleeps for `CHECK_INTERVAL` seconds and repeats
4. **Update** — If they differ, the A record is updated via Cloudflare's API
5. **Notification** — Sends a Slack/Discord/webhook notification on successful update or repeated failure
6. **Retry** — Each step retries up to `MAX_RETRIES` times (with `RETRY_DELAY` seconds between attempts) before sending a failure alert

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Service fails to start | Check `journalctl -u cloudflare-ddns@yourdomain.service` for errors; verify the script path and permissions |
| "Failed to find a valid IP" | Check internet connectivity; IP detection services may be temporarily unavailable |
| "PATCH method not allowed for the api_token authentication scheme" | Regenerate API token with **Zone.DNS Edit** permission |
| "Record does not exist" | Create an A record manually in the Cloudflare dashboard first |
| DNS server override not working | Verify `curl --version` shows >= 7.86.0; the `--dns-servers` flag requires c-ares support |
| AdGuard Home still showing queries | Ensure `DNS_SERVER` is set to a non-empty value in your script |
| Script hangs | Each `curl` call has `--max-time 10`; check network connectivity if retries are exhausted |

## Credits

- Original script by [K0p1-Git](https://github.com/K0p1-Git/cloudflare-ddns-updater)
- Fork maintained by [qctechjunkie](https://github.com/qctechjunkie)

## Support This Project

If you find this useful, consider supporting development:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/qctechjunkie)

[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-EA4AAA?style=for-the-badge&logo=github-sponsors&logoColor=white)](https://github.com/sponsors/qctechjunkie)

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request
