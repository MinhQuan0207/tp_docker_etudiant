# Compte Rendu — Exercice 6 : Métriques OTel, chaîne de traitement et clustering Alloy

**Date :** 2026-06-10
**Auteur :** mqnguyen
**Durée effective :** ~30 min
**Section TP :** Prometheus / Mimir — Challenge

---

## Objectif

Faire transiter les métriques OTLP de l'app Flask (`demo`) vers Mimir via la conversion
OTel → Prometheus, enrichies de deux attributs personnalisés (`team=platform` et
`deployment.environment=lab`). Vérifier dans Mimir que les séries applicatives portent
bien ces attributs.

Le bonus (clustering Alloy sur 2 répliques en StatefulSet) n'a pas été réalisé.

---

## Environnement

| Élément | Valeur |
|---|---|
| Cluster | kind `otel-lab` |
| Namespace | `observability` |
| Pod Alloy | `alloy-2sljb` (DaemonSet) |
| Pod Mimir | `mimir-c6ccbfdfb-42rt8` |
| App Flask | `demo` (namespace `default`) |
| Port Mimir | `9009` |
| Port Alloy UI | `12345` |

---

## Concepts clés abordés

### Conversion OTel → Prometheus : le composant bridge

Le composant `otelcol.exporter.prometheus` est un **pont** (bridge) entre le monde
OpenTelemetry et le monde Prometheus natif dans Alloy. Il reçoit des métriques OTLP
et les expose à un receiver `prometheus.*` pour qu'elles puissent être envoyées via
`prometheus.remote_write`.

C'est la seule façon de brancher une pipeline OTLP sur un `prometheus.remote_write`.
Sans ce bridge, les métriques OTLP et les métriques Prometheus sont deux mondes séparés
dans Alloy.

```
otelcol.exporter.prometheus "to_mimir" {
  forward_to = [prometheus.remote_write.mimir.receiver]
}
```

### Séparation des pipelines par type de signal

L'exercice exige que **seules les métriques** soient reroutées vers Mimir — les logs et
traces continuent vers l'exporteur debug. Cela se fait en branchant chaque type de signal
vers une sortie différente dans le `receiver.otlp` :

```alloy
otelcol.receiver.otlp "default" {
  output {
    logs   = [otelcol.processor.batch.default.input]   // → debug
    traces = [otelcol.processor.batch.default.input]   // → debug
    metrics = [otelcol.processor.attributes.metrics.input] // → Mimir
  }
}
```

### Action insert sur les attributs

L'action `insert` ajoute l'attribut uniquement s'il n'existe pas déjà.
C'est la bonne action pour enrichir sans écraser une valeur applicative existante.

---

## Arborescence du dossier

```
~/tp-observabilite/otel-alloy-ex06/
└── alloy-values.yaml    ← pipeline étendue avec bridge OTel→Prometheus
```

---

## Pipeline finale complète

```
otelcol.receiver.otlp "default"
    │
    ├── logs/traces ──► otelcol.processor.batch "default"
    │                           │
    │                   otelcol.processor.attributes "default"
    │                   (deployment.environment=lab)
    │                           │
    │                   otelcol.exporter.debug "default"
    │
    └── metrics ────► otelcol.processor.attributes "metrics"
                      (team=platform, deployment.environment=lab)
                                  │
                      otelcol.exporter.prometheus "to_mimir"
                                  │
                      prometheus.remote_write "mimir"   ◄── aussi utilisé par
                                  │                         prometheus.scrape "node_exporter"
                             Mimir :9009
```

---

## Configuration alloy-values.yaml

