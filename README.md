# Authentik + Nginx Proxy Manager + Cloudflare Automation Script

This Bash script automates the full setup of a **secure, authenticated reverse proxy** using:

- 🧠 [Authentik](https://goauthentik.io/) (SSO & Identity Provider)
- 🌐 [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) (exposes local services securely)
- 🧰 [Nginx Proxy Manager](https://nginxproxymanager.com/) (manages proxies easily)

---

## 🚀 What It Does

This script:

1. **Prompts for application details** like domain, port, and scheme.
2. **Creates a proxy host** in Nginx Proxy Manager with Authentik-specific config.
3. **Enables SSL** on the created host.
4. **Updates your Cloudflare Tunnel config** to include the new domain.
5. **Registers the app with Authentik**, creating a proxy provider and linking it to a new application.

---

## 🛠️ Prerequisites

Before running, make sure:

- You have **Nginx Proxy Manager CLI** (`nginx_proxy_manager_cli.sh`) ready and executable.
- Cloudflare Tunnel is already set up with an existing `TUNNEL_ID`.
- Authentik instance is up and running.
- `jq` is installed on your system.

---

## ⚙️ Required Variables

You’ll need to update the following variables in the script:

```bash
AUTHENTIK_INSTANCE="https://auth.company.com"
AUTHENTIK_API_TOKEN="YOUR_AUTHENTIK_API_TOKEN"

ACCOUNT_ID="YOUR_CLOUDFLARE_ACCOUNT_ID"
TUNNEL_ID="YOUR_CLOUDFLARE_TUNNEL_ID"
CLOUDFLARE_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN"
```

---

## 🧪 How to Use

```bash
chmod +x setup_proxy.sh
./setup_proxy.sh
```

You will be prompted to enter:

- Application Name
- Domain Name(s)
- Forward Host (defaults to 192.168.1.75)
- Forward Port
- Forward Scheme (http or https)

The script takes care of everything else!

---

## 🧩 Features

- ✅ Interactive CLI prompts
- 🔐 Automates Authentik proxy provider creation
- 🌍 Cloudflare Tunnel integration with domain rules
- 🔄 Seamless Nginx Proxy Manager CLI usage
- 🛡️ Adds secure Authentik SSO reverse proxy rules
- 🧾 Cleans up and patches JSON config on the fly with `jq`
- 🔐 SSL enablement for added security

---
## 📂 Example Use Case

Let’s say you have an internal app on:

- **IP**: `192.168.1.100`
- **Port**: `8080`
- **Domain**: `myapp.company.com`

Running this script will:

- Create a proxy for `myapp.company.com`
- Secure it with SSL
- Enforce Authentik SSO login
- Tunnel it securely via Cloudflare

---

## 📜 License

MIT

---

## 🙏 Credits

Built with ❤️ by [Aneez] for automating secure access to self-hosted services.
