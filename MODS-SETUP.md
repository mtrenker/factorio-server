# Adding Mods to Factorio Server

Mods are managed through the `mod-list.json` ConfigMap and can be automatically
downloaded from the Factorio mod portal.

## Quick Start

1. **Edit the mod list** in [k8s/config/mod-list.yaml](k8s/config/mod-list.yaml)
2. **Commit and push** changes
3. **Wait for ArgoCD sync** or restart:
   `kubectl rollout restart statefulset/factorio -n factorio`

## Mod List Format

```json
{
    "mods": [
        {
            "name": "base",
            "enabled": true
        },
        {
            "name": "space-age",
            "enabled": true
        },
        {
            "name": "mod-name-here",
            "enabled": true
        }
    ]
}
```

## Finding Mod Names

1. Visit https://mods.factorio.com/
2. Find the mod you want
3. Use the **internal name** from the URL (e.g., `Krastorio2` for
   https://mods.factorio.com/mod/Krastorio2)

## Example: Popular Mods

```json
{
    "mods": [
        {
            "name": "base",
            "enabled": true
        },
        {
            "name": "space-age",
            "enabled": true
        },
        {
            "name": "Krastorio2",
            "enabled": true
        },
        {
            "name": "space-exploration",
            "enabled": true
        },
        {
            "name": "RealisticReactors",
            "enabled": true
        }
    ]
}
```

## Automatic Mod Installation

The server is configured with `UPDATE_MODS_ON_START=true`, which means:

- ✅ Mods listed in `mod-list.json` will be **automatically downloaded** on
  server start
- ✅ Existing mods will be **updated** to latest compatible versions
- ✅ Missing mods will be **installed** automatically

## Disabling Mods

Set `"enabled": false` for any mod you want to keep but temporarily disable:

```json
{
    "name": "Krastorio2",
    "enabled": false
}
```

## Manual Mod Upload

If you want to upload mod files manually (e.g., for private/unreleased mods):

```bash
# Copy mod .zip file to the server
kubectl cp ./my-mod_1.0.0.zip factorio/factorio-0:/factorio/mods/

# Restart the server
kubectl rollout restart statefulset/factorio -n factorio
```

## Troubleshooting

### Mods Not Loading

Check the logs for mod-related errors:

```bash
kubectl logs -n factorio factorio-0 | grep -i mod
```

### Mod Dependencies

Factorio will automatically download required dependencies. If there are
conflicts, check the logs for error messages.

### Version Conflicts

If mods aren't compatible with your Factorio version:

- Use specific Factorio version tags (e.g.,
  `factoriotools/factorio:1.1.104-rootless`)
- Check mod compatibility on the mod portal

## Mod Portal Credentials (Optional)

For premium mods, faster downloads, or private mods, you can add your Factorio
credentials:

### Quick Setup

1. **Run the script:**
   ```bash
   # Interactive mode
   ./scripts/create-mod-credentials-secret.sh

   # Or with arguments
   ./scripts/create-mod-credentials-secret.sh 'your-username' 'your-token'
   ```

2. **Get your token** from https://factorio.com/profile

3. **Enable the secret:**
   ```bash
   # Uncomment the line in k8s/config/kustomization.yaml
   sed -i 's/# - sealed-secret-mod-credentials.yaml/- sealed-secret-mod-credentials.yaml/' k8s/config/kustomization.yaml
   ```

4. **Commit and push:**
   ```bash
   git add k8s/config/sealed-secret-mod-credentials.yaml k8s/config/kustomization.yaml
   git commit -m "Add mod portal credentials"
   git push
   ```

The server will automatically use these credentials for downloading mods!
