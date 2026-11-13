# ALOOZ HOSTING V100 - VPS + Minecraft + Invite Rewards

## Quick Setup
1. Upload `install.sh` to your VPS.
2. Run: `chmod +x install.sh && sudo bash install.sh`
3. Enter Discord Bot Token and your Discord User ID when prompted.
4. **IMPORTANT:** Go to [Discord Developer Portal](https://discord.com/developers/applications) -> Your Bot -> Bot -> Enable **SERVER MEMBERS INTENT**.
5. Restart bot: `systemctl restart alooz-bot`

## How Invite System Works
- Users invite friends using their Discord invite link.
- Bot tracks joins/leaves.
- Users type `/invites` to check their total.
- At 3+ invites, they use `/invite-claim type:vps` or `type:mc` to get a server.
- The server **auto-deletes after 30 days**.
- Users can type `/renew type:vps id:1` to renew for 30 days (costs 2 invites).

## Commands
- `/invites` - Check invites & tier
- `/invite-claim` - Claim a server
- `/renew` - Renew server (2 invites)
- `/myvps` - List your VPS
- `/ssh` - Get SSHX terminal link
- `/mc-list` - List MC servers
- `/help` - All commands

## Admin Commands
- `/deploy` - Manual VPS deploy
- `/listall` - List all VPS
- `/delete` - Delete VPS
- `/node` - Check system resources

## Troubleshooting
- If invite tracking fails, make sure **SERVER MEMBERS INTENT** is enabled in Discord Developer Portal.
- If `/ssh` fails, try again after 30 seconds (container is still booting).