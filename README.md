# sync_remote.sh

A helper script to sync directories between your local machine and the remote host.

## 1. SSH Configuration

Add an entry for your remote host (e.g. `datalab`) in your `~/.ssh/config`:

```ssh-config
Host datalab
  HostName cluster.datalab.tuwien.ac.at  # or your actual hostname
  User your_username
  IdentityFile ~/.ssh/id_rsa             # or your key path
```

## 2. Configure the Script

Edit the top of **sync_remote.sh** to match your setup:

```bash
# === CONFIGURATION (modify as needed) ===
REMOTE="datalab"
REMOTE_ROOT="your_sync_project"        	 # under ~ on the remote
LOCAL_ROOT="$HOME/your_local_project"    # under $HOME on the local
```

## 3. (Optional) Create an Alias

To call the script more easily, add this to your `~/.bashrc` or `~/.zshrc`:

```bash
alias sync_remote="/path/to/sync_remote.sh"
```

Reload your shell:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

You can now run:

```bash
sync_datalab --pull --remote-sub my/remote/subdir [--local-sub my/local/target/dir] [PATTERN...]
```

or

```bash
sync_datalab --push --local-sub my/local/subdir [--remote-sub my/remote/target/dir] [PATTERN...]
