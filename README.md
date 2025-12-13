# Factorio Server - Kubernetes Deployment

Dedicated Factorio game server running on Kubernetes, managed via ArgoCD GitOps.

## Architecture

- **Container**: `factoriotools/factorio:latest-rootless` (non-root, UID 1000)
- **Deployment**: StatefulSet with single replica
- **Storage**: 20Gi persistent volume (hcloud-volumes StorageClass)
- **Network**: hostNetwork mode (binds directly to node's network), headless
  service for game traffic, ClusterIP service for RCON
- **Resources**: 2-3 CPU cores, 2-4Gi RAM

## Repository Structure

```
k8s/
├── base/
│   ├── namespace.yaml          # Factorio namespace
│   └── kustomization.yaml
├── config/
│   ├── server-settings.yaml    # Server configuration ConfigMap
│   ├── mod-list.yaml           # Mod list ConfigMap
│   └── kustomization.yaml
├── workloads/
│   ├── statefulset.yaml        # Main server StatefulSet (with hostNetwork)
│   ├── service-game.yaml       # Headless service for game traffic
│   ├── service-rcon.yaml       # ClusterIP TCP 27015
│   └── kustomization.yaml
└── kustomization.yaml          # Root kustomization
```

## Deployment

### Automatic (via ArgoCD)

The server is automatically deployed via ArgoCD application defined in the
infrastructure repository:

```yaml
# In infra repo: argocd/applications/factorio.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: factorio
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/mtrenker/factorio-server
    path: k8s/
    targetRevision: main
```

**To deploy**: Push changes to this repository's `main` branch. ArgoCD will
automatically sync within minutes.

### Manual (for testing)

```bash
# Apply all manifests
kubectl apply -k k8s/

# Check deployment status
kubectl get statefulset -n factorio
kubectl get pods -n factorio
kubectl get pvc -n factorio

# View logs
kubectl logs -n factorio factorio-0 -f
```

## Connecting to the Server

### Finding the Server IP

The server uses `hostNetwork: true` to bind directly to the node's network
namespace, making port 34197/UDP accessible on the node where the pod is
running:

```bash
# Find which node the pod is running on
kubectl get pod -n factorio factorio-0 -o wide

# Get the EXTERNAL-IP of that node
kubectl get nodes -o wide
```

### Connection Details

- **Server Address**: `<node-ip>:34197` (e.g., `10.0.0.10:34197`)
- **Protocol**: UDP
- **Port**: 34197
- **Server Name**: "My Factorio Server"

### In Factorio Client

1. Launch Factorio
2. Click "Multiplayer" → "Browse games"
3. Click "Connect to address"
4. Enter: `<pod-node-ip>:34197` (use the external IP of the node running the
   pod)
5. Click "Connect"

## Administration

### RCON Access

Remote Console (RCON) allows server management without game client access.

#### Get RCON Password

```bash
# Password is auto-generated on first start
kubectl exec -n factorio factorio-0 -- cat /factorio/config/rconpw
```

#### Connect via RCON

```bash
# Port-forward RCON to localhost
kubectl port-forward -n factorio svc/factorio-rcon 27015:27015

# Use any RCON client (e.g., mcrcon)
mcrcon -H localhost -P 27015 -p <password>
```

#### Common RCON Commands

```
/players              # List connected players
/admins               # List server admins
/promote <player>     # Promote player to admin
/demote <player>      # Demote admin to player
/ban <player>         # Ban player
/unban <player>       # Unban player
/kick <player>        # Kick player
/time                 # Show game time
/evolution            # Show evolution factor
```

### Accessing Server Files

```bash
# List saves
kubectl exec -n factorio factorio-0 -- ls -lh /factorio/saves/

# Download a save file
kubectl cp factorio/factorio-0:/factorio/saves/my-server.zip ./my-server.zip

# Upload a save file
kubectl cp ./my-save.zip factorio/factorio-0:/factorio/saves/my-save.zip

# Load specific save (restart required)
# Edit StatefulSet env: SAVE_NAME=my-save
```

## Configuration

### Server Settings

Edit [k8s/config/server-settings.yaml](k8s/config/server-settings.yaml) to
customize:

- Server name and description
- Max players
- Game password
- Visibility (public/private)
- Autosave interval
- Admin permissions
- AFK kick settings

**Changes require**:

1. Push changes to git
2. ArgoCD will sync automatically
3. Restart pod: `kubectl rollout restart statefulset/factorio -n factorio`

### Environment Variables

Edit [k8s/workloads/statefulset.yaml](k8s/workloads/statefulset.yaml) to modify:

```yaml
env:
  - name: SAVE_NAME
    value: "my-server" # Save file name (without .zip)
  - name: LOAD_LATEST_SAVE
    value: "true" # Load most recent save on start
  - name: GENERATE_NEW_SAVE
    value: "true" # Generate new save if none exists
  - name: UPDATE_MODS_ON_START
    value: "true" # Auto-update mods on start
```

### Resource Limits

Current allocation (defined in StatefulSet):

```yaml
resources:
  requests:
    cpu: "2000m" # 2 CPU cores guaranteed
    memory: "2Gi" # 2GB RAM guaranteed
  limits:
    cpu: "3000m" # 3 CPU cores max
    memory: "4Gi" # 4GB RAM max
```

**Scaling up**: Increase limits if experiencing lag or slow saves (large
maps/many players).

## Backups

### Manual Backup

```bash
# Backup entire data directory
kubectl exec -n factorio factorio-0 -- tar czf /tmp/factorio-backup.tar.gz /factorio/saves /factorio/config

# Download backup
kubectl cp factorio/factorio-0:/tmp/factorio-backup.tar.gz ./factorio-backup-$(date +%Y%m%d).tar.gz
```

### Automated Backups (Recommended)

Consider implementing:

1. **VolumeSnapshot**: Use CSI driver volume snapshots
2. **CronJob**: Periodic backup to object storage
3. **Velero**: Cluster-wide backup solution

Example CronJob (create in `k8s/workloads/backup-cronjob.yaml`):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: factorio-backup
  namespace: factorio
spec:
  schedule: "0 */6 * * *" # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: alpine:latest
              command:
                - /bin/sh
                - -c
                - |
                    apk add --no-cache tar gzip
                    tar czf /backup/factorio-$(date +%Y%m%d-%H%M%S).tar.gz /data/saves
              volumeMounts:
                - name: factorio-data
                  mountPath: /data
                - name: backup-storage
                  mountPath: /backup
          restartPolicy: OnFailure
          volumes:
            - name: factorio-data
              persistentVolumeClaim:
                claimName: factorio-data-factorio-0
            - name: backup-storage
              # Define backup storage (NFS, S3, etc.)
```

## Monitoring

### Check Server Status

```bash
# Pod status
kubectl get pods -n factorio

# Resource usage
kubectl top pod -n factorio factorio-0

# Recent events
kubectl get events -n factorio --sort-by='.lastTimestamp'

# Server logs
kubectl logs -n factorio factorio-0 --tail=100 -f
```

### Health Checks

The StatefulSet includes:

- **Readiness Probe**: TCP check on RCON port (27015)
  - Ensures pod is ready before receiving traffic
- **Liveness Probe**: TCP check on RCON port (27015)
  - Restarts pod if server becomes unresponsive

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n factorio factorio-0

# Check logs
kubectl logs -n factorio factorio-0

# Common issues:
# - PVC not bound: Check StorageClass 'hcloud-volumes' exists
# - Image pull errors: Verify internet connectivity from cluster
# - Permission errors: Rootless image should avoid these (UID 1000)
```

### Connection Issues

```bash
# Find which node the pod is on
kubectl get pod -n factorio factorio-0 -o wide

# Get the external IP of that node
kubectl get node <node-name> -o wide

# Test UDP port is accessible (from outside the cluster)
nc -vuz <pod-node-external-ip> 34197

# Verify firewall rule allows UDP 34197
# Check your infrastructure firewall configuration
```

### Save File Issues

```bash
# List saves
kubectl exec -n factorio factorio-0 -- ls -la /factorio/saves/

# Check permissions (should be 1000:1000)
kubectl exec -n factorio factorio-0 -- ls -ln /factorio/saves/

# Fix permissions if needed (shouldn't be required with rootless)
kubectl exec -n factorio factorio-0 -- chown -R 1000:1000 /factorio
```

### Performance Issues

```bash
# Check resource usage
kubectl top pod -n factorio

# If CPU/memory at limits, increase resources in StatefulSet
# Consider moving to dedicated node with more resources
```

## Upgrading

### Update Factorio Version

Edit [k8s/workloads/statefulset.yaml](k8s/workloads/statefulset.yaml):

```yaml
spec:
  template:
    spec:
      containers:
        - name: factorio
          image: factoriotools/factorio:1.1.104-rootless # Change from latest-rootless to pin specific version
```

**Steps**:

1. Backup save files
2. Update image tag in git
3. Push changes
4. ArgoCD syncs automatically
5. Verify new version in logs

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo statefulset/factorio -n factorio

# Or revert git commit and let ArgoCD sync
```

## Adding Mods

### Manual Method

```bash
# 1. Download mod .zip files

# 2. Copy to server
kubectl cp ./my-mod_1.0.0.zip factorio/factorio-0:/factorio/mods/

# 3. Restart server
kubectl rollout restart statefulset/factorio -n factorio
```

### Automatic Method (Requires Factorio.com Account)

The server is configured with `UPDATE_MODS_ON_START: "true"` by default.

To enable automatic mod downloads:

1. Create a sealed secret with your Factorio credentials (see
   `scripts/create-mod-credentials-secret.sh`)
2. Configure mods in [k8s/config/mod-list.yaml](k8s/config/mod-list.yaml)
3. The initContainer will inject credentials and download mods on startup

Credentials are stored in Kubernetes secrets (not in StatefulSet directly):

- `factorio-mod-credentials` secret contains `username` and `token` keys
- These are optionally mounted via secretKeyRef in the StatefulSet

## Security Considerations

### Network Security

**Important**: The StatefulSet uses `hostNetwork: true`, which means:

- The pod shares the node's network namespace
- All container ports are directly exposed on the node's IP
- This bypasses Kubernetes network policies
- Ensure your infrastructure firewall rules are properly configured

### RCON Password

The RCON password is auto-generated and stored in `/factorio/config/rconpw`. For
production:

```bash
# Option 1: Extract and store securely
kubectl exec -n factorio factorio-0 -- cat /factorio/config/rconpw > rconpw.txt
# Store in password manager

# Option 2: Use Kubernetes Secret (advanced)
kubectl create secret generic factorio-rcon \
  --from-literal=password='your-secure-password' \
  -n factorio

# Mount secret in StatefulSet and override default
```

### Game Password

Set a game password in [server-settings.yaml](k8s/config/server-settings.yaml):

```json
"game_password": "your-secure-password",
```

### Admin Management

Admins are managed in `/factorio/config/server-adminlist.json`:

```bash
# View current admins
kubectl exec -n factorio factorio-0 -- cat /factorio/config/server-adminlist.json

# Add admin via RCON (while playing)
# Connect via RCON and run: /promote <playername>
```

## Cost Considerations

- **Storage**: 20Gi persistent volume (cost varies by provider)
- **Resources**: Uses existing cluster capacity (2 CPU, 2-4Gi RAM)
- **Network**: No additional costs (NodePort uses cluster IPs)

**Total**: Minimal additional cost (primarily storage)

## Support

- **Factorio Docker**: https://github.com/factoriotools/factorio-docker
- **Factorio Wiki**: https://wiki.factorio.com/
- **Official Forums**: https://forums.factorio.com/

## License

This deployment configuration is provided as-is for personal/private server use.
Factorio game content is © Wube Software LTD.
