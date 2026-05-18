# TP Observabilité Loki — Exercice 1 : Déploiement mono-nœud

## Objectif
Déployer la stack **Loki + Grafana + Grafana Alloy** via `docker compose` et valider le flux de logs de bout en bout dans Grafana Explore.

***

## Commandes exécutées

```bash
# Lancement de la stack
docker compose up -d

# Vérification de l'état des services
docker compose ps

# Diagnostic des logs Alloy
docker compose logs alloy

# Vérification de la réception des labels par Loki
curl -s "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool

# Redémarrage après correction de configuration
docker compose down
docker compose up -d
docker compose restart alloy
```

***

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
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

loki.source.docker "docker_logs" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.process.add_labels.receiver]
}

loki.process "add_labels" {
  stage.static_labels {
    values = {
      job = "docker",
    }
  }

  stage.docker {}

  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

***

## Résultats observés

- Les 3 services démarrés (`docker compose ps` : `alloy`, `grafana`, `loki` à l'état `Up`)
- Datasource Loki connectée dans Grafana (`Connections > Data sources > Save & test` ✅)
- API Loki retourne les labels attendus :
```json
{
    "status": "success",
    "data": ["container", "job", "compose_project", ...]
}
```
- Logs visibles dans **Grafana Explore** avec la requête LogQL :
```logql
{job="docker"}
```

***

## Difficultés rencontrées

### Problème 1 — Socket Docker inaccessible depuis Alloy
**Erreur :** `Cannot connect to the Docker daemon at unix:///var/run/docker.sock`

**Cause :** Le socket Docker de l'hôte n'était pas monté dans le conteneur Alloy.

**Correction :** Ajout du volume `/var/run/docker.sock:/var/run/docker.sock` et du paramètre `user: root` dans le service `alloy` du `docker-compose.yml`.

***

### Problème 2 — Loki refuse les logs sans labels
**Erreur :** `server returned HTTP status 400 Bad Request: error at least one label pair is required per stream`

**Cause :** Alloy envoyait des logs à Loki sans aucun label. Loki exige au minimum un label par stream.

**Correction :** Ajout d'un composant `loki.process` dans `config.alloy` avec un `stage.static_labels` définissant `job = "docker"`, et d'un `stage.docker {}` pour enrichir automatiquement les logs avec les métadonnées des conteneurs.

***

## Conclusion
La stack Loki est opérationnelle. Grafana Alloy collecte les logs des conteneurs Docker via le socket Unix, les enrichit avec des labels (`job`, métadonnées Docker), et les achemine vers Loki. Grafana visualise ces logs en temps réel via LogQL, validant le pipeline de collecte de bout en bout.