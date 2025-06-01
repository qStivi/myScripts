# Scripts Collection

This repository contains a variety of useful Linux and general-purpose scripts. Each script is designed to be self-contained and may automate setup, maintenance, or troubleshooting tasks.

---

## 🚀 How to Use Any Script from This Repository

### 1. **Find the Script**

* Browse the repository and select the script you want to use (for example, `myscript.sh`).

### 2. **Get the Raw Script URL**

* Click on the script file in GitHub to open it.
* Click the **"Raw"** button to view the plain text version.
* Copy the URL from your browser’s address bar. The raw URL will look like this:

  ```
  https://raw.githubusercontent.com/qStivi/myScripts/main/<script.sh>
  ```

---

### 3. **Download and Run the Script (Interactive-Friendly)**

**Recommended: Download, Inspect, Then Run**

This approach lets you review the script before running it and fully supports interactive prompts (like password entry, confirmations, etc).

```bash
curl -O https://raw.githubusercontent.com/qStivi/myScripts/main/<script.sh>
chmod +x <script.sh>
sudo ./<script.sh>
```

Or using `wget`:

```bash
wget https://raw.githubusercontent.com/qStivi/myScripts/main/<script.sh>
chmod +x <script.sh>
sudo ./<script.sh>
```

---

**Alternative: Run Directly from GitHub (One-liner)**

If you trust the script and repository, you can run it directly with:

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/qStivi/myScripts/main/<script.sh>)
```

or

```bash
sudo bash <(wget -qO- https://raw.githubusercontent.com/qStivi/myScripts/main/<script.sh>)
```

> **Note:** Both methods support interactive prompts.
> **Best practice:** Always review scripts before running them, especially with sudo/root.

---

## ⚠️ Security Note

* **Always review scripts before executing them, especially as root.**
* Some scripts may create or modify system files. Read script comments and instructions for details.
* Be aware of any scripts that handle credentials or sensitive information and follow guidance on securing such files.

---

## 📝 Example

If you want to run a script called `setup.sh` from this repository’s `main` branch:

```bash
curl -O https://raw.githubusercontent.com/qStivi/myScripts/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

Or, as a one-liner:

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/qStivi/myScripts/main/setup.sh)
```
