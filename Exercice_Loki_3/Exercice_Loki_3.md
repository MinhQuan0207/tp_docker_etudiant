# TP Observabilité Loki — Exercice 3 : Rotation des logs et découverte dynamique

## Objectif
Configurer Alloy pour suivre un répertoire de logs et garantir une collecte continue lors d'une rotation de fichiers sans perte ni doublons.

---

## Commandes exécutées

```bash
# Lancement de la stack
docker compose up -d

# Générateur de logs (terminal 2)
while true; do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) level=info msg=\"requete traitee\" user_id=$((RANDOM % 100)) status=200" >> logs/apps/app.log
  sleep 1
done

# Rotation simulée
mv logs/apps/app.log logs/apps/app.log.1
touch logs/apps/app.log

# Vérification de la continuité
tail -f logs/apps/app.log
wc -l logs/apps/app.log.1
```

---

## Contenu des fichiers clés

### `docker-compose.yml`

```yaml
networks:
  loki:
    driver: bridge

services:
  loki:
    image: grafana/loki:3.0.0
    container_name: loki
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    networks:
      - loki

  alloy:
    image: grafana/alloy:latest
    container_name: alloy
    user: root
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./logs:/var/log/apps
    command: run /etc/alloy/config.alloy
    depends_on:
      - loki
    networks:
      - loki

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    depends_on:
      - loki
    networks:
      - loki
```

### `alloy/config.alloy`

```hcl
// --- Collecte Docker ---
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

loki.source.docker "docker_logs" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.process.relabel.receiver]
}

loki.process "relabel" {
  stage.docker {}
  stage.static_labels {
    values = {
      job         = "docker",
      environment = "development",
    }
  }
  forward_to = [loki.write.default.receiver]
}

// --- Collecte des fichiers de logs locaux ---
local.file_match "app_logs" {
  path_targets = [{
    __path__    = "/var/log/apps/apps/*.log",
    job         = "app-files",
    environment = "development",
  }]
}

loki.source.file "app_files" {
  targets    = local.file_match.app_logs.targets
  forward_to = [loki.write.default.receiver]
}

// --- Envoi vers Loki ---
loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

---

## Résultats observés

- Logs du fichier visibles dans Grafana avec `{job="app-files"}`
- Après rotation (`mv app.log app.log.1` + `touch app.log`), les logs continuent d'arriver sans interruption
- `wc -l logs/apps/app.log.1` : **430 lignes** conservées dans l'ancien fichier
- Aucun trou visible dans la timeline Grafana

---

## Difficultés rencontrées

### Problème — Volume monté avec un niveau de dossier en trop
**Erreur :** `{job="app-files"}` ne retournait aucun log dans Grafana.

**Cause :** Le volume `./logs:/var/log/apps` montait le dossier `logs/` entier, mais les fichiers étaient dans `logs/apps/`. Alloy cherchait donc dans `/var/log/apps/*.log` alors que les fichiers étaient dans `/var/log/apps/apps/*.log`.

**Diagnostic :**
```bash
docker exec alloy ls /var/log/apps/
# Résultat : apps  (un sous-dossier supplémentaire)
```

**Correction :** Mise à jour du `__path__` dans `config.alloy` :
```hcl
__path__ = "/var/log/apps/apps/*.log"
```

---

## Conclusion
Alloy assure une collecte continue lors des rotations de fichiers grâce au position tracking par inode. Lors du renommage de `app.log` en `app.log.1`, Alloy a détecté le nouveau fichier `app.log` via le glob `*.log` et a repris la collecte immédiatement, sans perte de données ni doublons.