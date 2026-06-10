# Compte Rendu — Exercice 2 : Envoyer des données OTLP avec telemetrygen

**Date :** 2026-06-10  
**Auteur :** mqnguyen  
**Durée effective :** ~20 min  
**Section TP :** Fondamentaux  

***

## Objectif

Utiliser `telemetrygen` comme Pod Kubernetes éphémère pour pousser des données OTLP (traces, métriques, logs) vers Alloy via gRPC (port 4317) et confirmer la réception dans les logs du DaemonSet Alloy.

***

## Environnement

| Élément | Valeur |
|---|---|
| Cluster | kind `otel-lab` |
| Namespace Alloy | `observability` |
| Pod Alloy | `alloy-2sljb` (DaemonSet) |
| Endpoint cible | `alloy.observability.svc:4317` (gRPC, insecure) |
| Image telemetrygen | `ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest` |

***

## Arborescence du dossier

```
~/tp-observabilite/otel-alloy-ex02/
└── COMPTE_RENDU.md    ← ce fichier (pas de fichier de config : pods éphémères)
```

> Les pods `telemetrygen` sont lancés avec `kubectl run --rm` : aucun manifeste persistant n'est nécessaire.

***

## Concepts clés abordés

### DNS interne Kubernetes

Le DNS interne Kubernetes suit le format `<service>.<namespace>.svc:<port>`. Alloy étant déployé dans le namespace `observability` avec un Service nommé `alloy`, l'endpoint est : `alloy.observability.svc:4317`.

Tout pod du cluster peut résoudre ce nom sans configuration supplémentaire, ce qui permet aux pods `telemetrygen` lancés dans le namespace `default` d'atteindre Alloy dans `observability`.

### Structure d'un signal OTLP reçu

Les logs Alloy (exporteur debug en mode `detailed`) affichent la structure complète de chaque signal. Exemple pour une trace :

```
ResourceSpans #0
  Resource attributes:
    -> service.name: Str(telemetrygen)     ← identifie le service émetteur
  ScopeSpans #0
    Span #0
      Trace ID : 4456b45c9011db8f6f6ad051aa95cbef
      Name     : okey-dokey-0              ← span enfant (Server)
      Kind     : Server
    Span #1
      Name     : lets-go                   ← span parent (Client)
      Kind     : Client
```

Chaque **trace** est composée de **spans** parent/enfant identifiés par un `trace_id` commun et des `span_id` distincts.

***

## Commandes exécutées

### 1. Vérification préalable d'Alloy

```bash
curl -s http://localhost:12345/-/ready
# Résultat : Alloy is ready.
```

### 2. Envoi de traces (10 traces)

```bash
kubectl run telemetrygen-traces \
  --rm -i --tty --restart=Never \
  --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  -- traces \
  --otlp-endpoint=alloy.observability.svc:4317 \
  --otlp-insecure \
  --traces 10
```

### 3. Envoi de métriques (5 secondes)

```bash
kubectl run telemetrygen-metrics \
  --rm -i --tty --restart=Never \
  --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  -- metrics \
  --otlp-endpoint=alloy.observability.svc:4317 \
  --otlp-insecure \
  --duration 5s
```

### 4. Envoi de logs (10 logs)

```bash
kubectl run telemetrygen-logs \
  --rm -i --tty --restart=Never \
  --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  -- logs \
  --otlp-endpoint=alloy.observability.svc:4317 \
  --otlp-insecure \
  --logs 10
```

### 5. Vérification dans les logs Alloy

```bash
kubectl -n observability logs daemonset/alloy --tail=300 | \
  grep -E "ResourceSpans|ResourceMetrics|ResourceLogs" | head -20
```

***

## Résultats observés

### Signaux reçus confirmés

| Signal | Quantité envoyée | Reçu dans Alloy | Détail |
|---|---|---|---|
| **Traces** | 10 | ✅ `ResourceSpans` visible | `service.name=telemetrygen`, spans `lets-go` / `okey-dokey-0` |
| **Métriques** | 6 (gauge `gen`) | ✅ `ResourceMetrics` visible | Valeurs 0→5, type Gauge |
| **Logs** | 10 | ✅ `ResourceLogs` visible | `severity=Info`, body="the message" |

### Extrait des logs Alloy — Traces

```
ResourceSpans #0
Resource attributes:
  -> service.name: Str(telemetrygen)
Span #0  Name: okey-dokey-0  Kind: Server
Span #1  Name: lets-go       Kind: Client
component_id=otelcol.exporter.debug.default
```

### Extrait des logs Alloy — Métriques

```
ResourceMetrics #0
Resource attributes:
  -> service.name: Str(telemetrygen)
Metric: gen  DataType: Gauge  Values: 0 → 5
component_id=otelcol.exporter.debug.default
```

***

## Problèmes rencontrés

### Erreur `deployments.apps "alloy" not found`

**Cause :** Alloy est déployé en **DaemonSet** et non en Deployment. La commande `logs deploy/alloy` échoue car le type de ressource est incorrect.

**Solution :** Utiliser `daemonset/alloy` à la place :

```bash
kubectl -n observability logs daemonset/alloy --tail=300
```

***

## Conclusion

Les 3 types de signaux OTLP (traces, métriques, logs) ont été envoyés avec succès depuis des pods Kubernetes éphémères vers Alloy via gRPC (port 4317).

**Points clés retenus :**

- Le DNS interne Kubernetes permet la résolution cross-namespace sans configuration supplémentaire
- L'exporteur `debug` en mode `detailed` affiche la structure complète de chaque signal OTLP, très utile pour valider une pipeline avant de connecter un vrai backend
- Alloy est déployé en **DaemonSet** par le chart Helm officiel : utiliser `daemonset/alloy` et non `deploy/alloy` dans les commandes `kubectl logs`

L'exercice 3 portera sur le déploiement d'une vraie application Flask auto-instrumentée OpenTelemetry.