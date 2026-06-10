# Compte Rendu — Exercice 1 : Mettre Alloy en route

**Date :** 2026-06-10  
**Auteur :** mqnguyen  
**Durée effective :** ~30 min  
**Section TP :** Fondamentaux  

***

## Objectif

Déployer Grafana Alloy dans un cluster Kubernetes (kind) via Helm, dans un namespace dédié `observability`, avec un pipeline OTLP minimal relié à un exporteur debug. Vérifier l'accessibilité de l'UI de débogage sur le port 12345.

***

## Environnement

| Élément | Valeur |
|---|---|
| OS | Debian (VM) |
| Cluster | kind `otel-lab` |
| Namespace | `observability` |
| Alloy version | v1.16.3 |
| Config-reloader | prometheus-config-reloader v0.91.0 |
| Helm chart | grafana/alloy |

***

## Arborescence du dossier

```
~/tp-observabilite/otel-alloy-ex01/
├── alloy-values.yaml     ← configuration Helm + pipeline Alloy
└── COMPTE_RENDU.md       ← ce fichier
```

***

## Concepts clés abordés

### OpenTelemetry & Alloy

Grafana Alloy est le successeur de Grafana Agent. Il se configure via des **blocs typés câblés entre eux** (syntaxe anciennement appelée "River", inspirée du HCL Terraform). Une pipeline Alloy suit le modèle :

```
Receiver(s)  →  Processor(s)  →  Exporter(s)
```

Le protocole **OTLP** (OpenTelemetry Protocol) est le transport universel d'OpenTelemetry. Il supporte deux modes :
- **gRPC** sur le port `4317` — streaming, compact, performant
- **HTTP** sur le port `4318` — compatible firewalls, facile à déboguer

### Niveaux de stabilité Alloy

Depuis Alloy v1.14+, chaque composant possède un niveau de maturité :

| Niveau | Signification | Autorisé par défaut |
|---|---|---|
| `generally-available` | Stable, production-ready | ✅ Oui |
| `public-preview` | En cours de stabilisation | ❌ Non |
| `experimental` | Fonctionnel, API susceptible de changer | ❌ Non |

Le flag `--stability.level=experimental` est nécessaire pour autoriser les composants expérimentaux comme `otelcol.exporter.debug`.

***

## Pipeline configurée

```
otelcol.receiver.otlp "default"
  ├── gRPC : 0.0.0.0:4317
  └── HTTP : 0.0.0.0:4318
          │
          ▼ (metrics, logs, traces)
otelcol.exporter.debug "default"
  └── verbosity: "detailed"
```

***

## Fichier de configuration — `alloy-values.yaml`

```yaml
alloy:
  # Activer les composants expérimentaux (nécessaire pour otelcol.exporter.debug)
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
      // Receiver OTLP : écoute gRPC (4317) et HTTP (4318)
      otelcol.receiver.otlp "default" {
        grpc { endpoint = "0.0.0.0:4317" }
        http { endpoint = "0.0.0.0:4318" }
        output {
          metrics = [otelcol.exporter.debug.default.input]
          logs    = [otelcol.exporter.debug.default.input]
          traces  = [otelcol.exporter.debug.default.input]
        }
      }

      // Exporteur debug : affiche les signaux reçus dans les logs Alloy
      otelcol.exporter.debug "default" {
        verbosity = "detailed"
      }
```

***

## Commandes exécutées

### 1. Création du namespace

```bash
kubectl create namespace observability
```

### 2. Ajout du repo Helm Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 3. Installation initiale d'Alloy (tentative échouée)

```bash
helm install alloy grafana/alloy \
  --namespace observability \
  --values alloy-values.yaml
```

> ⚠️ Cette première installation a produit une erreur (voir section Problèmes rencontrés).

### 4. Correction et mise à jour via Helm upgrade

```bash
helm upgrade alloy grafana/alloy \
  --namespace observability \
  --values alloy-values.yaml
```

### 5. Vérification du déploiement

```bash
kubectl -n observability get pods
kubectl -n observability get svc alloy
```

### 6. Accès à l'UI Alloy

```bash
kubectl -n observability port-forward svc/alloy 12345:12345 &
curl -s http://localhost:12345/-/ready
```

***

## Résultats observés

### Service Alloy

```
NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                       AGE
alloy   ClusterIP   10.96.244.253   <none>        12345/TCP,4317/TCP,4318/TCP   20s
```

Les trois ports sont bien exposés : `12345` (UI), `4317` (OTLP gRPC), `4318` (OTLP HTTP).

### État des pods (après correction)

```
NAME          READY   STATUS    RESTARTS   AGE
alloy-xxxxx   2/2     Running   0          Xm
```

Les **deux conteneurs** (`alloy` + `config-reloader`) sont en état `Running`.

### Vérification de l'UI

```
curl -s http://localhost:12345/-/ready
→ ready
```

***

## Problèmes rencontrés

### Problème 1 : CrashLoopBackOff — composant expérimental refusé

**Symptôme :** Le pod affichait `1/2 CrashLoopBackOff` dès le démarrage.

**Diagnostic :**
```bash
kubectl -n observability logs alloy-xtb4w -c alloy --previous
```

**Erreur dans les logs :**
```
Error: /etc/alloy/config.alloy:13:1: component "otelcol.exporter.debug"
is at stability level "experimental", which is below the minimum allowed
stability level "generally-available". Use --stability.level command-line
flag to enable "experimental" features.
```

**Cause :** Alloy v1.16.3 bloque par défaut les composants de niveau `experimental`. `otelcol.exporter.debug` en fait partie.

**Solution :** Ajout de `--stability.level=experimental` dans `extraArgs` du `alloy-values.yaml`, puis `helm upgrade`.

***

## Graphe de composants (UI Alloy :12345)

L'UI affiche le graphe orienté acyclique (DAG) en temps réel :

```
[ otelcol.receiver.otlp.default ]
           │
           ├── metrics ──┐
           ├── logs    ──┼──▶ [ otelcol.exporter.debug.default ]
           └── traces  ──┘
```

Chaque composant affiche son état (✅ healthy), son débit (signaux/s) et ses erreurs éventuelles.

***

## Conclusion

L'exercice 1 est validé. Grafana Alloy est déployé et opérationnel dans le namespace `observability` avec :

- Un receiver OTLP actif sur les ports 4317 (gRPC) et 4318 (HTTP)
- Un exporteur debug en mode `detailed` câblé aux 3 signaux
- L'UI de débogage accessible sur `:12345`

**Point clé à retenir :** La gestion des niveaux de stabilité Alloy est un mécanisme de protection en production. En lab, `--stability.level=experimental` est nécessaire pour utiliser des composants comme `otelcol.exporter.debug`. En production, on privilégiera des exporteurs `generally-available`.

L'exercice 2 portera sur l'envoi de données OTLP réelles vers Alloy à l'aide de `telemetrygen`.