```yaml
alloy:
  extraArgs:
    - --stability.level=experimental

  extraPorts:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP

  configMap:
    content: |
      otelcol.receiver.otlp "default" {
        grpc { endpoint = "0.0.0.0:4317" }
        http { endpoint = "0.0.0.0:4318" }
        output {
          logs    = [otelcol.processor.batch.default.input]
          traces  = [otelcol.processor.batch.default.input]
          metrics = [otelcol.processor.attributes.metrics.input]
        }
      }

      otelcol.processor.batch "default" {
        output {
          logs   = [otelcol.processor.attributes.default.input]
          traces = [otelcol.processor.attributes.default.input]
        }
      }

      otelcol.processor.attributes "default" {
        action {
          key    = "deployment.environment"
          value  = "lab"
          action = "insert"
        }
        output {
          logs   = [otelcol.exporter.debug.default.input]
          traces = [otelcol.exporter.debug.default.input]
        }
      }

      otelcol.exporter.debug "default" {
        verbosity = "detailed"
      }

      otelcol.processor.attributes "metrics" {
        action {
          key    = "team"
          value  = "platform"
          action = "insert"
        }
        action {
          key    = "deployment.environment"
          value  = "lab"
          action = "insert"
        }
        output {
          metrics = [otelcol.exporter.prometheus.to_mimir.input]
        }
      }

      otelcol.exporter.prometheus "to_mimir" {
        forward_to = [prometheus.remote_write.mimir.receiver]
      }

      discovery.kubernetes "node_exporter" {
        role = "endpoints"
        namespaces { names = ["observability"] }
        selectors {
          role  = "endpoints"
          label = "app.kubernetes.io/name=prometheus-node-exporter"
        }
      }

      discovery.relabel "node_exporter" {
        targets = discovery.kubernetes.node_exporter.targets
        rule {
          source_labels = ["__meta_kubernetes_endpoint_port_name"]
          regex         = "metrics"
          action        = "keep"
        }
        rule {
          source_labels = ["__meta_kubernetes_node_name"]
          target_label  = "node"
        }
      }

      prometheus.scrape "node_exporter" {
        targets         = discovery.relabel.node_exporter.output
        forward_to      = [prometheus.remote_write.mimir.receiver]
        scrape_interval = "30s"
        job_name        = "node-exporter"
      }

      prometheus.remote_write "mimir" {
        endpoint {
          url = "http://mimir.observability.svc:9009/api/v1/push"
        }
      }
```

---

## Commandes exécutées

### 1. Mise en place du dossier de travail

```bash
cd ~/tp-observabilite/otel-alloy-ex06
cp ~/tp-observabilite/otel-alloy-ex05/alloy-values.yaml .
```

### 2. Édition du fichier alloy-values.yaml

Modification des sorties `metrics` du receiver OTLP vers un nouveau
`otelcol.processor.attributes "metrics"` dédié, suivi du bridge
`otelcol.exporter.prometheus "to_mimir"`.

### 3. Déploiement Helm

```bash
helm upgrade alloy grafana/alloy \
  --namespace observability \
  --values alloy-values.yaml
```

### 4. Génération de trafic

```bash
for i in $(seq 1 30); do curl -s http://localhost:5000/ > /dev/null; done
```

### 5. Vérification dans Mimir

```bash
sleep 20
curl -s "http://localhost:9009/prometheus/api/v1/query?query=http_server_duration_milliseconds_count" | \
  python3 -m json.tool | grep -E "team|deployment|__name__|value" | head -20
```

---

## Résultat observé

La commande de vérification a retourné :

```text
"__name__": "http_server_duration_milliseconds_count",
"deployment_environment": "lab",
"team": "platform"
"value": [
"__name__": "http_server_duration_milliseconds_count",
"deployment_environment": "lab",
"team": "platform"
"value": [
```

Deux séries `http_server_duration_milliseconds_count` sont visibles dans Mimir,
toutes deux portant les attributs ajoutés par le processor :
- `team="platform"` ✅
- `deployment_environment="lab"` ✅

> Note : OTel convertit les points `.` en `_` lors de la conversion vers Prometheus.
> `deployment.environment` devient donc `deployment_environment` dans Mimir.

---

## Bonus — Clustering Alloy (non réalisé)

Le clustering Alloy nécessite de passer le controller en `StatefulSet` avec 2 répliques.
Cette partie n'a pas été réalisée dans le cadre de ce TP, mais voici le principe :

```yaml
controller:
  type: statefulset
  replicas: 2

alloy:
  clustering:
    enabled: true
```

Vérification attendue :

```bash
curl -s http://localhost:12345/api/v0/web/cluster/peers | python3 -m json.tool
# Attendu : 2 peers, both "alive"
```

Sur un cluster kind à 1 nœud, les 2 pods peuvent rester en `Pending` faute de ressources.
Dans un environnement de production, le clustering permet de distribuer la charge de scrape
entre les répliques Alloy.

---

## Ce qu'il faut retenir

- `otelcol.exporter.prometheus` est le **bridge** obligatoire pour passer du monde OTLP
  au monde Prometheus dans Alloy — sans lui, `prometheus.remote_write` ne peut pas
  recevoir de métriques OTLP.
- Le receiver `prometheus.remote_write.NAME.receiver` est le point d'entrée Prometheus
  natif qui reçoit les métriques converties par le bridge.
- Le routage par type de signal (metrics vs logs/traces) se configure dans les `output`
  du receiver OTLP — chaque type peut pointer vers un composant différent.
- OTel convertit les noms d'attributs : les `.` deviennent `_` en Prometheus
  (`deployment.environment` → `deployment_environment`).
- Un seul `prometheus.remote_write` peut recevoir plusieurs sources (bridge OTel +
  scrape node-exporter) — il n'est pas nécessaire d'en créer un par source.
