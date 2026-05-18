# TP Observabilité Loki — Exercice 2 : Labels et Relabeling

## Objectif
Manipuler les labels dans Grafana Alloy : suppression, ajout statique et extraction dynamique.

## Commandes exécutées

```bash
docker compose up -d
docker compose logs alloy -f
```

## Contenu de alloy/config.alloy

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

## Résultats observés

- [ ] Label `environment=development` visible dans Grafana Explore
- [ ] Label `loglevel` extrait dynamiquement et visible dans le Label Browser
- [ ] Label `filename` absent du Label Browser
- [ ] Requête `{job="docker", loglevel="error"}` retourne des résultats

## Difficultés rencontrées
<!-- ... -->

## Conclusion
Le pipeline de relabeling Alloy permet de contrôler précisément les labels envoyés à Loki,
garantissant une cardinalité faible et un index optimisé.