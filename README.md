# Obsidian Vault - Jonas Integration

This vault integrates with the Jonas AI agent to sync generated notes.

## Setup

1. **Create `.env` file** in this directory:
   ```bash
   KEY_PATH=/absolute/path/to/your/ssh/key
   HOST=user@your-vm-hostname.com
   JONAS_VAULT_PATH=/path/to/jonas/.volumes/agent-data/vault/
   JONAS_LOCAL_TMP_VAULT=/Users/your-user/Projects/jonas/.volumes/agent-data/vault
   # Optional: override final destination (defaults to iCloud Obsidian path)
   JONAS_LOCAL_VAULT=/Users/your-user/Notes/Jonas
   ```

2. **Set up shell alias** (add to `~/.zshrc`):
   ```bash
   alias jvs='~/Projects/oc/scripts/sync-from-jonas.sh'
   ```

3. **Reload shell**:
   ```bash
   source ~/.zshrc
   ```

## Usage

```bash
# Sync Jonas notes
jvs
```

The script will:
- Connect to your Jonas VM via SSH
- Check for new/updated notes in the agent vault
- Sync them to your iCloud Obsidian vault
- Show what files changed

## Synced Content

Jonas notes are synced to:
```
~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jonas/
```

The agent creates:
- `daily/` - Daily notes and summaries
- `conversations/` - Conversation exports
- `research/` - Research findings
- `inbox/` - Quick captures

## Troubleshooting

**Connection errors:**
```bash
# Test SSH manually
ssh -i $KEY_PATH $HOST

# Verify vault path exists
ssh -i $KEY_PATH $HOST 'ls -la /path/to/vault/'
```

**Permission errors:**
- Ensure SSH key has correct permissions: `chmod 600 $KEY_PATH`
- Verify SSH key is added to remote: `ssh-copy-id -i $KEY_PATH $HOST`
