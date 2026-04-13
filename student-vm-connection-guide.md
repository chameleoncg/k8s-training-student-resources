# Student VM Connection Guide

Welcome to the Kubernetes Training Series\! For the hands-on portions of this course, you have been assigned a dedicated Virtual Machine (VM).

This guide provides step-by-step instructions on how to securely connect to your VM using SSH (Secure Shell).

> [!IMPORTANT]
> Having trouble? Skip straight to [**I Need Help!**](#i-need-help) at the bottom of the page.

## Prerequisites

Before you begin, locate the **Welcome to K8s Training - Your Student VM Details** email you received for the course. It contains three critical pieces of information you will need:

1. **VM Default Username** (`k8s-training`)
2. **VM IP Address** (e.g., `192.168.1.50`)
3. **VM SSH Private Key URL**, which is a unique link to download your private SSH key file.

### Step 1: Download Your SSH Key

Click the **VM SSH Private Key URL** provided in your email. This will automatically download a private key file to your computer (e.g., `vm-#-key`). By default, this usually saves to your `Downloads` folder.

## Operating System Guides

Please select your operating system and preferred terminal from the list below:

* [Windows 11 (Built-in SSH Client)](#windows-11-built-in-ssh-client)
* [Windows 11 (Using Windows Subsystem for Linux - WSL)](#windows-11-wsl)
* [macOS (Built-in Terminal or iTerm)](#macos-terminal-and-iterm)
* [Ubuntu Linux (Built-in Terminal)](#ubuntu-linux)



## Windows 11 (Built-in SSH Client)

Windows 11 comes with a built-in SSH client that you can use via PowerShell or the Command Prompt. SSH requires your private key to be heavily secured so that only your user account can read it.

### Step 2: Secure Your SSH Key

You must restrict the permissions of your downloaded private key file. You can do this using the Graphical User Interface (GUI) or the Command Line Interface (CLI).

#### Option A: Using the GUI (File Explorer)

1. Open **File Explorer** and navigate to your `Downloads` folder.
2. Right-click your downloaded private key file and select **Properties**.
3. Go to the **Security** tab and click the **Advanced** button.
4. Click **Disable inheritance**. Choose the option to **Remove all inherited permissions from this object**.
5. Click **Add**, then click **Select a principal**.
6. Type your exact Windows username into the box, click **Check Names**, and then click **OK**.
7. In the permissions window, check the box for **Read** and click **OK**.
8. Click **OK** on all remaining windows to apply the settings.

#### Option B: Using the CLI (PowerShell)

1. Open the Start Menu, type `PowerShell`, and press Enter.
2. Run the following commands to navigate to your Downloads folder and restrict the file permissions (replace `vm-#-key` with your exact file name):
    ```
    cd ~\Downloads
    icacls vm-#-key /inheritance:r /grant "$($env:USERNAME):R"
    ```

### Step 3: Connect to the VM

In your PowerShell window, run the following SSH command. Replace `vm-#-key` with your file's name, username with the username from your email, and IP_ADDRESS with your VM's IP:
```
ssh -i .\[vm-#-key] k8s-training@[ip-address]
```
> [!TIP]
> If prompted with a message about the host's authenticity, type `yes` and press Enter.



## Windows 11 (WSL)

If you already use the Windows Subsystem for Linux (WSL), it is highly recommended to connect to your VM from within your Linux distribution.

### Step 2: Secure Your SSH Key

In Linux, SSH requires file permissions to be set to read-only for the owner (`chmod 400`).

#### Setting Permissions via CLI

1. Open your WSL terminal (e.g., Ubuntu).
2. Copy the private key file from your Windows Downloads folder to your WSL home directory's .ssh folder:
    ```
    mkdir -p ~/.ssh
    cp /mnt/c/Users/YOUR_WINDOWS_USERNAME/Downloads/[vm-#-key] ~/.ssh/
    ```
3. Restrict the permissions on the key:
    ```
    chmod 400 ~/.ssh/[vm-#-key]
    ```
> [!NOTE]
> There is no native GUI method entirely within standard WSL without installing a desktop environment, so the CLI method is required here.

### Step 3: Connect to the VM

Run the following command in your WSL terminal, replacing the placeholder text with the details from your email:
```
ssh -i ~/.ssh/[vm-#-key] k8s-training@[ip-address]
```
> [!TIP]
> If prompted with a message about the host's authenticity, type `yes` and press Enter.



## macOS (Terminal and iTerm)

The connection process on macOS is identical whether you are using the default **Terminal** app (found in Applications > Utilities) or **iTerm**.

### Step 2: Secure Your SSH Key

SSH will reject your connection if your private key file is accessible by other users on your Mac. You must secure it.

#### Option A: Using the GUI (Finder)

1. Open **Finder** and go to your Downloads folder.
2. Right-click the private key file and select **Get Info**.
3. At the bottom of the window, expand the **Sharing & Permissions** section.
4. Click the **Padlock** icon in the bottom right and enter your Mac password to unlock it.
5. Under the "Privilege" column, ensure your username is set to **Read & Write** (or Read Only).
6. Change the privileges for "staff" and "everyone" to **No Access**.
7. Close the Get Info window.

#### Option B: Using the CLI (Terminal/iTerm) - *Recommended*

1. Open **Terminal** or **iTerm**.
2. Run the following commands to navigate to your Downloads folder and set the permissions to read-only for your user:
    ```
    cd ~/Downloads
    chmod 400 [vm-#-key]
    ```

### Step 3: Connect to the VM

In your Terminal or iTerm window, run the following command. Replace the placeholder values with the details from your email:
```
ssh -i [vm-#-key] k8s-training@[ip-address]
```
> [!TIP]
> If prompted with a message about the host's authenticity, type `yes` and press Enter.



## Ubuntu Linux

For users running Ubuntu Linux natively, you can use the default Terminal application to secure your key and connect.

### Step 2: Secure Your SSH Key

Linux SSH enforces strict permission checks on private key files. The file must only be readable by you.

#### Option A: Using the GUI (Files / Nautilus)

1. Open the **Files** application and navigate to your Downloads folder.
2. Right-click your downloaded private key file and select **Properties**.
3. Navigate to the **Permissions** tab.
4. Set the **Owner** access to **Read-only**.
5. Set the **Group** access to **None**.
6. Set the **Others** access to **None**.
7. Close the Properties window.

#### Option B: Using the CLI (Terminal)

1. Open the **Terminal** application (Ctrl+Alt+T).
2. Run the following commands to navigate to your Downloads folder and lock down the file:
    ```
    cd ~/Downloads
    chmod 400 [vm-#-key]
    ```

### Step 3: Connect to the VM

In your Terminal window, execute the SSH command below. Remember to swap out the placeholder text for the specific username and IP address found in your course email:
```
ssh -i [vm-#-key] k8s-training@[ip-address]
```
> [!TIP]
> If prompted with a message about the host's authenticity, type `yes` and press Enter.


# I Need Help!
If you are unable to connect to your VM, walk through these verification steps in order. They range from the most common mistakes to rarer edge cases.

1. Verify Credentials and Typos
    * **Error**: `ssh: connect to host IP_ADDRESS port 22: Connection timed out` or `Permission denied (publickey)`.
    * **Fix**: Double-check your IP address and username. Ensure you didn't accidentally copy a trailing space or swap numbers around. The username must be `k8s-training`, not your personal name.

2. Verify Key File Path
    * **Error**: `Warning: Identity file vm#-private not accessible: No such file or directory`.
    * **Fix**: The SSH command cannot find your key file. Ensure you are running the ssh command from the exact same folder where the file lives (usually `Downloads`), OR provide the full path to the file in the command (e.g., `ssh -i C:\Users\Name\Downloads\[vm-#-key] k8s-training@[ip-address]`).

3. Verify File Permissions
    * **Error**: `WARNING: UNPROTECTED PRIVATE KEY FILE!`
    * **Fix**: Your SSH client is rejecting the key because it is readable by other users on your system. You must go back to Step 2 for your specific operating system and ensure the key's permissions are restricted to your user account only (`chmod 400`):
      * [Windows 11 (Built-in SSH Client)](#windows-11-built-in-ssh-client)
      * [Windows 11 (Using Windows Subsystem for Linux - WSL)](#windows-11-wsl)
      * [macOS (Built-in Terminal or iTerm)](#macos-terminal-and-iterm)
      * [Ubuntu Linux (Built-in Terminal)](#ubuntu-linux)

4. Verify Network Restrictions
    * **Error**: `ssh: connect to host IP_ADDRESS port 22: Connection timed out` (even when the IP is correct).
    * **Fix**: You might be on a restricted corporate network or VPN that blocks outgoing SSH connections (Port 22). Try disconnecting from your VPN or switching to a different Wi-Fi network (like a mobile hotspot) to see if the connection goes through.

5. Verify File Format (Missing Newline)
    * **Error**: `Load key "[vm-#-key]": invalid format`
    * **Fix**: Occasionally, browsers or text editors modify the downloaded key file and remove the required blank line at the end of the file.
        1. Open your `[vm-#-key]` file in a basic text editor (like Notepad on Windows, or nano/TextEdit on macOS/Linux).
        2. Scroll to the very bottom. The last line of text should be `-----END OPENSSH PRIVATE KEY-----` (or similar).
        3. Place your cursor at the end of that line and press Enter/Return exactly once to add a single blank line.
        4. Save the file and try your SSH command again.

Still having trouble? Join the VM troubleshooting room for assistance.