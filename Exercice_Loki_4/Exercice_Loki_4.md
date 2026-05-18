# TP Observabilité Loki — Exercice 4 : Pipelines Alloy et Parsing à la source

## Objectif
Transformer et filtrer des logs JSON dans Alloy avant envoi à Loki : extraction de champs, suppression des lignes debug.

## Commandes exécutées

```bash
docker compose up -d

# Générateur de logs JSON (terminal 2)
while true; do
  LEVEL=$(shuf -n1 -e debug info info info error)
  USER_ID=$((RANDOM % 100))
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$LEVEL\",\"msg\":\"requete traitee\",\"user_id\":$USER_ID,\"status\":200}" >> logs/apps/app.log
  sleep 1
done

# Vérification du filtrage
grep -c '"level":"debug"' logs/apps/app.log
```

## Contenu de alloy/config.alloy

```hcl
// --- Collecte des fichiers JSON ---
local.file_match "json_logs" {
  path_targets = [{
    __path__    = "/var/log/apps/*.log",
    job         = "app-json",
    environment = "development",
  }]
}

loki.source.file "json_files" {
  targets    = local.file_match.json_logs.targets
  forward_to = [loki.process.parse_json.receiver]
}

loki.process "parse_json" {

  // 1. Parser le JSON de chaque ligne
  stage.json {
    expressions = {
      level   = "level",
      user_id = "user_id",
      msg     = "msg",
    }
  }

  // 2. Promouvoir level et user_id en labels temporaires
  stage.labels {
    values = {
      level   = "level",
      user_id = "user_id",
    }
  }

  // 3. Supprimer toutes les lignes debug
  stage.drop {
    source = "level"
    value  = "debug"
  }

  // 4. Ajouter un label statique job
  stage.static_labels {
    values = {
      job = "app-json",
    }
  }

  // 5. Supprimer user_id des labels indexés (forte cardinalité !)
  stage.label_drop {
    values = ["user_id"]
  }

  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

## Résultats observés

- [ ] Logs visibles dans Grafana avec `{job="app-json"}`
- [ ] Requête `{job="app-json"} |= "debug"` retourne 0 résultats
- [ ] Labels `level` visible dans le Label Browser avec valeurs `info` et `error`
- [ ] Label `user_id` absent du Label Browser (supprimé après usage)

## Difficultés rencontrées
<!-- ... -->

## Conclusion
Le pipeline Alloy parse, filtre et enrichit les logs JSON à la source.
Les lignes debug sont supprimées avant envoi, réduisant le volume stocké dans Loki.