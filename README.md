# Cloudflare DDNS Updater

A bash script to automatically update Cloudflare DNS records when your public IP address changes. Ideal for home servers, self-hosted services, and dynamic IP environments.

> **Note:** This is a fork of [K0p1-Git/cloudflare-ddns-updater](https://github.com/K0p1-Git/cloudflare-ddns-updater) with improvements to logging, notifications, and error handling.

## Features

- 🔄 Automatically detects public IP changes
- ☁️ Updates Cloudflare DNS A records via API
- 📱 Slack notifications (using modern Block Kit format)
- 💬 Discord webhook notifications
- 📝 Minimal logging (only logs significant events)
- ✅ Improved error handling and validation
- ⏱️ Curl timeouts to prevent hanging

## What's New in This Fork

| Improvement | Description |
|-------------|-------------|
| **Better error detection** | Validates API responses and extracted values before proceeding |
| **Minimal logging** | Only logs IP changes and errors, not routine checks |
| **Slack Block Kit** | Modern notification format per current Slack API guidelines |
| **Clickable domain links** | Domains always display as links in Slack notifications |
| **Curl timeouts** | Added `--max-time` to prevent script from hanging |
| **Explicit success checking** | Checks for `"success":true` instead of just absence of `"success":false` |

## Requirements

- `bash` or `sh`
- `curl`
- Cloudflare account with API token

## Setup

### 1. Create a Cloudflare API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Use the **Edit zone DNS** template or create a custom token with:
   - **Permissions:** Zone > DNS > Edit
   - **Zone Resources:** Include > Specific zone > Your domain
4. Copy the token

> ⚠️ **Important:** Your API token must have **Zone.DNS Edit** permission. Without this, you'll receive a "PATCH method not allowed for the api_token authentication scheme" error [2].

### 2. Configure the Script

Copy the template and edit your configuration:

```bash
cp cloudflare-template.sh cloudflare-yourdomain.sh
chmod +x cloudflare-yourdomain.sh
nano cloudflare-yourdomain.sh
```

Update these variables [1]:

```bash
auth_email="your-email@example.com"     # Cloudflare login email
auth_method="token"                      # Use "token" for API token
auth_key="your-api-token"               # Your API token
zone_identifier="your-zone-id"          # Found in domain Overview tab
record_name="subdomain.example.com"     # DNS record to update
ttl=3600                                # DNS TTL in seconds
proxy="false"                           # Cloudflare proxy (true/false)
sitename="My Site"                      # For notifications
slackuri=""                             # Slack webhook URL (optional)
discorduri=""                           # Discord webhook URL (optional)
```

### 3. Find Your Zone Identifier

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. Scroll down on the **Overview** tab
4. Copy the **Zone ID** from the right sidebar

### 4. Set Up a Cron Job

Run the script every minute:

```bash
crontab -e
```

Add:

```
* * * * * /path/to/cloudflare-yourdomain.sh
```

## Multiple Domains

To update multiple domains, create a separate script for each:

```bash
cp cloudflare-template.sh cloudflare-domain1.sh
cp cloudflare-template.sh cloudflare-domain2.sh
```

Then add separate cron entries for each script.

## Notifications

### Slack

1. Create an [Incoming Webhook](https://api.slack.com/messaging/webhooks) in your Slack workspace
2. Add the webhook URL to `slackuri`

Notifications use Slack's modern Block Kit format for better formatting and consistent domain linking.

### Discord

1. In your Discord channel, go to **Settings > Integrations > Webhooks**
2. Create a webhook and copy the URL
3. Add it to `discorduri`

## Logging

The script uses `logger` for system logging. Logs only include:

- IP change detections
- Successful updates
- Errors and failures

Routine "no change" checks are not logged to prevent log bloat when running every minute.

View logs with:

```bash
grep "DDNS Updater" /var/log/syslog
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Failed to find a valid IP" | Check internet connection; IP detection services may be temporarily unavailable [2] |
| "PATCH method not allowed for the api_token authentication scheme" | Regenerate API token with **Zone.DNS Edit** permission [2] |
| "Record does not exist" | Create an A record in Cloudflare dashboard first |
| Empty record identifier in logs (e.g., `DDNS failed for  (IP)`) | API response parsing failed; verify zone_identifier and record_name are correct [2] |
| Script hangs | Curl timeouts have been added; check network connectivity |

## How It Works

1. **IP Detection**: The script first attempts to get your public IP from Cloudflare's trace endpoint, with fallbacks to ipify.org and icanhazip.com [1]
2. **Record Lookup**: Queries the Cloudflare API for the existing A record
3. **Comparison**: Compares the current public IP with the DNS record
4. **Update**: If the IPs differ, updates the DNS record via Cloudflare's API
5. **Notification**: Sends a Slack/Discord notification on success or failure

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
